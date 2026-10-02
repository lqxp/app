# QXP Client - Tauri App

Web Client: https://qxch.at/app

Desktop client for the QXP messaging web app, built with Tauri v2 and TypeScript.

## Installation

Clone with submodules, or initialize them after cloning:

```bash
git submodule update --init --recursive
```

```bash
bun install
```

On NixOS, enter the prepared shell first:

```bash
nix develop
```

## Development

```bash
bun run dev
```

## Build

```bash
bun run build
```

`scripts/tauri-build.sh`, `scripts/build-android.sh`, and `scripts/ios-build.sh` automatically load a local `.env` file when present, so the packaged runtime can be injected consistently for Desktop, Android, and iOS.

Platform helpers are also available:

```bash
bun run build:mac
bun run build:win
bun run build:linux
```

## Flatpak (primary Linux packaging, local)

```bash
bun run build:flatpak              # stage + build + install for the current user
./scripts/build-flatpak.sh --run   # build + install + launch
./scripts/build-flatpak.sh --bundle # also emit flatpak/com.getqxchat.app.flatpak
```

Manifest + metadata live in `flatpak/` under the `com.getqxchat.app` app ID
(same ID as Android/iOS/desktop). The Tauri binary is compiled **inside**
the GNOME SDK sandbox: a Nix-built binary cannot run under the Flatpak
runtime (its `/nix` loader is absent in the sandbox). `scripts/build-flatpak.sh`
(enters `nix develop` by itself) stages everything the offline sandbox build
needs — a pinned upstream Rust toolchain (fetched once), the built frontend
(`client/dist`), vendored cargo deps (re-done only when `Cargo.lock`
changes) — then `flatpak-builder` compiles `--offline` and installs `--user`.
GNOME Platform/Sdk `50` is pulled from Flathub on first run if missing.
`flatpak`, `flatpak-builder` and `appstream` are provided by `nix develop`;
`flatpak/staging/` holds the (gitignored) staging area.

## Flathub submission

Local builds (`flatpak/com.getqxchat.app.yml`) cannot be submitted as-is:
Flathub builders have no network and accept only public `url`/`git`
sources. The submission-grade package lives in `flatpak/flathub/`:

- `com.getqxchat.app.yml` — manifest with SDK extensions for toolchains
  (`rust-stable`, `node22`), tray stack built from source (dbusmenu,
  ayatana-ido/indicator/appindicator), `git` app source + generated
  `cargo-sources.json` + per-arch frontend-deps release assets.
- `cargo-sources.json` — generated from `src-tauri/Cargo.lock`
  (`flatpak-cargo-generator.py`); regenerate whenever the lockfile changes.
- Screenshots for the metainfo are still TODO (capture 16:9 + 4:3 from the
  running app before submitting).

Release checklist (Flathub updates are manual PRs):

1. commit everything, cut the release tag (must contain `flatpak/` metadata)
  2. CI (`build-and-release.yml`, job `frontend-deps`) attaches
     `qxchat-frontend-deps-<tag>-<arch>.tar.gz` to the release; copy the
     printed sha256 into the manifest's frontend-deps sources
3. bump tag/commit/frontend-deps URLs in `flatpak/flathub/com.getqxchat.app.yml`
4. run `flatpak-builder-lint` on manifest + repo, fix all errors
5. open the PR yourself (`flathub/flathub`, base `new-pr`, title
   `Add com.getqxchat.app`) and answer reviewers

AI disclosure (Flathub policy, mandatory): this manifest and its packaging
were AI-assisted — review and understand every line before submitting, and
never let tooling open the PR or write review replies for you.

After merge + first official build, claim the ✓ checkmark via domain
verification (`getqxchat.com/.well-known/org.flathub.VerifiedApps.txt`).

## Runtime config injection

The packaged web client runtime payload (`window.__QXP_RUNTIME__`) can be generated in two ways:

1. from `QXP_RUNTIME_CONFIG_URL`, by fetching a remote production page and extracting its runtime payload
2. directly from environment variables during build

Supported environment variables:

```properties
QXP_RUNTIME_CONFIG_URL=https://example.com/
QXP_SERVER_ORIGIN=https://example.com
QXP_API_BASE_URL=https://example.com
QXP_WS_URL=wss://example.com/ws
QXP_TURN_URLS=turn:turn.example.com:3478?transport=udp,turns:turn.example.com:5349?transport=tcp
QXP_TURN_USERNAME=qxp-turn
QXP_TURN_CREDENTIAL=replace-me
QXP_RELAY_ONLY=true
QXP_CALLS_ENABLED=true
QXP_CALLS_UNAVAILABLE_REASON=
```

`QXP_RUNTIME_CONFIG_URL` is optional. If it is omitted, `client/scripts/sync-runtime-config.mjs` builds `client/dist/runtime-config.js` directly from the other variables.

Example local `.env`:

```properties
QXP_SERVER_ORIGIN=https://chat.example.com
QXP_API_BASE_URL=https://chat.example.com
QXP_WS_URL=wss://chat.example.com/ws
QXP_TURN_URLS=turn:turn.example.com:3478?transport=udp,turns:turn.example.com:5349?transport=tcp
QXP_TURN_USERNAME=qxp-turn
QXP_TURN_CREDENTIAL=replace-me
QXP_RELAY_ONLY=true
QXP_CALLS_ENABLED=true
```

In GitHub Actions, store public runtime values in repository/environment `Variables` and sensitive values such as `QXP_TURN_CREDENTIAL` in `Secrets`.

## iOS

iOS builds require macOS with the full Xcode app installed.

```bash
nix develop
bun run ios:build --export-method development
```

For development on a simulator or device:

```bash
nix develop
bun run ios:dev -- --open
```

## Android

Android builds are handled by `scripts/build-android.sh` through the package script:

```bash
bun run build:android
```

The script automatically enters the Nix development shell with `nix develop` when it is not already running inside Nix. It also prepares the Android SDK/NDK environment, Rust Android targets, and Tauri build dependencies.

By default, `bun run build:android` builds a release APK for `aarch64`:

```bash
bun run build:android
# equivalent default args: --apk --target aarch64
```

Release APKs are signed with the project keystore (`lqxp-release.jks` at the project root or `~/.config/qxchat/qxchat-release.jks`). The script prompts for the keystore password interactively if not set via `.env`.

To build a debug APK (unsigned, for quick iteration):

```bash
bun run build:android -- --debug --apk --target aarch64
```

Release APK signing is configured through environment variables. `scripts/build-android.sh` loads a local `.env` file automatically if it exists, which can contain both Android signing settings and QXP runtime injection values. `.env`, keystores, and generated Gradle signing files are ignored by git.

Create a new local signing password and `.env` file:

```bash
ANDROID_SIGNING_PASSWORD="$(openssl rand -base64 48)"
mkdir -p "$HOME/.config/qxchat"
cat > .env <<EOF
LQXP_ANDROID_CREATE_KEYSTORE=1
LQXP_REWRITE_ANDROID_KEYSTORE_PROPERTIES=1
ANDROID_KEYSTORE_PATH=$HOME/.config/qxchat/qxchat-release.jks
ANDROID_KEYSTORE_PASSWORD='$ANDROID_SIGNING_PASSWORD'
ANDROID_KEY_ALIAS=lqxp
ANDROID_KEY_PASSWORD='$ANDROID_SIGNING_PASSWORD'
ANDROID_KEY_DNAME='CN=QxChat, OU=QxChat, O=QxChat, L=Unknown, ST=Unknown, C=XX'
EOF
chmod 600 .env
unset ANDROID_SIGNING_PASSWORD
```

Then build a signed release APK:

```bash
bun run build:android -- --apk --target aarch64
```

On the first release build, the script creates the keystore at:

```text
~/.config/qxchat/qxchat-release.jks
```

and writes Gradle's generated signing configuration to:

```text
src-tauri/gen/android/keystore.properties
```

The relevant variables are:

```properties
LQXP_ANDROID_CREATE_KEYSTORE=1
LQXP_REWRITE_ANDROID_KEYSTORE_PROPERTIES=1
ANDROID_KEYSTORE_PATH=/absolute/path/to/qxchat-release.jks
ANDROID_KEYSTORE_PASSWORD=change-me
ANDROID_KEY_ALIAS=lqxp
ANDROID_KEY_PASSWORD=change-me
ANDROID_KEY_DNAME=CN=LQXP Client, OU=LQXP, O=LQXP, L=Unknown, ST=Unknown, C=XX
```

You can also point `.env` to an existing keystore instead of generating a new one by setting `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and optionally `ANDROID_KEY_PASSWORD`.

Expected APK output locations include:

```text
src-tauri/gen/android/app/build/outputs/apk/universal/debug/app-universal-debug.apk
src-tauri/gen/android/app/build/outputs/apk/universal/release/app-universal-release.apk
```

If release signing is not configured, Gradle may produce an unsigned release artifact such as:

```text
src-tauri/gen/android/app/build/outputs/apk/universal/release/app-universal-release-unsigned.apk
```

If Gradle/Tauri fails with a WebSocket or IPC error such as `failed to read CLI options` or `Connection refused`, stop stale Gradle daemons and rebuild:

```bash
src-tauri/gen/android/gradlew --project-dir src-tauri/gen/android --stop
bun run build:android
```

The script also disables the Gradle daemon for Android builds because Gradle daemons can keep stale Tauri IPC environment variables.

The GitHub workflow for simulator builds and signed IPA builds is documented in [tauri-ios.md](tauri-ios.md).

### Android live testing against a local dev server

Use `adb reverse` to forward the device's loopback to your local dev server, then build an APK targeting it:

```bash
# 1. Start the dev server on the host
cd client && bun run dev

# 2. Build APK pointing to localhost and deploy
bun run build:android -- --local
```

The `--local` flag injects `QXP_SERVER_ORIGIN=http://127.0.0.1:4560` into the APK's runtime config.
After install, the script sets up `adb reverse tcp:4560 tcp:4560` automatically — the app on the device reaches the host dev server through loopback.

Full TCP forwarding (HTTP/1.1, WebSocket upgrades, everything). No emulator needed.

```bash
# Deploy an already-built APK with reverse proxy
bun run adb

# Deploy + live logcat
bun run adb -- --log

# Custom dev port
QXP_DEV_PORT=3000 bun run adb
```

### QxChat NixOS integration (flake example)

This setup fetches QxChat from GitHub, imports its NixOS module, adds its package via overlay, and enables it system-wide.

```nix flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    qxchat-src = {
      url = "git+https://github.com/lqxp/app.git?ref=main&submodules=1";
      flake = false;
    };
  };

  outputs = { nixpkgs, qxchat-src, ... }:
  let
    system = "x86_64-linux";
  in {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        # QxChat module + package overlay
        {
          imports = [ "${qxchat-src}/nix/module.nix" ];

          nixpkgs.overlays = [
            (final: prev: {
              qxchat = prev.callPackage "${qxchat-src}/nix/qxchat.nix" { };
            })
          ];

          programs.qxchat.enable = true;
        }

        ./configuration.nix
      ];
    };
  };
}
```

Then apply it with:

```bash
sudo nixos-rebuild switch --flake .#my-host
```

## Permissions

The main Tauri capability is declared in `src-tauri/capabilities/default.json`.
It grants the bundled QXP web client access to core Tauri APIs, notification APIs for messaging, and restricted URL opening for QXP, `mailto:` and `tel:` links.

With `"withGlobalTauri": true`, the bundled page can use Tauri guest APIs through `window.__TAURI__` when needed, including notifications.

Native media permissions for macOS are declared in `src-tauri/Info.plist` for camera and microphone access used by calls or voice features in the remote web app. Speaker output does not require a separate Tauri permission.

On Android, runtime permissions (camera, microphone, notifications, media/storage) are prompted natively through the `permissions` Tauri plugin (`src-tauri/src/permissions.rs` + `com.getqxchat.app.PermissionsPlugin`). The client triggers a single grouped permission request once the user reaches the home screen after login/unlock, instead of relying on the WebView, which does not reliably surface those prompts. The granted Android permission strings are declared in `src-tauri/gen/android/app/src/main/AndroidManifest.xml`.

### Background keep-alive (Android)

Android aggressively suspends WebViews and kills background activities, which would tear down the frontend WebSocket (the socket that receives new messages) and long-lived WebRTC calls. To keep the app alive in the background QxChat runs a native foreground service (`com.getqxchat.app.ForegroundService`) with a partial wake lock and a persistent notification, controlled through the `background` Tauri plugin (`src-tauri/src/background.rs` + `com.getqxchat.app.BackgroundPlugin`). It is started once the user reaches the home screen after login/unlock.

Tauri exposes no foreground-service/background flag on Android (`backgroundThrottling` is documented as unsupported on Android). The native service is therefore the correct mechanism. The frontend WebSocket remains the sole owner of the QXP wire protocol and E2EE state (moving it to Rust would require reimplementing the encrypted message pipeline and WebRTC signaling); the native service guards the process so that socket survives.

## NixOS

`flake.nix` include the Linux dependencies that Tauri expects on NixOS, including GTK, WebKitGTK 4.1, GLib, `libsoup_3`, `librsvg`, and the GIO networking module setup required by WebKit.

### Calls (WebRTC) on NixOS

Stock nixpkgs `webkitgtk_4_1` is built with `enableExperimental = false`, and
upstream WebKit defaults `ENABLE_WEB_RTC` to `ENABLE_EXPERIMENTAL_FEATURES —
so the stock library has no `RTCPeerConnection` at all. The symptom is the
thread subtitle reporting that WebRTC is not supported, with the call button
disabled. This is a packaging flag, not an app bug.

Opt in (one full WebKit source build, then cached):

```nix
programs.qxchat = {
  enable = true;
  webrtcSupport = true;
};
```

Mic/camera/screen-share additionally need the host media stack, which the
wrapper cannot provide itself:

- `services.pipewire.enable = true` (with WirePlumber) for mic/camera.
- The portal backend matching your compositor for screen sharing, e.g.
  `programs.qxchat.extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];`
  on Hyprland (`-wlr` on Sway/wlroots, `-kde`/`-gnome` on those DEs).

### WebKitGTK flickering / blank window on NixOS

The DMABUF renderer + Mesa combination flickers or fails (`Failed to create
GBM buffer`, `EGL_BAD_PARAMETER`, empty window) on some GPUs and Wayland
sessions. Try, in order:

```bash
WEBKIT_DISABLE_DMABUF_RENDERER=1 qxchat   # helps most NVIDIA/Wayland setups
GDK_BACKEND=x11 qxchat                    # XWayland fallback
```

Note: forcing the legacy renderer is known to segfault the UI process on
AMD + Wayland with webkitgtk 2.52, so keep these as opt-in workarounds, not
defaults.

## License

MIT
