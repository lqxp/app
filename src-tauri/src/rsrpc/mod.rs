//! Vendored fork of rsRPC (SpikeHD/rsRPC, MIT) — Discord-compatible local
//! RPC server embedded in QxChat.
//!
//! What changed vs upstream (`v0.28.0`):
//! - REMOVED the built-in process scanner (`server/process.rs`,
//!   `detection.rs`, scan callbacks): QxChat runs its own detection fed by
//!   the server-provided detectable list (`activity` plugin).
//! - ADDED an `on_activity` hook: every native `SET_ACTIVITY` frame received
//!   over IPC or websocket (set + clear) is also delivered to QxChat, which
//!   publishes it as the user's rich activity. This is the "real native RPC"
//!   source; the process scan stays as the fallback for silent apps.
//! - HARDENED startup: no `exit(1)`/`panic!` when ports or IPC slots are
//!   taken (e.g. real Discord running) — connectors are skipped gracefully
//!   so QxChat can never die from a socket conflict.
//!
//! Wire behavior toward connected apps is unchanged (arRPC-compatible).

use crate::log;
use server::{
    client_connector::ClientConnector, ipc::IpcConnector, ipc_utils::IpcFacilitator,
    websocket::WebsocketConnector,
};
use std::sync::{mpsc, Arc, Mutex};

pub mod cmd;
pub mod logger;
pub mod server;
pub mod url_params;

pub use cmd::{Activity, ActivityCmd};

/// `Some(activity)` on SET_ACTIVITY, `None` on clear/disconnect.
/// `Option<app_id>` is the emitter's Discord application id.
pub type ActivityCallback = dyn FnMut(Option<Activity>, Option<String>) + Send + Sync;

/// Native activity after mapping to display fields (QxChat card model).
#[derive(Debug, Clone, PartialEq)]
pub struct RpcSeenActivity {
    /// One of `game`, `app`, `media`.
    pub kind: &'static str,
    /// Display name (payload `name`, never empty).
    pub name: String,
    pub details: String,
    pub state: String,
    /// Epoch millis (`timestamps.start`, already ms after `fix()`). 0 = hidden.
    pub started_at_ms: u64,
    /// Emitter's Discord application id (resolves bare artwork keys).
    pub app_id: String,
    /// Raw artwork references (URLs, CDN keys, `mp:`/`spotify:` ids).
    pub large_image: String,
    pub small_image: String,
}

/// Trims a raw artwork reference (URLs, CDN keys, `mp:`/`spotify:` ids).
fn sanitize_artwork(value: Option<&str>) -> String {
    value.unwrap_or("").trim().chars().take(512).collect()
}

/// Maps a native SET_ACTIVITY payload to display fields.
/// - Drops our own outbound presence (`own_client_id`): without this the
///   client's "Playing QxChat" would loop back into its own feed when no
///   real Discord holds the IPC slot.
/// - Discord activity `type 2` (Listening) → `media`; otherwise `game` iff
///   the app name is a known game display name, else `app`.
/// - Unnamed payloads are dropped (nothing renderable).
pub fn map_rpc_activity(
    activity: &Activity,
    app_id: Option<&str>,
    own_client_id: &str,
    known_game_names: &std::collections::HashSet<String>,
) -> Option<RpcSeenActivity> {
    let incoming_app = app_id
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .or_else(|| activity.application_id.as_deref())
        .unwrap_or("");
    if !own_client_id.is_empty() && incoming_app == own_client_id {
        return None;
    }
    let name: String = activity
        .name
        .as_deref()
        .unwrap_or("")
        .trim()
        .chars()
        .take(64)
        .collect();
    if name.is_empty() {
        return None;
    }
    let kind = match activity.r#type {
        2 => "media",
        _ => {
            if known_game_names.contains(&name.to_lowercase()) {
                "game"
            } else {
                "app"
            }
        }
    };
    let details: String = activity
        .details
        .as_deref()
        .unwrap_or("")
        .trim()
        .chars()
        .take(64)
        .collect();
    let state: String = activity
        .state
        .as_deref()
        .unwrap_or("")
        .trim()
        .chars()
        .take(64)
        .collect();
    // Native emitters (pypresence et al.) send `start` in seconds; the
    // bridge path normalizes via `fix_timestamps()`, but this hook reads raw
    // frames — normalize here too, with the same cutoff, so the elapsed
    // clock is right. Values already in ms exceed now+100y in seconds and
    // pass through untouched.
    let started_raw = activity
        .timestamps
        .as_ref()
        .and_then(|t| t.start.as_ref())
        .map(|s| s.as_millis())
        .unwrap_or(0)
        .max(0);
    let sec_cutoff = chrono::Utc::now().timestamp() + (100 * 365 * 24 * 3600);
    let started_at_ms = if started_raw > 0 && started_raw <= sec_cutoff {
        (started_raw as u64).saturating_mul(1000)
    } else {
        started_raw as u64
    };
    let app_id: String = incoming_app.chars().take(64).collect();
    let large_image = sanitize_artwork(activity.assets.as_ref().and_then(|a| a.large_image.as_deref()));
    let small_image = sanitize_artwork(activity.assets.as_ref().and_then(|a| a.small_image.as_deref()));
    Some(RpcSeenActivity { kind, name, details, state, started_at_ms, app_id, large_image, small_image })
}

#[derive(Clone, Debug)]
pub struct RPCConfig {
    pub enable_ipc_connector: bool,
    pub enable_websocket_connector: bool,
    pub enable_secondary_events: bool,
    pub port: u16,
}

impl Default for RPCConfig {
    fn default() -> Self {
        Self {
            enable_ipc_connector: true,
            enable_websocket_connector: true,
            enable_secondary_events: true,
            port: 1337,
        }
    }
}

/// Owned connectors: dropping them would close sockets / remove socket
/// files (see `BoundListener`), so the server keeps them for life.
struct Connectors {
    _client_connector: Arc<Mutex<ClientConnector>>,
    _ipc_connector: Option<IpcConnector>,
    _ws_connector: Option<WebsocketConnector>,
}

pub struct RPCServer {
    connectors: Option<Connectors>,
    config: RPCConfig,
    on_activity: Option<Arc<Mutex<ActivityCallback>>>,
}

impl RPCServer {
    pub fn empty(config: RPCConfig) -> Self {
        Self {
            connectors: None,
            config,
            on_activity: None,
        }
    }

    /// Native activity hook. Must be set BEFORE `start()`.
    pub fn on_activity(&mut self, callback: impl FnMut(Option<Activity>, Option<String>) + Send + Sync + 'static) {
        if self.connectors.is_some() {
            log!("[RPC Server] Cannot set on_activity, connectors are already initialized");
            return;
        }
        self.on_activity = Some(Arc::new(Mutex::new(callback)));
    }

    pub fn start(&mut self) {
        let (ipc_event_sender, ipc_event_receiver) = mpsc::channel::<ActivityCmd>();
        let (ws_event_sender, ws_event_receiver) = mpsc::channel::<ActivityCmd>();

        let client_connector = Arc::new(Mutex::new(ClientConnector::new(
            self.config.port,
            server::utils::CONNECTION_REPONSE.to_string(),
            ipc_event_receiver,
            ws_event_receiver,
            self.on_activity.clone(),
        )));
        client_connector.lock().unwrap().start();

        let ipc_connector = if self.config.enable_ipc_connector {
            match IpcConnector::new(ipc_event_sender) {
                Some(mut connector) => {
                    log!("[RPC Server] Starting IPC connector...");
                    connector.start();
                    Some(connector)
                }
                None => {
                    log!("[RPC Server] No free IPC slot (Discord running?) — inbound socket RPC disabled, scan fallback applies.");
                    None
                }
            }
        } else {
            None
        };

        let ws_connector = if self.config.enable_websocket_connector || self.config.enable_secondary_events {
            log!("[RPC Server] Starting websocket connector...");
            match WebsocketConnector::new(ws_event_sender) {
                Some(mut connector) => {
                    connector.start(
                        self.config.enable_websocket_connector,
                        self.config.enable_secondary_events,
                    );
                    Some(connector)
                }
                None => {
                    log!("[RPC Server] No free websocket port (6463-6472) — inbound websocket RPC disabled.");
                    None
                }
            }
        } else {
            None
        };

        log!("[RPC Server] Done! Watching for activity...");
        self.connectors = Some(Connectors {
            _client_connector: client_connector,
            _ipc_connector: ipc_connector,
            _ws_connector: ws_connector,
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    fn game_names() -> HashSet<String> {
        ["baldur's gate 3", "overwatch"]
            .iter()
            .map(|s| s.to_string())
            .collect()
    }

    fn payload(name: &str, kind_type: u32) -> Activity {
        Activity {
            name: Some(name.to_string()),
            details: Some("Acte II".to_string()),
            state: Some("En groupe".to_string()),
            timestamps: Some(cmd::Timestamps {
                start: Some(cmd::TimeoutValue::default()),
                end: None,
            }),
            r#type: kind_type,
            ..Default::default()
        }
    }

    #[test]
    fn drops_own_outbound_presence() {
        let act = payload("QxChat", 0);
        assert!(map_rpc_activity(&act, Some("1548385894283608145"), "1548385894283608145", &game_names()).is_none());
        // Same payload from another app id passes through.
        assert!(map_rpc_activity(&act, Some("999"), "1548385894283608145", &game_names()).is_some());
    }

    #[test]
    fn classifies_by_type_then_name() {
        assert_eq!(
            map_rpc_activity(&payload("Spotify", 2), Some("1"), "0", &game_names()).unwrap().kind,
            "media"
        );
        assert_eq!(
            map_rpc_activity(&payload("Overwatch", 0), Some("2"), "0", &game_names()).unwrap().kind,
            "game"
        );
        assert_eq!(
            map_rpc_activity(&payload("Zed", 0), Some("3"), "0", &game_names()).unwrap().kind,
            "app"
        );
    }

    #[test]
    fn carries_artwork_and_app_id() {
        let mut act = payload("Zed", 0);
        act.application_id = Some("1263505205522337886".to_string());
        act.assets = Some(cmd::Assets {
            large_image: Some("https://example.com/icon.png".to_string()),
            large_text: None,
            small_image: Some("zed".to_string()),
            small_text: None,
        });
        let seen = map_rpc_activity(&act, None, "0", &game_names()).unwrap();
        assert_eq!(seen.app_id, "1263505205522337886");
        assert_eq!(seen.large_image, "https://example.com/icon.png");
        assert_eq!(seen.small_image, "zed");
    }

    #[test]
    fn drops_unnamed_and_truncates() {
        assert!(map_rpc_activity(&payload("   ", 0), Some("1"), "0", &game_names()).is_none());
        let long = "x".repeat(200);
        let seen = map_rpc_activity(&payload(&long, 0), Some("1"), "0", &game_names()).unwrap();
        assert_eq!(seen.name.chars().count(), 64);
        // Default TimeoutValue is 0 → hidden timer.
        assert_eq!(seen.started_at_ms, 0);
    }

    fn activity_with_start(start: i64) -> Activity {
        serde_json::from_value(serde_json::json!({
            "name": "Zed",
            "type": 0,
            "timestamps": { "start": start },
        }))
        .unwrap()
    }

    #[test]
    fn normalizes_second_timestamps_to_ms() {
        // Native emitters send seconds (pypresence et al.): the hook must
        // read them as seconds, not milliseconds (else "497035:49:14").
        let sec = chrono::Utc::now().timestamp() - 79;
        let seen =
            map_rpc_activity(&activity_with_start(sec), Some("3"), "0", &game_names()).unwrap();
        assert_eq!(seen.started_at_ms, (sec as u64) * 1000);
    }

    #[test]
    fn passes_through_millisecond_timestamps() {
        let ms = chrono::Utc::now().timestamp_millis();
        let seen =
            map_rpc_activity(&activity_with_start(ms), Some("3"), "0", &game_names()).unwrap();
        assert_eq!(seen.started_at_ms, ms as u64);
    }
}
