<div align="center">
  <img src="https://getqxchat.com/app-icon-with-name.svg" alt="QxChat logo" width="320" />

  # QxChat — Desktop & Mobile App

  **End-to-end encrypted messaging, native everywhere. One codebase, six platforms, zero tracking.**

  [![License: MIT](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](./LICENSE)
  [![Tauri v2](https://img.shields.io/badge/Tauri-v2-24c8db?style=flat-square&logo=tauri)](./src-tauri)
  [![Vue 3](https://img.shields.io/badge/client-Vue_3-42b883?style=flat-square&logo=vue.js)](https://github.com/lqxp/client)
  [![Nix](https://img.shields.io/badge/builds-Nix-5277c3?style=flat-square&logo=nixos)](./nix)
  [![Linux](https://img.shields.io/badge/Linux-AppImage%2Fdeb%2Frpm-e95420?style=flat-square&logo=linux)](https://github.com/lqxp/app/releases)
  [![Windows](https://img.shields.io/badge/Windows-msi-0078d4?style=flat-square&logo=windows)](https://github.com/lqxp/app/releases)
  [![macOS](https://img.shields.io/badge/macOS-dmg-000000?style=flat-square&logo=apple)](https://github.com/lqxp/app/releases)
  [![Android](https://img.shields.io/badge/Android-apk-3ddc84?style=flat-square&logo=android)](https://github.com/lqxp/app/releases)

  <a href="https://getqxchat.com/download"><strong>Download</strong></a>
  ·
  <a href="https://qxch.at/app">Web app</a>
  ·
  <a href="https://getqxchat.com/wiki">Wiki</a>
  ·
  <a href="https://discord.wf/qxchat">Discord</a>
  ·
  <a href="https://github.com/lqxp">GitHub</a>
</div>

---

## What is this?

`lqxp/app` packages the [QxChat web client](https://github.com/lqxp/client) (Vue 3, E2EE via Web Crypto) into **native apps with Tauri v2**: system notifications, tray, auto-updater, embedded Tor, background services on Android — the full desktop and mobile experience from a single codebase.

> Same rooms, same keys, every screen. Pair your devices once with [QxCloudSync](https://getqxchat.com/wiki/qxcloudsync) and everything follows.

---

## Features

- ★ **Native shell** — system tray, native notifications, auto-updates from GitHub releases, deep polish per OS.
- ★ **Embedded Tor** — one-click Tor routing with live circuit map, relay directory, and geo view.
- ★ **Device sync** — rooms, messages, settings and keys across phone, desktop and web via QxCloudSync.
- ★ **Calls & whiteboard** — WebRTC voice, per-user volume, collaborative whiteboard, polls, spoiler effects.
- ★ **Privacy modes** — client lock, RAM-only OPSEC, decoy vault, streamer mode, 12-word recovery.
- ★ **Extras** — Discord Rich Presence, custom themes, EN/FR/RU/ES locales, screen-share audio.

---

## Platforms & artifacts

| Platform | Artifacts (per release) |
|---|---|
| Linux x64 / arm64 | AppImage · `.deb` · `.rpm` · NixOS module |
| Windows x64 / arm64 | `.msi` (signed, VirusTotal-scanned) |
| macOS arm64 / x64 | `.dmg` (ad-hoc signed) |
| Android | signed `.apk` |
| iOS | unsigned `.ipa` (self-sign) |

Grab the latest build on the [**releases page**](https://github.com/lqxp/app/releases) or the [**download hub**](https://getqxchat.com/download). The in-app updater notifies you of new versions automatically.

### NixOS (one-liner)

```nix
{
  inputs.qxchat.url = "github:lqxp/app/releases/download/v1.20.8/QxChat_1.20.8_flake.nix";
  # ... see release assets for the exact URL of your version
}
```

```nix
{ inputs, ... }: {
  imports = [ inputs.qxchat.nixosModules.default ];
  nixpkgs.overlays = [ inputs.qxchat.overlays.default ];
  programs.qxchat.enable = true;
}
```

---

## For contributors

The web client lives in the [`client/`](./client) submodule ([`lqxp/client`](https://github.com/lqxp/client)); the native shell in [`src-tauri/`](./src-tauri) (Rust); reproducible packaging in [`nix/`](./nix).

```sh
git clone --recurse-submodules https://github.com/lqxp/app
cd app
bun install && bun run dev        # Tauri dev window
```

Releases are cut with `python3 scripts/bump-version.py [patch|minor|major]` (bumps client + Tauri + Nix, tags, CI builds all six platforms). **The full technical manual — builds per OS, Android signing, iOS, NixOS module, capabilities, environment injection — lives in [`docs/BUILD.md`](./docs/BUILD.md).**

---

<div align="center">
  <sub>Built on Internet · Open source · No tracking</sub>
  <br />
  <a href="https://qxch.at/app">qxch.at/app</a>
  |
  <a href="https://getqxchat.com/download">download</a>
  |
  <a href="https://getqxchat.com/wiki">wiki</a>
  |
  <a href="https://discord.wf/qxchat">discord.wf/qxchat</a>
  |
  <a href="https://github.com/lqxp">github.com/lqxp</a>
</div>
