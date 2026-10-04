//! QxChat-native rich activity detection (desktop only).
//!
//! While the `discord-rpc` plugin pushes *our* presence to Discord, this
//! module answers the reverse question for the QxChat mesh itself: "what is
//! this user doing right now?" so profile cards can render a Discord-style
//! activity block ("Playing Baldur's Gate 3 — 12:34 elapsed").
//!
//! Detection is a running-process scan against two allowlists:
//! - the server-provided detectable map (`set_detectable`, fetched by the
//!   frontend from `GET /api/activity/detectable` — the server compacts the
//!   official Discord feed (served by our server), never fetched directly),
//! - the small built-in table below (offline fallback, plus apps/media kinds
//!   the upstream game list does not cover).
//! Only listed executables are ever reported, so random background processes
//! never leak. The frontend polls `get_activity` (~every 30 s) and broadcasts
//! the result inside its own profile — no Discord socket involved, so this
//! runs side by side with the outbound Discord Rich Presence without any
//! conflict.

use std::collections::HashMap;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};
use std::sync::Once;
use std::time::{SystemTime, UNIX_EPOCH};

use sysinfo::{ProcessRefreshKind, ProcessesToUpdate, System};
use tauri::{
    plugin::{Builder, TauriPlugin},
    Manager, Runtime,
};

/// Server-provided `exe -> display name` map (kind `game`), pushed by the
/// frontend. Empty until the first successful fetch; the built-in table below
/// covers the gap.
struct ActivityState {
    server_games: Mutex<HashMap<String, String>>,
    /// Last native RPC payload seen by the embedded server (`None` = clear).
    /// Mapped on read so classification always uses fresh game lists.
    /// `Arc` (not a plain `Mutex`): the RPC callback owns a clone, so it
    /// never touches Tauri `State` guards across threads (borrowck E0597).
    rpc_raw: Arc<Mutex<Option<(crate::rsrpc::cmd::Activity, Option<String>)>>>,
}

/// Upper bound on the server map (alloc guard on hostile payloads).
const MAX_SERVER_ENTRIES: usize = 250_000;

/// Opt-in verbose logging, off by default. Enable with
/// `QXCHAT_ACTIVITY_DEBUG=1` before starting the client; every
/// `get_activity` poll then reports which source won (native RPC vs process
/// scan) and which display fields it carried.
static ACTIVITY_DEBUG_INIT: Once = Once::new();
static ACTIVITY_DEBUG: AtomicBool = AtomicBool::new(false);

fn activity_debug_enabled() -> bool {
    ACTIVITY_DEBUG_INIT.call_once(|| {
        if std::env::var("QXCHAT_ACTIVITY_DEBUG").as_deref() == Ok("1") {
            ACTIVITY_DEBUG.store(true, Ordering::Relaxed);
        }
    });
    ACTIVITY_DEBUG.load(Ordering::Relaxed)
}

fn activity_debug(message: impl AsRef<str>) {
    if activity_debug_enabled() {
        eprintln!("[qxchat-activity] {}", message.as_ref());
    }
}

/// Detected activity exposed to the frontend.
#[derive(Debug, Clone, serde::Serialize)]
struct DetectedActivity {
    /// One of `game`, `app`, `media`, `call`.
    kind: String,
    /// Display name ("Baldur's Gate 3").
    name: String,
    /// Optional second line (native RPC `details`).
    #[serde(skip_serializing_if = "String::is_empty")]
    details: String,
    /// Optional third line (native RPC `state`).
    #[serde(skip_serializing_if = "String::is_empty")]
    state: String,
    /// Emitter's Discord application id (resolves bare artwork keys).
    #[serde(skip_serializing_if = "String::is_empty", rename = "appId")]
    app_id: String,
    /// Raw artwork references (resolved + proxied by the frontend).
    #[serde(skip_serializing_if = "Option::is_none")]
    assets: Option<DetectedArtwork>,
    /// Epoch millis when the process started (elapsed timer).
    started_at: u64,
}

/// Raw artwork references of a detected activity.
#[derive(Debug, Clone, serde::Serialize)]
struct DetectedArtwork {
    #[serde(skip_serializing_if = "String::is_empty")]
    large: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    small: String,
}

/// (executable key, display name, kind). Keys are matched against the
/// lowercased executable stem (`firefox`) or process name.
const DETECTABLE: &[(&str, &str, &str)] = &[
    // Games
    ("cs2", "Counter-Strike 2", "game"),
    ("valorant-win64-shipping", "VALORANT", "game"),
    ("valorant", "VALORANT", "game"),
    ("leagueoflegends", "League of Legends", "game"),
    ("leagueclient", "League of Legends", "game"),
    ("bg3_dx11", "Baldur's Gate 3", "game"),
    ("bg3", "Baldur's Gate 3", "game"),
    ("eldenring", "ELDEN RING", "game"),
    ("witcher3", "The Witcher 3", "game"),
    ("cyberpunk2077", "Cyberpunk 2077", "game"),
    ("osu!", "osu!", "game"),
    ("osu", "osu!", "game"),
    ("fortniteclient-win64-shipping", "Fortnite", "game"),
    ("r5apex", "Apex Legends", "game"),
    ("overwatch", "Overwatch 2", "game"),
    ("rocketleague", "Rocket League", "game"),
    ("stardewvalley", "Stardew Valley", "game"),
    ("terraria", "Terraria", "game"),
    ("factorio", "Factorio", "game"),
    ("satisfactory", "Satisfactory", "game"),
    ("palworld", "Palworld", "game"),
    ("helldivers2", "HELLDIVERS 2", "game"),
    ("lethal company", "Lethal Company", "game"),
    ("balatro", "Balatro", "game"),
    ("dota2", "Dota 2", "game"),
    ("arma3", "Arma 3", "game"),
    ("rust", "Rust", "game"),
    ("warframe", "Warframe", "game"),
    ("destiny2", "Destiny 2", "game"),
    ("diablo iv", "Diablo IV", "game"),
    ("wow", "World of Warcraft", "game"),
    ("ffxiv_dx11", "FINAL FANTASY XIV", "game"),
    ("genshinimpact", "Genshin Impact", "game"),
    ("starrail", "Honkai: Star Rail", "game"),
    ("rimworld", "RimWorld", "game"),
    ("stellaris", "Stellaris", "game"),
    ("eu4", "Europa Universalis IV", "game"),
    ("ck3", "Crusader Kings III", "game"),
    ("civ6", "Civilization VI", "game"),
    ("civ7", "Civilization VII", "game"),
    ("aoe2de", "Age of Empires II", "game"),
    ("aoe4", "Age of Empires IV", "game"),
    ("aces", "War Thunder", "game"),
    ("worldoftanks", "World of Tanks", "game"),
    ("warthunder", "War Thunder", "game"),
    ("pathofexile", "Path of Exile", "game"),
    ("poe2", "Path of Exile 2", "game"),
    ("drg", "Deep Rock Galactic", "game"),
    // Apps
    ("code", "Visual Studio Code", "app"),
    ("cursor", "Cursor", "app"),
    ("zed", "Zed", "app"),
    ("zed-editor", "Zed", "app"),
    ("zeditor", "Zed", "app"),
    // Nix wrappers (.zed-editor-wrapped) and the upstream wrapper binary.
    (".zed-editor-wrapped", "Zed", "app"),
    (".zed-editor-wrapper", "Zed", "app"),
    ("idea64", "IntelliJ IDEA", "app"),
    ("webstorm64", "WebStorm", "app"),
    ("pycharm64", "PyCharm", "app"),
    ("rider64", "Rider", "app"),
    ("firefox", "Firefox", "app"),
    ("chrome", "Chrome", "app"),
    ("msedge", "Edge", "app"),
    ("brave", "Brave", "app"),
    ("arc", "Arc", "app"),
    ("obs64", "OBS Studio", "app"),
    ("obs", "OBS Studio", "app"),
    ("discord", "Discord", "app"),
    ("vesktop", "Vesktop", "app"),
    ("telegram", "Telegram", "app"),
    ("blender", "Blender", "app"),
    ("photoshop", "Photoshop", "app"),
    ("unity", "Unity", "app"),
    ("unrealengine", "Unreal Engine", "app"),
    ("godot", "Godot", "app"),
    ("davinciresolve", "DaVinci Resolve", "app"),
    ("reaper", "REAPER", "app"),
    // Media
    ("spotify", "Spotify", "media"),
    ("vlc", "VLC", "media"),
    ("foobar2000", "foobar2000", "media"),
    ("mpv", "mpv", "media"),
    ("mpc-hc64", "Media Player Classic", "media"),
    ("strawberry", "Strawberry", "media"),
    ("rhythmbox", "Rhythmbox", "media"),
    ("fl64", "FL Studio", "media"),
];

/// Never report ourselves (would loop "Using QxChat" forever).
const SELF_NAMES: &[&str] = &["qxchat"];

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Lowercased executable stem, without a Windows `.exe` suffix.
fn exe_key(raw: &str) -> String {
    let lower = raw.to_lowercase();
    lower.strip_suffix(".exe").unwrap_or(&lower).to_owned()
}

fn kind_rank(kind: &str) -> u8 {
    match kind {
        "game" => 0,
        "media" => 1,
        _ => 2,
    }
}

/// Scans running processes once and returns the best allowlist match:
/// games beat media, media beats apps; ties go to the latest start time.
/// The built-in table wins ties against the server map (curated kinds); a
/// server-only hit reports kind `game`.
fn detect(server_games: &HashMap<String, String>) -> Option<DetectedActivity> {
    let mut sys = System::new();
    sys.refresh_processes_specifics(
        ProcessesToUpdate::All,
        true,
        ProcessRefreshKind::everything(),
    );
    // Deduplicate: one candidate per executable key. Cow-free small struct:
    // (rank, started_at, display, kind, builtin).
    let mut seen: HashMap<String, (u8, u64, String, &'static str, bool)> = HashMap::new();
    for proc_ in sys.processes().values() {
        let from_exe = proc_
            .exe()
            .and_then(|p| p.file_stem())
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_default();
        let name = if from_exe.is_empty() {
            proc_.name().to_string_lossy().into_owned()
        } else {
            from_exe
        };
        let key = exe_key(&name);
        if key.is_empty() || SELF_NAMES.contains(&key.as_str()) {
            continue;
        }
        let (display, kind, builtin) =
            match DETECTABLE.iter().find(|(exe, _, _)| *exe == key) {
                Some((_, display, kind)) => (display.to_string(), *kind, true),
                None => match server_games.get(&key) {
                    Some(server_name) => (server_name.clone(), "game", false),
                    None => continue,
                },
            };
        let started_at = proc_.start_time().saturating_mul(1000);
        let started_at = if started_at == 0 { now_ms() } else { started_at };
        let rank = kind_rank(kind);
        let replace = match seen.get(&key) {
            None => true,
            Some((prev_rank, prev_started, _, _, prev_builtin)) => {
                // Built-in entries outrank server ones at equal kind recency.
                (builtin && !prev_builtin)
                    || (builtin == *prev_builtin
                        && (rank < *prev_rank
                            || (rank == *prev_rank && started_at > *prev_started)))
            }
        };
        if replace {
            seen.insert(key, (rank, started_at, display, kind, builtin));
        }
    }
    seen
        .into_values()
        .min_by(|a, b| {
            a.0.cmp(&b.0)
                .then(b.1.cmp(&a.1))
                .then(b.4.cmp(&a.4))
        })
        .map(|(_, started_at, name, kind, _)| DetectedActivity {
            kind: kind.to_owned(),
            name,
            details: String::new(),
            state: String::new(),
            app_id: String::new(),
            assets: None,
            started_at,
        })
}

/// Lowercased display names known to be games: built-in `game` entries plus
/// every server-provided name (the upstream feed is games-only).
fn known_game_names(server_games: &HashMap<String, String>) -> std::collections::HashSet<String> {
    let mut set = std::collections::HashSet::new();
    for (_, display, kind) in DETECTABLE {
        if *kind == "game" {
            set.insert(display.to_lowercase());
        }
    }
    for name in server_games.values() {
        set.insert(name.to_lowercase());
    }
    set
}

/// Native RPC payload (if any) mapped to display fields. `None` when silent,
/// self-emitted, or unrenderable.
fn rpc_activity(state: &ActivityState) -> Option<DetectedActivity> {
    let raw = state.rpc_raw.lock().unwrap().clone()?;
    let (activity, app_id) = raw;
    let games = state.server_games.lock().unwrap();
    let known = known_game_names(&games);
    drop(games);
    let seen = crate::rsrpc::map_rpc_activity(
        &activity,
        app_id.as_deref(),
        crate::discord_rpc::QXCHAT_DISCORD_CLIENT_ID,
        &known,
    )?;
    let assets = if seen.large_image.is_empty() && seen.small_image.is_empty() {
        None
    } else {
        Some(DetectedArtwork { large: seen.large_image, small: seen.small_image })
    };
    Some(DetectedActivity {
        kind: seen.kind.to_owned(),
        name: seen.name,
        details: seen.details,
        state: seen.state,
        app_id: seen.app_id,
        assets,
        started_at: seen.started_at_ms,
    })
}

/// Replaces the server-provided detectable map. Keys are normalized
/// (lowercase stems); oversized payloads are truncated. Returns the stored
/// entry count.
#[tauri::command]
fn set_detectable(
    state: tauri::State<'_, ActivityState>,
    games: HashMap<String, String>,
) -> usize {
    let mut map = HashMap::with_capacity(games.len().min(MAX_SERVER_ENTRIES));
    for (raw_key, raw_name) in games {
        if map.len() >= MAX_SERVER_ENTRIES {
            break;
        }
        let key = exe_key(&raw_key);
        let name: String = raw_name.trim().chars().take(96).collect();
        if key.is_empty() || name.is_empty() {
            continue;
        }
        map.entry(key).or_insert(name);
    }
    let count = map.len();
    *state.server_games.lock().unwrap() = map;
    activity_debug(format!("detectable map replaced: {count} entries"));
    count
}

/// Current activity, or `None` when nothing recognizable runs.
/// Priority: native RPC frames (real SET_ACTIVITY) beat the process scan —
/// like Discord itself, SDK payloads win over heuristics.
#[tauri::command]
fn get_activity(state: tauri::State<'_, ActivityState>) -> Option<DetectedActivity> {
    // Never crash the app from a detection pass.
    if let Some(rpc) = std::panic::catch_unwind(|| rpc_activity(&state)).ok().flatten() {
        activity_debug(format!(
            "source=rpc name={:?} kind={} details={} state={} large_art={} small_art={} has_app_id={} started_at={}",
            rpc.name,
            rpc.kind,
            !rpc.details.is_empty(),
            !rpc.state.is_empty(),
            rpc.assets.as_ref().map(|a| !a.large.is_empty()).unwrap_or(false),
            rpc.assets.as_ref().map(|a| !a.small.is_empty()).unwrap_or(false),
            !rpc.app_id.is_empty(),
            rpc.started_at,
        ));
        return Some(rpc);
    }
    let snapshot = state.server_games.lock().unwrap().clone();
    let found = std::panic::catch_unwind(|| detect(&snapshot)).ok().flatten();
    activity_debug(format!(
        "source={} name={:?}",
        if found.is_some() { "scan" } else { "none" },
        found.as_ref().map(|a| a.name.clone()).unwrap_or_default(),
    ));
    found
}

/// Starts the embedded Discord-compatible RPC server once: native apps
/// publish real SET_ACTIVITY frames to us (even with no Discord running).
fn spawn_rpc_server<R: Runtime>(app: &tauri::AppHandle<R>) {
    let slot = app.state::<ActivityState>().rpc_raw.clone();
    let _ = std::thread::Builder::new()
        .name("qxchat-rpc-server".into())
        .spawn(move || {
            let mut server = crate::rsrpc::RPCServer::empty(crate::rsrpc::RPCConfig::default());
            server.on_activity(move |activity, app_id| {
                if let Ok(mut guard) = slot.lock() {
                    *guard = activity.map(|a| (a, app_id));
                }
            });
            server.start();
            // `start` spawns workers and returns; park this thread so the
            // server (owned here) is never dropped.
            loop {
                std::thread::park();
            }
        });
}

/// Initializes the activity plugin.
pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("activity")
        .invoke_handler(tauri::generate_handler![get_activity, set_detectable])
        .setup(|app, _api| {
            app.manage(ActivityState {
                server_games: Mutex::new(HashMap::new()),
                rpc_raw: Arc::new(Mutex::new(None)),
            });
            spawn_rpc_server(app);
            Ok(())
        })
        .build()
}
