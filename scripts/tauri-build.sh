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

build_target=""
for arg in "$@"; do
  if [[ "$arg" == --target=* ]]; then
    build_target="${arg#--target=}"
    break
  fi
done
if [[ -z "$build_target" ]]; then
  for ((i = 1; i <= $#; i++)); do
    if [[ "${!i}" == "--target" ]]; then
      next=$((i + 1))
      if [[ $next -le $# ]]; then
        build_target="${!next}"
      fi
      break
    fi
  done
fi

if [[ -n "$build_target" ]] && command -v rustup >/dev/null 2>&1; then
  rustup target add "$build_target"
fi

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
  exec "$fhs_env/bin/qxchat-appimage-build-env" -c "scripts/tauri-build.sh ${quoted_args}"
fi

if [[ "$(uname -s)" == "Linux" ]]; then
  chmod -R u+w "src-tauri/target/release/bundle/appimage" 2>/dev/null || true
  rm -rf "src-tauri/target/release/bundle/appimage"
fi

LQXP_TAURI_BUILD_RUNNING=1 exec bun tauri build "$@"
