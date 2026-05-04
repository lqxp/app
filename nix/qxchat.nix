{
  lib,
  rustPlatform,
  stdenvNoCC,
  pnpm,
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
  libdrm,
  libgbm ? mesa,
  libglvnd,
  mesa,
  libepoxy,
  wayland,
  nodejs,
}:

let
  pname = "qxchat";
  version = "1.0.0";

  frontendSrc = ../client;

  frontend = stdenvNoCC.mkDerivation {
    pname = "${pname}-frontend";
    inherit version;

    src = frontendSrc;

    nativeBuildInputs = [
      nodejs
      pnpm.configHook
    ];

    pnpmDeps = pnpm.fetchDeps {
      inherit pname version;
      src = frontendSrc;
      fetcherVersion = 1;
      hash = "sha256-YwG2FhVhS+JxI/hSmxjGReyE4q4DKqOZ1r36JRCa27s=";
    };

    buildPhase = ''
      runHook preBuild
      pnpm install --offline --frozen-lockfile
      pnpm run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r dist $out/
      runHook postInstall
    '';
  };

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
  pipewireSpaPath = "${pipewire}/lib/spa-0.2";
  runtimeLibPath = lib.makeLibraryPath (
    [
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
      libdrm
      libgbm
      libglvnd
      mesa
      libepoxy
      wayland
      pipewire
    ]
    ++ gstPlugins
  );

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
        # Prevent Tauri from trying to run bun build steps inside the Rust build hook.
        substituteInPlace src-tauri/tauri.conf.json \
          --replace-fail '"beforeBuildCommand": "cd client && bun run build:tauri",' '"beforeBuildCommand": "",'

        rm -rf client/dist
        mkdir -p client
        cp -r ${frontend}/dist client/dist
        chmod -R u+w client/dist

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
    libdrm
    libgbm
    libglvnd
    mesa
    libepoxy
    wayland
  ]
  ++ gstPlugins;

  desktopItems = [ desktopItem ];

  postInstall = ''
    install -Dm644 src-tauri/icons/icon.png "$out/share/icons/hicolor/512x512/apps/qxchat.png"

    wrapProgram "$out/bin/lqxp-client" \
      --set GST_REGISTRY_FORK "no" \
      --unset GST_PLUGIN_SCANNER \
      --unset GST_PLUGIN_SCANNER_1_0 \
      --set GST_REGISTRY_1_0 "/tmp/qxchat-gst-registry.bin" \
      --set LD_LIBRARY_PATH "${runtimeLibPath}" \
      --set GIO_MODULE_DIR "${glib-networking}/lib/gio/modules" \
      --set GIO_EXTRA_MODULES "${glib-networking}/lib/gio/modules" \
      --set GST_PLUGIN_SYSTEM_PATH_1_0 "${gstPluginPath}" \
      --set GST_PLUGIN_PATH_1_0 "${gstPluginPath}" \
      --set GST_PLUGIN_SYSTEM_PATH "${gstPluginPath}" \
      --set GST_PLUGIN_PATH "${gstPluginPath}" \
      --set PIPEWIRE_MODULE_DIR "${pipewire}/lib/pipewire-0.3" \
      --set SPA_PLUGIN_DIR "${pipewireSpaPath}"

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
