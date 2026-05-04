{
  lib,
  rustPlatform,
  pkg-config,
  makeWrapper,
  wrapGAppsHook4,
  copyDesktopItems,
  makeDesktopItem,
  gobject-introspection,
  glib-networking,
  gtk3,
  webkitgtk_4_1,
  libsoup_3,
  openssl,
  glib,
  gdk-pixbuf,
  pango,
  cairo,
  atkmm,
  at-spi2-atk,
  harfbuzz,
  librsvg,
  dbus,
  gst_all_1,
  pipewire,
}:

let
  pname = "qxchat";
  version = "1.0.0";

  gstPlugins = [
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
    gst_all_1.gst-libav
    pipewire
  ];

  gstPluginPath = lib.concatStringsSep ":" (map (pkg: "${pkg}/lib/gstreamer-1.0") gstPlugins);

  desktopItem = makeDesktopItem {
    name = "qxchat";
    desktopName = "QxChat";
    exec = "qxchat";
    terminal = false;
    categories = [
      "Network"
      "Chat"
    ];
    icon = "qxchat";
  };
in
rustPlatform.buildRustPackage {
  inherit pname version;

  # Keep client/dist in the source tree (it is gitignored but required by Tauri at build/runtime).
  src = ../.;
  cargoRoot = "src-tauri";
  buildAndTestSubdir = "src-tauri";

  cargoLock = {
    lockFile = ../src-tauri/Cargo.lock;
  };

  nativeBuildInputs = [
    pkg-config
    makeWrapper
    wrapGAppsHook4
    copyDesktopItems
    gobject-introspection
  ];

  postPatch = ''
    # Prevent Tauri from trying to run bun/npm build steps inside the sandbox.
    substituteInPlace src-tauri/tauri.conf.json \
      --replace-fail '"beforeBuildCommand": "cd client && bun run build:tauri",' '"beforeBuildCommand": "",'

    test -f client/dist/index.html || (echo "Missing client/dist/index.html (build frontend once locally)" >&2; exit 1)

    cat > client/dist/runtime-config.js <<'EOF'
window.__QXP_RUNTIME__ = {"apiBaseUrl":"https://qxp.kisakay.com","rtc":{"callsEnabled":true,"callsUnavailableReason":"","relayOnly":true,"turnCredential":"df64240e730e15fdfb75d6cff95367b95ed341bd98517544","turnUrls":["turn:turn.qxp.kisakay.com:3478?transport=udp","turn:turn.qxp.kisakay.com:3478?transport=tcp","turns:turn.qxp.kisakay.com:5349?transport=tcp"],"turnUsername":"qxp-turn"},"serverOrigin":"https://qxp.kisakay.com","wsUrl":"wss://qxp.kisakay.com/ws"};
EOF
  '';

  buildInputs = [
    gtk3
    webkitgtk_4_1
    libsoup_3
    openssl
    glib
    gdk-pixbuf
    pango
    cairo
    atkmm
    at-spi2-atk
    glib-networking
    harfbuzz
    librsvg
    dbus
  ]
  ++ gstPlugins;

  desktopItems = [ desktopItem ];

  postInstall = ''
    install -Dm644 src-tauri/icons/icon.png "$out/share/icons/hicolor/512x512/apps/qxchat.png"

    wrapProgram "$out/bin/lqxp-client" \
      --set WEBKIT_DISABLE_DMABUF_RENDERER 1 \
      --set GIO_MODULE_DIR "${glib-networking}/lib/gio/modules" \
      --set GIO_EXTRA_MODULES "${glib-networking}/lib/gio/modules" \
      --set GST_PLUGIN_SYSTEM_PATH_1_0 "${gstPluginPath}"

    ln -s "$out/bin/lqxp-client" "$out/bin/qxchat"
  '';

  meta = {
    description = "QxChat desktop client (Tauri)";
    homepage = "https://github.com/lqxp/client-tauri";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "qxchat";
  };
}
