#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "${LQXP_ANDROID_BUILD_RUNNING:-}" != "1" ]]; then
  if command -v nix >/dev/null 2>&1 && [[ -f flake.nix ]]; then
    echo "Entering nix develop for Android build..."
    exec env TMPDIR=/tmp nix develop --command env TMPDIR=/tmp LQXP_ANDROID_BUILD_RUNNING=1 scripts/build-android.sh "$@"
  elif [[ "${IN_NIX_SHELL:-}" != "pure" && "${IN_NIX_SHELL:-}" != "impure" ]]; then
    if command -v nix-shell >/dev/null 2>&1 && [[ -f shell.nix ]]; then
      echo "Entering nix-shell for Android build..."
      printf -v quoted_args "%q " "$@"
      exec env TMPDIR=/tmp nix-shell --run "TMPDIR=/tmp LQXP_ANDROID_BUILD_RUNNING=1 scripts/build-android.sh ${quoted_args}"
    fi

  echo "warning: not running inside nix-shell/nix develop, continuing with the current environment." >&2
  fi
fi

command -v bun >/dev/null 2>&1 || {
  echo "error: bun is required." >&2
  exit 1
}

command -v rustup >/dev/null 2>&1 || {
  echo "error: rustup is required." >&2
  exit 1
}

export RUSTUP_TOOLCHAIN="${RUSTUP_TOOLCHAIN:-stable}"
export TMPDIR="/tmp"
export LQXP_RUSTUP_BIN_DIR="/tmp/lqxp-client-rustup-bin-${UID:-$(id -u)}"
mkdir -p "$LQXP_RUSTUP_BIN_DIR"

cat > "$LQXP_RUSTUP_BIN_DIR/cargo" <<'EOF'
#!/usr/bin/env bash
exec rustup run "${RUSTUP_TOOLCHAIN:-stable}" cargo "$@"
EOF

cat > "$LQXP_RUSTUP_BIN_DIR/rustc" <<'EOF'
#!/usr/bin/env bash
exec rustup run "${RUSTUP_TOOLCHAIN:-stable}" rustc "$@"
EOF

chmod +x "$LQXP_RUSTUP_BIN_DIR/cargo" "$LQXP_RUSTUP_BIN_DIR/rustc"
export PATH="$LQXP_RUSTUP_BIN_DIR:$PATH"
export CARGO="$LQXP_RUSTUP_BIN_DIR/cargo"
export RUSTC="$LQXP_RUSTUP_BIN_DIR/rustc"
hash -r 2>/dev/null || true

command -v cargo >/dev/null 2>&1 || {
  echo "error: cargo is required." >&2
  exit 1
}

is_release_build() {
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "--debug" ]]; then
      return 1
    fi
  done

  return 0
}

configure_android_release_signing() {
  is_release_build "$@" || return 0

  local keystore_properties="src-tauri/gen/android/keystore.properties"
  if [[ -f "$keystore_properties" && "${LQXP_REWRITE_ANDROID_KEYSTORE_PROPERTIES:-}" != "1" ]]; then
    return 0
  fi

  local keystore_path="${ANDROID_KEYSTORE_PATH:-$HOME/.config/lqxp-client/lqxp-release.jks}"
  local keystore_password="${ANDROID_KEYSTORE_PASSWORD:-}"
  local key_alias="${ANDROID_KEY_ALIAS:-lqxp}"
  local key_password="${ANDROID_KEY_PASSWORD:-$keystore_password}"

  if [[ ! -f "$keystore_path" && "${LQXP_ANDROID_CREATE_KEYSTORE:-}" == "1" ]]; then
    command -v keytool >/dev/null 2>&1 || {
      echo "error: keytool is required to create an Android release keystore." >&2
      exit 1
    }

    if [[ -z "$keystore_password" && -t 0 ]]; then
      read -rsp "Android release keystore password: " keystore_password
      echo
    fi

    if [[ -z "$keystore_password" ]]; then
      echo "error: ANDROID_KEYSTORE_PASSWORD is required when LQXP_ANDROID_CREATE_KEYSTORE=1." >&2
      exit 1
    fi

    key_password="${ANDROID_KEY_PASSWORD:-$keystore_password}"
    mkdir -p "$(dirname "$keystore_path")"
    keytool -genkeypair \
      -v \
      -keystore "$keystore_path" \
      -storepass "$keystore_password" \
      -alias "$key_alias" \
      -keypass "$key_password" \
      -keyalg RSA \
      -keysize 2048 \
      -validity 10000 \
      -dname "${ANDROID_KEY_DNAME:-CN=LQXP Client, OU=LQXP, O=LQXP, L=Unknown, ST=Unknown, C=XX}"
  fi

  if [[ -f "$keystore_path" && -n "$keystore_password" && -n "$key_alias" && -n "$key_password" ]]; then
    cat > "$keystore_properties" <<EOF
ANDROID_KEYSTORE_PATH=$keystore_path
ANDROID_KEYSTORE_PASSWORD=$keystore_password
ANDROID_KEY_ALIAS=$key_alias
ANDROID_KEY_PASSWORD=$key_password
EOF
    chmod 600 "$keystore_properties"
    echo "Android release signing enabled via $keystore_properties"
    return 0
  fi

  cat >&2 <<EOF
warning: release signing is not configured; Gradle will produce an unsigned APK.
To create and use a local release keystore, run for example:
  LQXP_ANDROID_CREATE_KEYSTORE=1 ANDROID_KEYSTORE_PASSWORD='change-me' bun run build:android -- --apk --target aarch64
Or set ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS and optionally ANDROID_KEY_PASSWORD.
EOF
}

if [[ -z "${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}" ]]; then
  echo "error: ANDROID_SDK_ROOT/ANDROID_HOME is not set. Run through nix-shell or nix develop." >&2
  exit 1
fi

if [[ -z "${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME:-${NDK_HOME:-}}}" ]]; then
  echo "error: ANDROID_NDK_ROOT/ANDROID_NDK_HOME/NDK_HOME is not set. Run through nix-shell or nix develop." >&2
  exit 1
fi

if declare -F lqxp-rustup-android-targets >/dev/null 2>&1; then
  lqxp-rustup-android-targets
else
  rustup toolchain install "$RUSTUP_TOOLCHAIN" --profile minimal
  rustup target add --toolchain "$RUSTUP_TOOLCHAIN" \
    aarch64-linux-android \
    armv7-linux-androideabi \
    i686-linux-android \
    x86_64-linux-android
fi

if [[ ! -d src-tauri/gen/android || "${LQXP_FORCE_ANDROID_INIT:-}" == "1" ]]; then
  bun tauri android init
fi

local_properties="src-tauri/gen/android/local.properties"
if [[ ! -f "$local_properties" || "${LQXP_REWRITE_ANDROID_LOCAL_PROPERTIES:-}" == "1" ]]; then
  {
    echo "# Generated by scripts/build-android.sh"
    echo "sdk.dir=${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
    echo "ndk.dir=${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME:-$NDK_HOME}}"
    if [[ -n "${CMAKE_ROOT:-}" ]]; then
      echo "cmake.dir=$CMAKE_ROOT"
    fi
  } > "$local_properties"
fi

bun install --no-save
(cd QxpClient && bun install --no-save)

build_args=("$@")
if [[ ${#build_args[@]} -eq 0 ]]; then
  build_args=(--debug --apk)
fi

configure_android_release_signing "${build_args[@]}"

bun tauri android build "${build_args[@]}"

echo
echo "APK output(s):"
find src-tauri/gen/android/app/build/outputs -name "*.apk" -print 2>/dev/null || true
