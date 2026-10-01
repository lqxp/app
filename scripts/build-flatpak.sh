#!/usr/bin/env bash
# QxChat — local Flatpak build (primary Linux packaging).
#
# The binary is compiled INSIDE the GNOME SDK sandbox: a Nix-built binary
# cannot run under the Flatpak runtime (its /nix loader is absent there).
# This script stages everything the offline sandbox build needs — a pinned
# upstream Rust toolchain, the built frontend, vendored cargo deps — then
# flatpak-builder compiles and installs for the current user.
#
#   ./scripts/build-flatpak.sh            # stage + build + install --user
#   ./scripts/build-flatpak.sh --run      # + launch
#   ./scripts/build-flatpak.sh --bundle   # + emit flatpak/com.getqxchat.app.flatpak
#   ./scripts/build-flatpak.sh --build-only # stage only, no flatpak-builder run
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

if [[ "${LQXP_FLATPAK_BUILD_RUNNING:-}" != "1" ]]; then
  if command -v nix >/dev/null 2>&1 && [[ -f flake.nix ]]; then
    echo "Entering nix develop for Flatpak staging..."
    exec env TMPDIR=/tmp LQXP_FLATPAK_BUILD_RUNNING=1 nix develop \
      --command scripts/build-flatpak.sh "$@"
  fi
  echo "warning: not running inside nix develop, continuing with the current environment." >&2
fi

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
STAGING="flatpak/staging"
BUNDLE_OUT="flatpak/${APP_ID}.flatpak"

# Pinned upstream Rust (static.rust-lang.org tarball, self-contained).
RUST_VERSION="1.92.0"
RUST_TARBALL="$STAGING/rust-toolchain.tar.gz"
RUST_URL="https://static.rust-lang.org/dist/rust-${RUST_VERSION}-x86_64-unknown-linux-gnu.tar.gz"

RUN_AFTER=0
MAKE_BUNDLE=0
BUILD_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --run) RUN_AFTER=1 ;;
    --bundle) MAKE_BUNDLE=1 ;;
    --build-only) BUILD_ONLY=1 ;;
  esac
done

command -v bun >/dev/null 2>&1 || { echo "error: bun is required." >&2; exit 1; }
command -v cargo >/dev/null 2>&1 || { echo "error: cargo is required." >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "error: curl is required." >&2; exit 1; }

mkdir -p "$STAGING"
# Legacy flat staging locations (pre-tarroot layout) — remove once.
rm -rf "$STAGING/src-tauri" "$STAGING/client" "$STAGING/vendor" "$STAGING/.cargo" "$STAGING/tray-libs" "$STAGING/${APP_ID}.desktop" "$STAGING/${APP_ID}.metainfo.xml"

# 0. Rust toolchain (downloaded once, then cached).
if [[ ! -f "$RUST_TARBALL" ]]; then
  echo "Fetching Rust $RUST_VERSION toolchain (one-time, ~300MB)..."
  curl -fL --retry 3 -o "$RUST_TARBALL" "$RUST_URL"
fi
rm -rf "$STAGING/toolchain"
mkdir -p "$STAGING/toolchain"
tar -xzf "$RUST_TARBALL" -C "$STAGING/toolchain" --strip-components=1
[[ -f "$STAGING/toolchain/install.sh" ]] || {
  echo "error: toolchain extract looks wrong (no install.sh)." >&2
  exit 1
}
# Assemble a proper prefix layout once (rustc discovers its sysroot relative
# to its own binary; the raw component dirs are NOT directly usable).
if [[ ! -x "$STAGING/toolchain-install/bin/rustc" || ! -f "$STAGING/toolchain-install/.toolchain-stamp" || "$(cat "$STAGING/toolchain-install/.toolchain-stamp")" != "$RUST_VERSION" ]]; then
  echo "Assembling Rust $RUST_VERSION prefix (one-time per version)..."
  rm -rf "$STAGING/toolchain-install"
  (cd "$STAGING/toolchain" && ./install.sh --prefix="$ROOT/$STAGING/toolchain-install" --without=rust-docs,rust-docs-json-preview --disable-ldconfig >/dev/null)
  echo "$RUST_VERSION" > "$STAGING/toolchain-install/.toolchain-stamp"
fi
"$STAGING/toolchain-install/bin/rustc" --version

# 1. Frontend dist (built outside: sandbox has no network for bun install).
(cd client && bun install --no-save && bun run build:tauri)
[[ -d client/dist ]] || { echo "error: client/dist missing after frontend build." >&2; exit 1; }

# Everything the sandbox needs is assembled physically under tarroot/app/
# (no tar --transform: it also rewrites symlink targets and breaks them).
TROOT="$STAGING/tarroot/app"

# 2. Vendored cargo deps (re-done only when Cargo.lock changes).
lock_hash="$(sha256sum src-tauri/Cargo.lock | cut -d' ' -f1)-${RUST_VERSION}"
if [[ ! -d "$TROOT/vendor" || ! -f "$STAGING/.vendor-hash" || "$(cat "$STAGING/.vendor-hash")" != "$lock_hash" ]]; then
  echo "Vendoring cargo dependencies..."
  rm -rf "$TROOT/vendor" "$TROOT/.cargo"
  mkdir -p "$TROOT/.cargo"
  (cd src-tauri && cargo vendor "$ROOT/$TROOT/vendor" > "$ROOT/$TROOT/.cargo/config.toml")
  # cargo vendor prints an ABSOLUTE directory path (valid only on this host);
  # the sandbox needs the path relative to .cargo/config.toml instead.
  sed -i 's|^directory = .*|directory = "vendor"|' "$TROOT/.cargo/config.toml"
  grep -q '^directory = "vendor"$' "$TROOT/.cargo/config.toml" || {
    echo "error: failed to relativize vendor directory in cargo config." >&2
    exit 1
  }
  echo "$lock_hash" > "$STAGING/.vendor-hash"
else
  echo "Vendor cache hit (Cargo.lock unchanged)."
fi

# 2.5 Tray stack (Ayatana) from the LOCKED nixpkgs: the GNOME runtime ships
# no appindicator libs and libappindicator-sys panics at startup without
# them. Only libs absent from the runtime are staged (glibc matches: 2.42).
echo "Resolving tray libraries from nixpkgs..."
tray_paths="$(nix build --impure --print-out-paths --no-link --expr 'with (builtins.getFlake "'"$ROOT"'").inputs.nixpkgs.legacyPackages.x86_64-linux; [ libayatana-appindicator libayatana-indicator libdbusmenu-gtk3 dbus-glib ayatana-ido ]')"
rm -rf "$TROOT/tray-libs"
mkdir -p "$TROOT/tray-libs"
for pat in 'libayatana-appindicator3.so*' 'libayatana-indicator*.so*' 'libayatana-ido*.so*' 'libdbusmenu-glib.so*' 'libdbusmenu-gtk3.so*' 'libdbus-glib-1.so*'; do
  # shellcheck disable=SC2086
  matches="$(find $tray_paths -maxdepth 4 \( -type f -o -type l \) -name "$pat" -print)"
  [[ -n "$matches" ]] || { echo "error: no nixpkgs lib matches $pat." >&2; exit 1; }
  # shellcheck disable=SC2086
  cp -d $matches "$TROOT/tray-libs/"
done
echo "Tray libs staged:"
ls "$TROOT/tray-libs/"

# 3. Stage source tree: src-tauri minus build junk + built frontend.
rm -rf "$TROOT/src-tauri" "$TROOT/client"
tar -cf - -C . \
  --exclude='src-tauri/target' \
  --exclude='src-tauri/gen/android/app/build' \
  --exclude='src-tauri/gen/android/build' \
  --exclude='src-tauri/gen/android/.gradle' \
  --exclude='src-tauri/vendor' \
  --exclude='src-tauri/.cargo' \
  src-tauri client/dist | tar -xf - -C "$TROOT"
cp -f "flatpak/${APP_ID}.desktop" "flatpak/${APP_ID}.metainfo.xml" "$TROOT/"

# 4. Single archive source (unambiguous layout for flatpak-builder).
# NOTE: flatpak-builder strips the first path component when extracting
# archives (and drops bare top-level files), so the archive nests everything
# under app/: buildroot ends up with src-tauri/, client/, vendor/, .cargo/,
# tray-libs/ and the desktop/metainfo files, exactly what the manifest
# expects. The nesting is physical (no tar --transform, which also rewrites
# symlink targets and silently breaks them).
rm -f "$STAGING/sources.tar.gz"
tar -czf "$STAGING/sources.tar.gz" -C "$STAGING/tarroot" app
tar -tzf "$STAGING/sources.tar.gz" | awk -F/ '{print $1"/"$2}' | sort -u | head -n 10
echo "Staged $(du -sh "$STAGING/sources.tar.gz" | cut -f1) of sandbox sources."

if [[ "$BUILD_ONLY" == "1" ]]; then
  echo "Build-only: staging ready, flatpak-builder not run."
  exit 0
fi

command -v flatpak >/dev/null 2>&1 || { echo "error: flatpak is required." >&2; exit 1; }
command -v flatpak-builder >/dev/null 2>&1 || { echo "error: flatpak-builder is required (nix develop provides it)." >&2; exit 1; }

# 5. Runtime + SDK (GNOME 50).
for ref in org.gnome.Platform//50 org.gnome.Sdk//50; do
  if ! flatpak info --user "$ref" >/dev/null 2>&1 && ! flatpak info --system "$ref" >/dev/null 2>&1; then
    flatpak install -y --user flathub "$ref"
  fi
done

# 6. Build + install for the current user.
# Always --force-clean: flatpak-builder refuses to reuse flatpak/build
# across runs in this setup (finished or not), and a deterministic clean
# build is what a release wants. Cargo recompiles from scratch (~800 crates),
# so a build takes a while; vendor/toolchain/frontend stay cached in staging.
BUILDER_ARGS=(--force-clean --user --install --disable-rofiles-fuse --state-dir=flatpak/.flatpak-builder)
flatpak-builder "${BUILDER_ARGS[@]}" "$BUILD_DIR" "$MANIFEST"
# flatpak re-creates the exports icon index read-only on every install,
# which breaks the NEXT install's export step: keep it writable.
chmod u+w ~/.local/share/flatpak/exports/share/icons/hicolor/index.theme 2>/dev/null || true

if [[ "$MAKE_BUNDLE" == "1" ]]; then
  flatpak build-bundle ~/.local/share/flatpak/repo "$BUNDLE_OUT" "$APP_ID"
  echo "Bundle: $BUNDLE_OUT"
fi

if [[ "$RUN_AFTER" == "1" ]]; then
  flatpak run "$APP_ID"
else
  echo "Installed $APP_ID — run: flatpak run $APP_ID"
fi
