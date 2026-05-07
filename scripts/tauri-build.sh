#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

load_dotenv() {
  if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
    export LQXP_DOTENV_LOADED=1
  fi
}

load_dotenv

if [[ "${LQXP_TAURI_BUILD_RUNNING:-}" == "1" ]]; then
  echo "Refusing to run scripts/tauri-build.sh from inside tauri build; check beforeBuildCommand." >&2
  exit 1
fi

if [[ "$(uname -s)" == "Linux" && ! -x /usr/bin/xdg-open && "${LQXP_APPIMAGE_FHS:-}" != "1" ]]; then
  if [[ -d "$HOME/.cache/tauri" ]]; then
    chmod -R a+rX "$HOME/.cache/tauri"
  fi
  fhs_env="$(nix-build nix/appimage-shell.nix --no-out-link)"
  printf -v quoted_args "%q " "$@"
  exec "$fhs_env/bin/lqxp-client-appimage-build-env" -c "scripts/tauri-build.sh ${quoted_args}"
fi

if [[ "$(uname -s)" == "Linux" ]]; then
  chmod -R u+w "src-tauri/target/release/bundle/appimage" 2>/dev/null || true
  rm -rf "src-tauri/target/release/bundle/appimage"
fi

LQXP_TAURI_BUILD_RUNNING=1 exec bun tauri build "$@"
