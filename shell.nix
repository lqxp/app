let
  pkgs = import <nixpkgs> {};
  gstPlugins = [
    pkgs.gst_all_1.gstreamer.out
    pkgs.gst_all_1.gst-plugins-base
    pkgs.gst_all_1.gst-plugins-good
    pkgs.gst_all_1.gst-plugins-bad
    pkgs.gst_all_1.gst-plugins-ugly
    pkgs.gst_all_1.gst-libav
  ];
  gstTools = with pkgs.gst_all_1; [
    gstreamer
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
    gst-plugins-ugly
    gst-libav
  ];
  gstPluginPath = pkgs.lib.concatStringsSep ":" (map (pkg: "${pkg}/lib/gstreamer-1.0") gstPlugins);
in
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    cargo
    cargo-tauri
    gobject-introspection
    nodejs
    pkg-config
    rustc
    rustup
    wrapGAppsHook4
    gst_all_1.gstreamer.dev
  ];

  buildInputs = (with pkgs; [
    at-spi2-atk
    atkmm
    cairo
    gdk-pixbuf
    glib
    glib-networking
    gtk3
    harfbuzz
    librsvg
    libsoup_3
    openssl
    pango
    webkitgtk_4_1
    xdotool
  ]) ++ gstTools ++ gstPlugins;

  shellHook = ''
    export GIO_MODULE_DIR="${pkgs.glib-networking}/lib/gio/modules"
    export GST_PLUGIN_SYSTEM_PATH_1_0="${gstPluginPath}"
    export WEBKIT_DISABLE_DMABUF_RENDERER=1
  '';
}
