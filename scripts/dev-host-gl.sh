#!/usr/bin/env bash
# Dev launcher for machines where the nix GL stack cannot create an EGL
# display (gray window + `EGL_BAD_PARAMETER`): runs the dev client with the
# HOST drivers via nixGL under XWayland, instead of nix llvmpipe.
#
# Requires: XWayland running (`ls /tmp/.X11-unix`), nixGL fetchable.
# Backend target + dev identifier come from client/.env.development and
# src-tauri/tauri.dev.conf.json — no manual exports needed.
set -euo pipefail

# nixGL is NOT a replacement for `nix develop`: it only swaps the GL stack.
# The GTK/pkg-config build env must already be present.
if [ -z "${PKG_CONFIG_PATH:-}" ]; then
  echo "error: no nix build env detected (PKG_CONFIG_PATH empty)." >&2
  echo "Run this script from inside \`nix develop\` first, then retry." >&2
  exit 1
fi

export DISPLAY="${DISPLAY:-:1}"
export GDK_BACKEND=x11
# Root cause of the dev gray-window/segfault loop (block/buzz#3654):
# WEBKIT_DISABLE_DMABUF_RENDERER empties the buffer transport mode on current
# WebKitGTK (-> nullptr backing store -> SEGV). Force shared-memory transport
# instead; the flake devShell already does this, this covers stale shells.
export -n WEBKIT_DISABLE_DMABUF_RENDERER 2>/dev/null || unset WEBKIT_DISABLE_DMABUF_RENDERER
export WEBKIT_DMABUF_RENDERER_FORCE_SHM=1
# Host drivers take over: drop the nix software-GL fallbacks for this run.
unset LIBGL_ALWAYS_SOFTWARE 2>/dev/null || true
unset WEBKIT_DISABLE_COMPOSITING_MODE 2>/dev/null || true

exec nix run --impure github:nix-community/nixGL -- bun run dev "$@"
