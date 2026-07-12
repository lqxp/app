#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ "${QXP_WINDOWS_BUILD_SHELL:-}" != "1" ]; then
  exec nix develop .#windows -c env QXP_WINDOWS_BUILD_SHELL=1 bash "$0" "$@"
fi

export QXP_SERVER_ORIGIN="${QXP_SERVER_ORIGIN:-https://qxch.at}"
export QXP_API_BASE_URL="${QXP_API_BASE_URL:-https://qxch.at}"
export QXP_WS_URL="${QXP_WS_URL:-wss://qxch.at/ws}"
export QXP_CALLS_ENABLED="${QXP_CALLS_ENABLED:-true}"
export QXP_RELAY_ONLY="${QXP_RELAY_ONLY:-true}"
export QXP_TURN_URLS="${QXP_TURN_URLS:-turn:turn.qxp.kisakay.com:3478?transport=udp,turn:turn.qxp.kisakay.com:3478?transport=tcp,turns:turn.qxp.kisakay.com:5349?transport=tcp}"
export QXP_TURN_USERNAME="${QXP_TURN_USERNAME:-qxp-turn}"
export QXP_TURN_CREDENTIAL="${QXP_TURN_CREDENTIAL:-df64240e730e15fdfb75d6cff95367b95ed341bd98517544}"

export CARGO_BUILD_TARGET=x86_64-pc-windows-gnu
export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-gcc
export CC_x86_64_pc_windows_gnu=x86_64-w64-mingw32-gcc
export CXX_x86_64_pc_windows_gnu=x86_64-w64-mingw32-g++
export AR_x86_64_pc_windows_gnu=x86_64-w64-mingw32-ar
export RANLIB_x86_64_pc_windows_gnu=x86_64-w64-mingw32-ranlib

bun install --no-save
bun tauri build --target x86_64-pc-windows-gnu "$@"
