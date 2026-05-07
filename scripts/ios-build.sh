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

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: iOS builds require macOS with the full Xcode app installed." >&2
  exit 1
fi

command -v bun >/dev/null 2>&1 || {
  echo "error: bun is required." >&2
  exit 1
}

command -v rustup >/dev/null 2>&1 || {
  echo "error: rustup is required." >&2
  exit 1
}

command -v xcodebuild >/dev/null 2>&1 || {
  echo "error: Xcode is required." >&2
  exit 1
}

xcodebuild -version >/dev/null

if ! command -v pod >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "CocoaPods is missing; installing it with Homebrew..."
    brew install cocoapods
  else
    echo "error: CocoaPods is required. Install Homebrew, then run: brew install cocoapods" >&2
    exit 1
  fi
fi

rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim

bun install --no-save
(cd client && bun install --no-save)

if [[ ! -d src-tauri/gen/apple || "${LQXP_FORCE_IOS_INIT:-}" == "1" ]]; then
  bun run ios:init
fi

bun tauri ios build "$@"
