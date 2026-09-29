# AGENTS.md — lqxp client (web)

Vue 3 + TypeScript official web client for QxChat: in-browser E2EE, WebRTC
calls, offline-capable UI. All crypto and sync authentication happen here —
the server (`lqxp/lqxp`) is a blind relay.

## Layout

- `client/src/composables/useMessenger.ts` — WS dispatch, rooms, calls.
- `client/src/composables/useCloudSync.ts` — QxCloudSync device mesh
  (handshakes, epochs, snapshots, healing contract §9.1.1).
- `client/src/crypto/` — `cloudsync.ts` (sync envelopes), `phantom.ts`,
  `e2ee.ts`, `slhdsa.ts`.
- `client/src/composables/phantomBridge.ts` — op bridge
  (messenger ↔ phantom/cloudsync).
- `client/src/composables/useI18n.ts` — user-facing translations.

## Build / test / lint

```sh
cd client
bun run typecheck   # vue-tsc; pre-existing errors in unrelated components only — add none in touched files
bun run build       # vite build + runtime-config inject; must succeed
```

No unit-test harness; relay-affecting changes must at minimum typecheck and
build.

## Languages — ENGLISH ONLY IN CODE

- **All code comments MUST be English**: concise, technical, no
  chain-of-thought. This applies to every file, including the sync stack.
- String literals are the only exception: French UI text stays French (it is
  user-facing content, translated via `useI18n` where wired).
- Server error keys stay stable English — never translate them client-side
  for logic; match on the exact key.

## Sync rules (QxCloudSync)

- Follow `explain/09-qxcloudsync.md` (§9.1.1 healing contract) in `lqxp/lqxp`:
  op 60 ack (`delivered/dropped/peers/peerCount`), op 62 directory,
  op 63 presence.
- Handshake: hello → accept → confirm, HMAC + ECDSA + SLH-DSA all verified,
  fail closed. Canonical JSON (sorted keys) for transcripts — never
  `JSON.stringify`.
- Anti-replay: per-peer `(syncId, epoch)` high-water + bounded dedup; LWW
  merge makes residual replays harmless.
- Anti-storm guards on every auto-action: unicast fallback 1/30s/peer,
  same-route retry 1/10s/peer, proactive hello 1/30s global, re-handshake /
  rekey resend 1/min/peer.
- Backward compat: gate new-relay behavior on caps (e.g. `relayMeshCaps`
  set by first ack carrying `delivered`) so old servers change nothing.
- `peerWs` (server routing hint) is unauthenticated: learn it only from
  verified inbound traffic or verified handshakes, and only act on envelopes
  with `outer.to === own device id`.
- Secrets (masters, epoch keys, syncRoot, SLH cache) live in RAM only,
  wiped on client lock; persisted blobs are AES-GCM envelopes.

## Git

- This checkout (`client/`) is its own repo (`lqxp/client`); the parent
  directory bumps the pointer after each client push.
- Branch `main`; messages: `feat|fix|docs|chore(scope): subject`.
- Never force-push `main`.
