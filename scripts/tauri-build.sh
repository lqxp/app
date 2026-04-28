#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

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

exec bun tauri build "$@"
