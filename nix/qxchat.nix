# QxChat — NixOS binary wrapper (no source build).
#
# Philosophy: CI builds Tauri once per release and publishes
#   QxChat_<version>_linux-x86_64.tar.gz
#   QxChat_<version>_linux-aarch64.tar.gz
# as GitHub release assets. This derivation just fetches the matching
# tarball and injects it into a NixOS `ld` environment (patchelf + wrapProgram),
# so updates are a download instead of a full Rust/WebKit rebuild.
#
# Tarball layout (produced by .github/workflows/build-and-release.yml):
#   qxchat-linux-<arch>/qxchat      (Tauri binary, frontend embedded)
#   qxchat-linux-<arch>/icon.png    (optional app icon)
#
# To update to a new release:
#   1. bump `version` below,
#   2. run `nix-prefetch-url <tarball-url>` for each arch and paste the
#      resulting `sha256-...` SRI hashes into `binaryHashes`.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook4,
  copyDesktopItems,
  makeDesktopItem,
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
  libdrm,
  libgbm ? mesa,
  libglvnd,
  mesa,
  libepoxy,
  wayland,
  libayatana-appindicator,
  alsa-lib,
  # Overridable so a release flake can pin an exact version + hashes
  # without editing this file (see QxChat_<version>_flake.nix assets).
  version ? "1.20.5",
  binaryHashes ? {
    x86_64-linux = "sha256-dH5knCO1DnXiynvBS6fr5zeCPgJY6l2uYkGgrKfZjgc=";
    aarch64-linux = "sha256-0AHL9GXtKF0L/DY32O8uQfR7JQQ8Ah3bCru3HO33ZlQ=";
  },
}:

let
  pname = "qxchat";

  arch =
    {
      x86_64-linux = "x86_64";
      aarch64-linux = "aarch64";
    }
    .${stdenv.hostPlatform.system}
      or (throw "qxchat: unsupported system ${stdenv.hostPlatform.system} (only x86_64-linux and aarch64-linux have prebuilt binaries)");

  src = fetchurl {
    url = "https://github.com/lqxp/app/releases/download/v${version}/QxChat_${version}_linux-${arch}.tar.gz";
    hash =
      binaryHashes.${stdenv.hostPlatform.system}
        or (throw "qxchat: missing binary hash for ${stdenv.hostPlatform.system}");
  };

  webkitgtk = webkitgtk_4_1.override {
    enableExperimental = true;
  };

  gstPlugins = [
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
    gst_all_1.gst-libav
    gst_all_1.gst-plugins-rs
    pipewire
  ];

  gstPluginPath = lib.concatStringsSep ":" (map (pkg: "${pkg}/lib/gstreamer-1.0") gstPlugins);
  pipewireSpaPath = "${pipewire}/lib/spa-0.2";
  runtimeLibPath = lib.makeLibraryPath (
    [
      gtk3
      webkitgtk
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
      libdrm
      libgbm
      libglvnd
      mesa
      libepoxy
      wayland
      pipewire
      libayatana-appindicator
      alsa-lib
    ]
    ++ gstPlugins
  );

  desktopItem = makeDesktopItem {
    name = "com.qxp.client";
    desktopName = "QxChat";
    exec = "qxchat";
    terminal = false;
    categories = [
      "Network"
      "Chat"
    ];
    icon = "qxchat";
    extraConfig = {
      StartupWMClass = "com.qxp.client";
    };
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  sourceRoot = "qxchat-linux-${arch}";

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook4
    copyDesktopItems
  ];

  buildInputs = [
    gtk3
    webkitgtk
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
    libdrm
    libgbm
    libglvnd
    mesa
    libepoxy
    wayland
    alsa-lib
  ]
  ++ gstPlugins;

  # The prebuilt binary has no runtime search path; autoPatchelfHook appends
  # everything from buildInputs, and we add the remaining wrap below.
  autoPatchelfIgnoreMissingDeps = [
    # Ayatana indicator is dlopen()ed by Tauri at runtime; resolved via
    # LD_LIBRARY_PATH in the wrapper instead of a DT_NEEDED entry.
    "libayatana-appindicator3.so.1"
  ];

  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    install -Dm755 qxchat "$out/bin/qxchat"

    if [ -f icon.png ]; then
      install -Dm644 icon.png "$out/share/icons/hicolor/512x512/apps/qxchat.png"
    fi

    runHook postInstall
  '';

  desktopItems = [ desktopItem ];

  postFixup = ''
    wrapProgram "$out/bin/qxchat" \
      --set G_APPLICATION_ID "com.qxp.client" \
      --set WEBKIT_DISABLE_DMABUF_RENDERER "1" \
      --set WEBKIT_DISABLE_COMPOSITING_MODE "1" \
      --prefix LD_LIBRARY_PATH : "${runtimeLibPath}" \
      --set GIO_MODULE_DIR "${glib-networking}/lib/gio/modules" \
      --set GIO_EXTRA_MODULES "${glib-networking}/lib/gio/modules" \
      --set GST_PLUGIN_SYSTEM_PATH_1_0 "${gstPluginPath}" \
      --set GST_PLUGIN_PATH_1_0 "${gstPluginPath}" \
      --set GST_PLUGIN_SYSTEM_PATH "${gstPluginPath}" \
      --set GST_PLUGIN_PATH "${gstPluginPath}" \
      --set PIPEWIRE_MODULE_DIR "${pipewire}/lib/pipewire-0.3" \
      --set SPA_PLUGIN_DIR "${pipewireSpaPath}" \
      "''${gappsWrapperArgs[@]}"
  '';

  meta = {
    description = "QxChat desktop client (Tauri, prebuilt binary)";
    homepage = "https://github.com/lqxp/client";
    license = lib.licenses.mit;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "qxchat";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
