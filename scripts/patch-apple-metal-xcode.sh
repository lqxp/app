#!/usr/bin/env bash
# Patches the cached apple-metal Swift bridge so it compiles with Xcode < 26.
#
# Background: every apple-metal release (0.6.x-0.9.x) contains this block in
# swift-bridge/Sources/AppleMetalBridge/State.swift:
#
#     if #available(macOS 26.0, *) {
#         descriptor.reductionMode = MTLSamplerReductionMode(...)!
#         descriptor.lodBias = lodBias
#     }
#
# `#available` is a *runtime* guard, but the compiler still type-checks the
# body against the SDK. On Xcode < 26 (e.g. the macos-15-intel runner, which
# can never install Xcode 26) `MTLSamplerReductionMode` / `reductionMode` /
# `lodBias` do not exist, so the Swift build fails with "cannot find ... in
# scope" / "has no member". Wrapping the block in `#if swift(>=6.2)` compiles
# it out on old toolchains (Xcode 26 ships Swift 6.2) while keeping upstream
# behavior on new ones. QxChat never configures sampler reductionMode/lodBias
# (we only use ScreenCaptureKit audio), so this is behavior-preserving for us.
set -euo pipefail

patched=0
for state in "$HOME/.cargo/registry/src/"*/apple-metal-*/swift-bridge/Sources/AppleMetalBridge/State.swift; do
  [ -f "$state" ] || continue
  if grep -q '#if swift(>=6.2)' "$state"; then
    echo "already patched: $state"
    patched=1
    continue
  fi
  if ! grep -q 'MTLSamplerReductionMode' "$state"; then
    echo "no broken block found (already fixed upstream?): $state"
    patched=1
    continue
  fi
  python3 - "$state" <<'EOF'
import sys
path = sys.argv[1]
src = open(path).read()
old = """    if #available(macOS 26.0, *) {
        descriptor.reductionMode = MTLSamplerReductionMode(rawValue: reductionMode) ?? MTLSamplerReductionMode(rawValue: 0)!
        descriptor.lodBias = lodBias
    }
"""
new = """    #if swift(>=6.2)
    if #available(macOS 26.0, *) {
        descriptor.reductionMode = MTLSamplerReductionMode(rawValue: reductionMode) ?? MTLSamplerReductionMode(rawValue: 0)!
        descriptor.lodBias = lodBias
    }
    #endif
"""
assert old in src, f"pattern not found in {path}"
open(path, "w").write(src.replace(old, new))
print(f"patched: {path}")
EOF
  patched=1
done

if [ "$patched" -eq 0 ]; then
  echo "apple-metal State.swift not in cargo cache yet (fresh cache) - nothing to patch."
fi
