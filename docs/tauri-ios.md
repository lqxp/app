# Tauri iOS build

The iOS build belongs to this repository root. The Tauri project is `src-tauri`, and it packages the frontend from the `client` submodule.

## Local build

iOS builds require macOS with the full Xcode app installed.

```bash
nix develop
bun run ios:build --export-method development
```

Without Nix:

```bash
./scripts/ios-build.sh --export-method development
```

Useful environment variables:

- `APPLE_DEVELOPMENT_TEAM`: Apple Developer Team ID used by Tauri/Xcode signing.
- `QXP_RUNTIME_CONFIG_URL`: URL used by `client/scripts/sync-runtime-config.mjs` to copy runtime server/RTC settings into the packaged app.
- `QXP_SERVER_ORIGIN`: overrides the packaged server origin.
- `QXP_API_BASE_URL`: overrides the packaged HTTP API base URL.
- `QXP_WS_URL`: overrides the packaged WebSocket URL.
- `QXP_TURN_URLS`: comma-separated TURN URLs.
- `QXP_TURN_USERNAME`: TURN username.
- `QXP_TURN_CREDENTIAL`: TURN credential or shared secret.
- `QXP_RELAY_ONLY`: enables relay-only WebRTC mode when set to `true`.
- `QXP_CALLS_ENABLED`: enables/disables calls at build time.
- `QXP_CALLS_UNAVAILABLE_REASON`: default reason shown when calls are disabled.
- `LQXP_FORCE_IOS_INIT=1`: regenerates the Tauri Apple project before building.

`QXP_RUNTIME_CONFIG_URL` is optional. If it is not set, the packaged `runtime-config.js` is generated directly from the environment variables above.

The IPA is generated under:

```text
src-tauri/gen/apple/build/arm64/
```

## Development on a simulator or device

```bash
nix develop
bun run ios:dev -- --open
```

## GitHub Actions signing secrets

The existing `Build And Release` workflow builds the signed IPA in `.github/workflows/build-and-release.yml`.
Configure:

- `APPLE_DEVELOPMENT_TEAM`
- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_PROVISIONING_PROFILE_BASE64`
- `APPLE_KEYCHAIN_PASSWORD` optional

Example encoding commands on macOS:

```bash
base64 -i Certificates.p12 | pbcopy
base64 -i LQXP.mobileprovision | pbcopy
```
