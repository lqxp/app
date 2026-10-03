// QXCHAT-FORK of rsRPC client_connector:
// - process-scanner thread removed (QxChat runs its own detection);
// - `on_activity` hook: every native SET_ACTIVITY (set + clear) received over
//   IPC or websocket is ALSO delivered to QxChat (independent of downstream
//   bridge clients being connected);
// - no `exit(1)`: a taken bridge port degrades to hook-only mode instead of
//   killing the host app.

use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};

use crate::rsrpc_sws::{Event, EventHub, Message, Responder};

use crate::log;
use crate::rsrpc::{
    cmd::{Activity, ActivityCmd, ActivityPayload},
    ActivityCallback,
};

fn empty_activity(pid: u64, socket_id: String) -> String {
    format!(
        r#"
    {{
      "activity": null,
      "pid": {pid},
      "socketId": "{socket_id}"
    }}
  "#
    )
}

#[derive(Clone)]
pub struct ClientConnector {
    server: Arc<Mutex<Option<EventHub>>>,
    pub clients: Arc<Mutex<HashMap<u64, Responder>>>,
    data_on_connect: String,

    pub ipc_event_rec: Arc<Mutex<Option<std::sync::mpsc::Receiver<ActivityCmd>>>>,
    pub ws_event_rec: Arc<Mutex<Option<std::sync::mpsc::Receiver<ActivityCmd>>>>,
    on_activity: Option<Arc<Mutex<ActivityCallback>>>,
}

impl ClientConnector {
    pub fn new(
        port: u16,
        data_on_connect: String,
        ipc_event_rec: std::sync::mpsc::Receiver<ActivityCmd>,
        ws_event_rec: std::sync::mpsc::Receiver<ActivityCmd>,
        on_activity: Option<Arc<Mutex<ActivityCallback>>>,
    ) -> ClientConnector {
        // Bridge server for downstream consumers (Discord web, custom
        // clients). Optional: when the port is taken we still run the
        // hook — QxChat's own activity feed never depends on it.
        let server = match crate::rsrpc_sws::launch(port) {
            Ok(hub) => Some(hub),
            Err(_) => {
                log!("[Client Connector] Bridge port already in use — hook-only mode");
                None
            }
        };
        ClientConnector {
            server: Arc::new(Mutex::new(server)),
            clients: Arc::new(Mutex::new(HashMap::new())),
            data_on_connect,

            ipc_event_rec: Arc::new(Mutex::new(Some(ipc_event_rec))),
            ws_event_rec: Arc::new(Mutex::new(Some(ws_event_rec))),
            on_activity,
        }
    }

    fn emit_activity(&self, activity: Option<Activity>, app_id: Option<String>) {
        if let Some(cb) = self.on_activity.as_ref() {
            if let Ok(mut cb) = cb.lock() {
                cb(activity, app_id);
            }
        }
    }

    pub fn start(&mut self) {
        let server = self.server.lock().unwrap().take();
        let clients_clone = self.clients.clone();
        let data_on_connect = self.data_on_connect.clone();

        // Downstream bridge loop (optional).
        if let Some(server) = server {
            std::thread::spawn(move || {
                loop {
                    match server.poll_event() {
                        Event::Connect(client_id, responder) => {
                            log!("[Client Connector] Client {} connected", client_id);

                            // Send initial connection data
                            responder.send(Message::Text(data_on_connect.clone()));

                            clients_clone.lock().unwrap().insert(client_id, responder);
                        }
                        Event::Disconnect(client_id) => {
                            clients_clone.lock().unwrap().remove(&client_id);
                        }
                        Event::Message(client_id, message) => {
                            log!(
                                "[Client Connector] Received message from client {}: {:?}",
                                client_id,
                                message
                            );
                            let clients = clients_clone.lock().unwrap();
                            if let Some(responder) = clients.get(&client_id) {
                                responder.send(message);
                            }
                        }
                    }
                }
            });
        } else {
            log!("[Client Connector] Bridge disabled — downstream consumers get nothing, hook still live");
        }

        // Create a thread for each reciever
        let ipc_event_rec = self.ipc_event_rec.lock().unwrap().take().unwrap();
        let ws_event_rec = self.ws_event_rec.lock().unwrap().take().unwrap();

        let mut ipc_clone = self.clone();
        let mut ws_clone = self.clone();

        std::thread::spawn(move || {
            while let Ok(mut ipc_activity) = ipc_event_rec.recv() {
                // QXCHAT-FORK: the hook fires even with zero downstream
                // clients — our own feed must not depend on observers.
                if ipc_activity.cmd == "SET_ACTIVITY" {
                    match ipc_activity.args.as_ref().and_then(|a| a.activity.clone()) {
                        Some(activity) => {
                            let app_id = ipc_activity.application_id.clone();
                            ipc_clone.emit_activity(Some(activity), app_id);
                        }
                        None => {
                            ipc_clone.emit_activity(None, ipc_activity.application_id.clone());
                        }
                    }
                }

                // if there are no client, skip
                if ipc_clone.clients.lock().unwrap().is_empty() {
                    log!("[Client Connector] No clients connected, skipping");
                    continue;
                }

                ipc_activity.fix();

                let mut args = match ipc_activity.args {
                    Some(args) => args,
                    None => {
                        log!("[Client Connector] Invalid activity command, skipping");
                        continue;
                    }
                };

                if args.activity.is_none() {
                    let pid = args.pid.unwrap_or_default();
                    // Send empty payload
                    let payload = empty_activity(pid, pid.to_string());

                    log!("[Client Connector] Sending empty payload");

                    ipc_clone.send_data(payload);

                    continue;
                }

                let activity = args.activity.as_mut();

                if let Some(activity) = activity {
                    activity.application_id = ipc_activity.application_id;

                    let payload = ActivityPayload {
                        activity: Some(activity.clone()),
                        pid: args.pid,
                        socket_id: Some(args.pid.unwrap_or(0).to_string()),
                    };

                    match serde_json::to_string(&payload) {
                        Ok(payload) => {
                            log!(
                                "[Client Connector] Sending payload for IPC activity: {:?}",
                                payload
                            );
                            ipc_clone.send_data(payload)
                        }
                        Err(err) => log!("[Client Connector] Error serializing IPC activity: {}", err),
                    };
                } else {
                    log!("[Client Connector] Invalid activity command, skipping");
                }
            }
        });

        std::thread::spawn(move || {
            while let Ok(mut ws_event) = ws_event_rec.recv() {
                if ws_event.cmd == "SET_ACTIVITY" {
                    match ws_event.args.as_ref().and_then(|a| a.activity.clone()) {
                        Some(activity) => {
                            let app_id = ws_event.application_id.clone();
                            ws_clone.emit_activity(Some(activity), app_id);
                        }
                        None => {
                            ws_clone.emit_activity(None, ws_event.application_id.clone());
                        }
                    }
                }

                // if there are no clients, skip
                if ws_clone.clients.lock().unwrap().is_empty() {
                    log!("[Client Connector] No clients connected, skipping");
                    continue;
                }

                if ws_event.cmd != "SET_ACTIVITY" {
                    // Just send the event as-is, there isn't really anything to go off of here
                    // I will change this if arRPC implements things like INVITE_BROWSER event responses, to ensure compatibility
                    let payload = serde_json::to_string(&ws_event).unwrap_or("".to_string());
                    log!("[Client Connector] Sending payload for WS event");
                    ws_clone.send_data(payload);

                    continue;
                }

                ws_event.fix();

                let mut args = match ws_event.args {
                    Some(args) => args,
                    None => {
                        log!("[Client Connector] Invalid activity command, skipping");
                        continue;
                    }
                };

                if args.activity.is_none() {
                    let pid = args.pid.unwrap_or_default();
                    // Send empty payload
                    let payload = empty_activity(pid, pid.to_string());

                    log!("[Client Connector] Sending empty payload");

                    ws_clone.send_data(payload);

                    continue;
                }

                let activity = args.activity.as_mut();

                if let Some(activity) = activity {
                    activity.application_id = ws_event.application_id;

                    let payload = ActivityPayload {
                        activity: Some(activity.clone()),
                        pid: args.pid,
                        socket_id: Some(args.pid.unwrap_or(0).to_string()),
                    };

                    match serde_json::to_string(&payload) {
                        Ok(payload) => {
                            log!(
                                "[Client Connector] Sending payload for WS activity: {:?}",
                                payload
                            );
                            ws_clone.send_data(payload)
                        }
                        Err(err) => log!("[Client Connector] Error serializing WS activity: {}", err),
                    };
                } else {
                    log!("[Client Connector] Invalid activity command, skipping");
                }
            }
        });
    }

    pub fn send_data(&mut self, data: String) {
        // Send data to all clients
        for (_, responder) in self.clients.lock().unwrap().iter() {
            responder.send(Message::Text(data.clone()));
        }
    }
}

impl Drop for ClientConnector {
    fn drop(&mut self) {
        if let Ok(mut server) = self.server.lock() {
            drop(server.take());
        }
    }
}
