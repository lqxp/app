fn main() {
    tauri_build::try_build(
        tauri_build::Attributes::new()
            .plugin(
                "tor",
                tauri_build::InlinedPlugin::new().commands(&[
                    "status",
                    "start",
                    "stop",
                    "toggle",
                    "is_ready",
                    "relays",
                    "circuit",
                    "geo",
                    "geo_ip",
                ]),
            )
            .plugin(
                "screen-audio",
                tauri_build::InlinedPlugin::new().commands(&["start", "stop"]),
            )
            .plugin(
                "integrity",
                tauri_build::InlinedPlugin::new().commands(&["fingerprint"]),
            )
            .plugin(
                "background",
                tauri_build::InlinedPlugin::new()
                    .commands(&["start_background", "stop_background", "is_background_running"]),
            )
            .plugin(
                "discord-rpc",
                tauri_build::InlinedPlugin::new().commands(&[
                    "get_settings",
                    "set_enabled",
                    "set_show_platform",
                    "get_status",
                ]),
            )
            .plugin(
                "permissions",
                tauri_build::InlinedPlugin::new()
                    .commands(&["request_permissions", "check_permissions"]),
            ),
    )
    .expect("failed to run tauri-build");
}
