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

  src = lib.cleanSource ../.;
  cargoRoot = "src-tauri";

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
