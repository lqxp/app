#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ $# -lt 1 ]]; then
  echo "error: expected Tauri build arguments." >&2
  exit 1
fi

export RUSTUP_TOOLCHAIN="${RUSTUP_TOOLCHAIN:-stable}"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    command -v rustup >/dev/null 2>&1 || {
      echo "error: rustup is required." >&2
      exit 1
    }

    rustup show active-toolchain
    command -v cargo
    cargo --version
    command -v rustc
    rustc --version
    ;;
  *)
    export TMPDIR="${TMPDIR:-/tmp}"
    export LQXP_RUSTUP_BIN_DIR="${TMPDIR}/lqxp-client-rustup-bin-${UID:-$(id -u)}"
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

    rustup show active-toolchain
    command -v cargo
    cargo --version
    command -v rustc
    rustc --version
    ;;
esac

bun install --frozen-lockfile
(cd client && bun install --frozen-lockfile)

bun run tauri build "$@"
