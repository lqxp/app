//! Discord Rich Presence for the Tauri desktop client.
//!
//! The frontend drives this module over Tauri IPC (`plugin:discord-rpc|…`)
//! from the "Advanced" settings section; the actual Discord conversation
//! happens here, in Rust, through the local Discord IPC socket
//! (`discord-rich-presence` handles the platform transports: named pipes on
//! Windows, Unix sockets on macOS/Linux).
//!
//! Presence layout (assets must exist in the Discord developer portal):
//! - large image `icon`, tooltip `QxChat v<version>`
//! - small image `windows` / `macos` / `linux` (auto-detected, toggleable),
//!   tooltip `on <Platform>`
//! - no details/state, so Discord renders exactly `Playing QxChat`
//!
//! A background worker owns the connection: it connects when enabled,
//! retries while Discord is absent, re-pushes the activity when settings
//! change, and clears + disconnects when disabled. Settings persist in
//! `discord-rpc.json` under the app-data dir (enabled by default).

use std::sync::{
    atomic::{AtomicBool, Ordering},
    mpsc, Mutex,
};
use std::time::Duration;

use discord_rich_presence::{
    activity::{Activity, Assets},
    DiscordIpc, DiscordIpcClient,
};
use tauri::{
    plugin::{Builder, TauriPlugin},
    Manager, Runtime,
};

/// Discord application (client) ID for QxChat.
const CLIENT_ID: &str = "1548385894283608145";

/// Settings file in the app-data dir.
const SETTINGS_FILE: &str = "discord-rpc.json";

/// Delay between connection attempts while Discord is unreachable.
const RETRY_DELAY: Duration = Duration::from_secs(15);

/// Periodic re-push of the activity on a live connection (keepalive).
const REFRESH_INTERVAL: Duration = Duration::from_secs(120);

/// Persisted (and IPC-visible) Rich Presence settings.
#[derive(Debug, Clone, Copy, serde::Serialize, serde::Deserialize)]
struct RpcSettings {
    enabled: bool,
    show_platform: bool,
}

impl Default for RpcSettings {
    fn default() -> Self {
        Self {
            enabled: true,
            show_platform: true,
        }
    }
}

/// Status snapshot exposed to the frontend.
#[derive(Debug, Clone, Copy, serde::Serialize)]
struct RpcStatus {
    enabled: bool,
    show_platform: bool,
    connected: bool,
}

/// Wake-up signal for the worker (settings changed → re-read + re-push).
enum WorkerMsg {
    Refresh,
}

struct RpcState {
    settings: Mutex<RpcSettings>,
    connected: AtomicBool,
    tx: Mutex<Option<mpsc::Sender<WorkerMsg>>>,
}

impl RpcState {
    fn new(settings: RpcSettings) -> Self {
        Self {
            settings: Mutex::new(settings),
            connected: AtomicBool::new(false),
            tx: Mutex::new(None),
        }
    }

    fn snapshot(&self) -> RpcStatus {
        let settings = *self.settings.lock().unwrap();
        RpcStatus {
            enabled: settings.enabled,
            show_platform: settings.show_platform,
            connected: self.connected.load(Ordering::SeqCst),
        }
    }

    fn signal(&self) {
        if let Some(tx) = self.tx.lock().unwrap().as_ref() {
            let _ = tx.send(WorkerMsg::Refresh);
        }
    }
}

fn settings_path<R: Runtime>(app: &tauri::AppHandle<R>) -> Option<std::path::PathBuf> {    let dir = app.path().app_data_dir().ok()?;
    Some(dir.join(SETTINGS_FILE))
}

/// Reads persisted settings; missing or corrupt files fall back to defaults
/// (Rich Presence enabled).
fn read_settings<R: Runtime>(app: &tauri::AppHandle<R>) -> RpcSettings {
    let Some(path) = settings_path(app) else {
        return RpcSettings::default();
    };
    match std::fs::read(&path) {
        Ok(bytes) => serde_json::from_slice(&bytes).unwrap_or_default(),
        Err(_) => RpcSettings::default(),
    }
}

fn write_settings<R: Runtime>(app: &tauri::AppHandle<R>, settings: &RpcSettings) {
    let Some(path) = settings_path(app) else {
        return;
    };
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    match serde_json::to_vec_pretty(settings) {
        Ok(bytes) => {
            if let Err(e) = std::fs::write(&path, bytes) {
                eprintln!("[qxchat-discord-rpc] failed to persist settings: {e}");
            }
        }
        Err(e) => eprintln!("[qxchat-discord-rpc] failed to serialize settings: {e}"),
    }
}

/// `(small-image key, tooltip platform name)`, or `None` when this platform
/// has no matching asset in the Discord portal.
fn platform_asset() -> Option<(&'static str, &'static str)> {
    #[cfg(target_os = "windows")]
    {
        Some(("windows", "Windows"))
    }
    #[cfg(target_os = "macos")]
    {
        Some(("macos", "macOS"))
    }
    #[cfg(target_os = "linux")]
    {
        Some(("linux", "Linux"))
    }
    #[cfg(not(any(
        target_os = "windows",
        target_os = "macos",
        target_os = "linux"
    )))]
    {
        None
    }
}

fn build_activity(settings: &RpcSettings, version: &str) -> Activity<'static> {
    let mut assets = Assets::new()
        .large_image("icon")
        .large_text(format!("QxChat v{version}"));
    if settings.show_platform {
        if let Some((key, name)) = platform_asset() {
            assets = assets
                .small_image(key)
                .small_text(format!("on {name}"));
        }
    }
    Activity::new().assets(assets)
}

/// Returns the current settings.
#[tauri::command]
fn get_settings(state: tauri::State<'_, RpcState>) -> RpcSettings {
    *state.settings.lock().unwrap()
}

/// Enables or disables Rich Presence (persisted, applied live).
#[tauri::command]
fn set_enabled<R: Runtime>(
    app: tauri::AppHandle<R>,
    state: tauri::State<'_, RpcState>,
    enabled: bool,
) -> RpcSettings {
    {
        let mut settings = state.settings.lock().unwrap();
        settings.enabled = enabled;
        write_settings(&app, &settings);
    }
    state.signal();
    *state.settings.lock().unwrap()
}

/// Shows or hides the OS small image (persisted, applied live).
#[tauri::command]
fn set_show_platform<R: Runtime>(
    app: tauri::AppHandle<R>,
    state: tauri::State<'_, RpcState>,
    show_platform: bool,
) -> RpcSettings {
    {
        let mut settings = state.settings.lock().unwrap();
        settings.show_platform = show_platform;
        write_settings(&app, &settings);
    }
    state.signal();
    *state.settings.lock().unwrap()
}

/// Returns settings plus live connection state for the settings UI.
#[tauri::command]
fn get_status(state: tauri::State<'_, RpcState>) -> RpcStatus {
    state.snapshot()
}

fn wait_for_signal(rx: &mpsc::Receiver<WorkerMsg>, timeout: Duration) -> bool {
    match rx.recv_timeout(timeout) {
        Ok(WorkerMsg::Refresh) => true,
        Err(mpsc::RecvTimeoutError::Timeout) => true,
        Err(mpsc::RecvTimeoutError::Disconnected) => false,
    }
}

fn worker_loop<R: Runtime>(
    app: tauri::AppHandle<R>,
    rx: mpsc::Receiver<WorkerMsg>,
    version: String,
) {
    let mut client: Option<DiscordIpcClient> = None;

    loop {
        let settings = *app.state::<RpcState>().settings.lock().unwrap();

        if !settings.enabled {
            // Disabled: clear any live presence and park until re-enabled.
            if let Some(mut c) = client.take() {
                let _ = c.clear_activity();
                let _ = c.close();
            }
            app.state::<RpcState>()
                .connected
                .store(false, Ordering::SeqCst);
            match rx.recv() {
                Ok(WorkerMsg::Refresh) => continue,
                Err(_) => break,
            }
        }

        if client.is_none() {
            // (Re)connect while Discord may be absent; never crash the app.
            let mut c = DiscordIpcClient::new(CLIENT_ID);
            match c.connect() {
                Ok(()) => {
                    client = Some(c);
                    app.state::<RpcState>()
                        .connected
                        .store(true, Ordering::SeqCst);
                }
                Err(e) => {
                    eprintln!("[qxchat-discord-rpc] connect failed (Discord running?): {e}");
                    if !wait_for_signal(&rx, RETRY_DELAY) {
                        break;
                    }
                    continue;
                }
            }
        }

        // Connected: (re-)push the activity. A failed push means the
        // connection died → drop it and go back through reconnect.
        let push_ok = match client.as_mut() {
            Some(c) => match c.set_activity(build_activity(&settings, &version)) {
                Ok(()) => true,
                Err(e) => {
                    eprintln!("[qxchat-discord-rpc] set_activity failed: {e}");
                    false
                }
            },
            None => false,
        };
        if !push_ok {
            if let Some(mut c) = client.take() {
                let _ = c.close();
            }
            app.state::<RpcState>()
                .connected
                .store(false, Ordering::SeqCst);
            continue;
        }

        if !wait_for_signal(&rx, REFRESH_INTERVAL) {
            break;
        }
    }
}

fn spawn_worker<R: Runtime>(app: tauri::AppHandle<R>, version: String) {
    let (tx, rx) = mpsc::channel::<WorkerMsg>();
    *app.state::<RpcState>().tx.lock().unwrap() = Some(tx);

    let _ = std::thread::Builder::new()
        .name("qxchat-discord-rpc".into())
        .spawn(move || worker_loop(app, rx, version));
}

/// Initializes the discord-rpc plugin.
pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("discord-rpc")
        .invoke_handler(tauri::generate_handler![
            get_settings,
            set_enabled,
            set_show_platform,
            get_status
        ])
        .setup(|app, _api| {
            let settings = read_settings(app);
            app.manage(RpcState::new(settings));

            let version = app.package_info().version.to_string();
            spawn_worker((*app).clone(), version);
            Ok(())
        })
        .build()
}
