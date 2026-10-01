#!/usr/bin/env bash
# QxChat — local Flatpak build (primary Linux packaging).
# Builds the Tauri release binary, stages it, and installs the Flatpak for the
# current user: `bun run build:flatpak`.
set -euo pipefail

cd "$(dirname "$0")/.."

load_dotenv() {
  if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
  fi
}

load_dotenv

APP_ID="com.getqxchat.app"
MANIFEST="flatpak/${APP_ID}.yml"
BUILD_DIR="flatpak/build"
BUNDLE_OUT="flatpak/${APP_ID}.flatpak"

RUN_AFTER=0
BUILD_ONLY=0
MAKE_BUNDLE=0
for arg in "$@"; do
  case "$arg" in
    --run) RUN_AFTER=1 ;;
    --build-only) BUILD_ONLY=1 ;;
    --bundle) MAKE_BUNDLE=1 ;;
  esac
done

command -v flatpak >/dev/null 2>&1 || {
  echo "error: flatpak is required (nix develop provides it)." >&2
  exit 1
}

# 1. Release binary only (frontend dist + cargo release, no desktop bundles).
# Skip the AppImage FHS env (only needed for linuxdeploy bundling): plain
# `nix develop` already carries webkitgtk + toolchain, and the FHS re-exec
# breaks host/nix libc resolution at link time.
LQXP_APPIMAGE_FHS=1 scripts/tauri-build.sh --no-bundle

BIN="src-tauri/target/release/qxchat"
[[ -x "$BIN" ]] || {
  echo "error: release binary not found at $BIN." >&2
  exit 1
}

# 2. Stage files next to the manifest (gitignored copies).
cp -f "$BIN" flatpak/qxchat
cp -f src-tauri/icons/icon.png flatpak/icon.png
chmod +x flatpak/qxchat

if [[ "$BUILD_ONLY" == "1" ]]; then
  echo "Staged flatpak/qxchat + flatpak/icon.png (build-only, no flatpak-builder run)."
  exit 0
fi

command -v flatpak-builder >/dev/null 2>&1 || {
  echo "error: flatpak-builder is required (nix develop provides it)." >&2
  exit 1
}

# 3. Runtime + SDK (GNOME 50, matches local runtimes).
if ! flatpak info --user org.gnome.Platform//50 >/dev/null 2>&1 && ! flatpak info --system org.gnome.Platform//50 >/dev/null 2>&1; then
  flatpak install -y --user flathub org.gnome.Platform//50
fi
if ! flatpak info --user org.gnome.Sdk//50 >/dev/null 2>&1 && ! flatpak info --system org.gnome.Sdk//50 >/dev/null 2>&1; then
  flatpak install -y --user flathub org.gnome.Sdk//50
fi

# 4. Build + install for the current user.
# --disable-rofiles-fuse: FUSE unmount is denied in this env (nix/container),
# fall back to hardlinks. State stays inside flatpak/ (gitignored).
flatpak-builder --force-clean --user --install --disable-rofiles-fuse \
  --state-dir=flatpak/.flatpak-builder "$BUILD_DIR" "$MANIFEST"

if [[ "$MAKE_BUNDLE" == "1" ]]; then
  flatpak build-bundle ~/.local/share/flatpak/repo "$BUNDLE_OUT" "$APP_ID"
  echo "Bundle: $BUNDLE_OUT"
fi

if [[ "$RUN_AFTER" == "1" ]]; then
  flatpak run "$APP_ID"
else
  echo "Installed $APP_ID — run: flatpak run $APP_ID"
fi
