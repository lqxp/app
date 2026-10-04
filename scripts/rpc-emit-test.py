#!/usr/bin/env python3
"""Minimal Discord-RPC IPC emitter to test QxChat rich activity.

Talks to the embedded rsRPC server (same wire as real Discord):
  socket  : $XDG_RUNTIME_DIR/discord-ipc-0..9 (fallback /tmp, $TMPDIR, $TMP, $TEMP)
  handshake: opcode 0 {"v":1,"client_id":...}
  activity : opcode 1 {"cmd":"SET_ACTIVITY","args":{"pid":...,"activity":{...}},"nonce":...}

Usage:
  python3 scripts/rpc-emit-test.py              # full Zed demo, holds 120s
  python3 scripts/rpc-emit-test.py --dry-run    # print frames without socket
  python3 scripts/rpc-emit-test.py --clear      # clear the activity and exit
  python3 scripts/rpc-emit-test.py --name Spotify --type 2 --details "Song" --state "Artist" \
      --large https://cdn.discordapp.com/embed/avatars/0.png

While it holds, the QxChat desktop client (`bunx tauri dev`) should show the
profile card with name + details + state + elapsed + artwork (via
GET /api/activity/assets). Ctrl-C clears and exits.
"""

import argparse
import json
import os
import socket
import struct
import sys
import time

OP_HANDSHAKE = 0
OP_FRAME = 1

# Stable direct PNGs (no redirect — the server proxy only follows same-host).
DEFAULT_LARGE = "https://cdn.discordapp.com/embed/avatars/0.png"
DEFAULT_SMALL = "https://cdn.discordapp.com/embed/avatars/1.png"


def find_socket() -> str:
    xdg = os.environ.get("XDG_RUNTIME_DIR", "")
    tmpdir = os.environ.get("TMPDIR", "")
    tmp = os.environ.get("TMP", "")
    temp = os.environ.get("TEMP", "")
    base = xdg or tmpdir or tmp or temp or "/tmp"
    base = base.rstrip("/") + "/"
    for i in range(10):
        path = f"{base}discord-ipc-{i}"
        # Try connect later; prefer first existing socket file.
        if os.path.exists(path):
            return path
    return f"{base}discord-ipc-0"


def recv_frame(sock: socket.socket, timeout: float = 5.0):
    sock.settimeout(timeout)
    try:
        hdr = b""
        while len(hdr) < 8:
            chunk = sock.recv(8 - len(hdr))
            if not chunk:
                return None, None
            hdr += chunk
        op, length = struct.unpack("<II", hdr)
        data = b""
        while len(data) < length:
            chunk = sock.recv(length - len(data))
            if not chunk:
                break
            data += chunk
        return op, data.decode("utf-8", "replace")
    except socket.timeout:
        return None, None


def send_frame(sock: socket.socket, op: int, payload: str):
    raw = payload.encode("utf-8")
    sock.sendall(struct.pack("<II", op, len(raw)) + raw)


def build_activity(args) -> dict:
    now_sec = int(time.time()) - 79  # 1:19 elapsed like the report
    activity = {
        "name": args.name,
        "type": args.type,
        "details": args.details or None,
        "state": args.state or None,
        "timestamps": {"start": now_sec},
        "assets": {},
    }
    if args.large:
        activity["assets"]["large_image"] = args.large
        activity["assets"]["large_text"] = "Large tooltip"
    if args.small:
        activity["assets"]["small_image"] = args.small
        activity["assets"]["small_text"] = "Small tooltip"
    if not activity["assets"]:
        activity.pop("assets")
    if not activity["details"]:
        activity.pop("details", None)
    if not activity["state"]:
        activity.pop("state", None)
    return activity


def main() -> int:
    ap = argparse.ArgumentParser(description="Emit a fake Discord RPC activity to QxChat.")
    ap.add_argument("--socket", default=None, help="IPC socket path (default: auto)")
    ap.add_argument("--client-id", default="1263505205522337886", help="Fake Discord application id")
    ap.add_argument("--name", default="Zed", help="Activity name")
    ap.add_argument("--type", type=int, default=0, help="0=game/app, 2=listening->media")
    ap.add_argument("--details", default="Editing activity.rs", help="Second line")
    ap.add_argument("--state", default="Workspace: lqxp-client", help="Third line")
    ap.add_argument("--large", default=DEFAULT_LARGE, help="Large artwork URL (empty to omit)")
    ap.add_argument("--small", default=DEFAULT_SMALL, help="Small artwork URL (empty to omit)")
    ap.add_argument("--hold", type=int, default=120, help="Seconds to hold the activity")
    ap.add_argument("--clear", action="store_true", help="Send a clear (activity:null) then exit")
    ap.add_argument("--dry-run", action="store_true", help="Print frames, do not connect")
    ns = ap.parse_args()

    pid = os.getpid()
    nonce = f"{int(time.time()*1000)}"
    activity = None if ns.clear else build_activity(ns)
    cmd = {
        "cmd": "SET_ACTIVITY",
        "args": {"pid": pid, "activity": activity},
        "nonce": nonce,
    }
    handshake = json.dumps({"v": 1, "client_id": ns.client_id})

    if ns.dry_run:
        print("socket:", ns.socket or find_socket())
        print("handshake(op=0):", handshake)
        print("frame(op=1):", json.dumps(cmd, indent=2))
        return 0

    path = ns.socket or find_socket()
    print(f"[rpc-emit] connecting to {path} (pid={pid}, app={ns.client_id})")
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.connect(path)
    except OSError as e:
        print(f"[rpc-emit] cannot connect: {e}", file=sys.stderr)
        print("[rpc-emit] is the QxChat desktop client running? (it owns discord-ipc-0)", file=sys.stderr)
        return 1

    send_frame(sock, OP_HANDSHAKE, handshake)
    op, resp = recv_frame(sock)
    print(f"[rpc-emit] handshake ack op={op} resp={resp[:200] if resp else None}")

    payload = json.dumps(cmd)
    send_frame(sock, OP_FRAME, payload)
    op, resp = recv_frame(sock)
    print(f"[rpc-emit] set_activity echo op={op} resp={(resp or '')[:200]}")

    if ns.clear:
        print("[rpc-emit] cleared.")
        sock.close()
        return 0

    print(f"[rpc-emit] holding '{ns.name}' for {ns.hold}s — check the QxChat profile card, Ctrl-C to clear+quit.")
    try:
        time.sleep(ns.hold)
    except KeyboardInterrupt:
        pass
    finally:
        clear = json.dumps({"cmd": "SET_ACTIVITY", "args": {"pid": pid, "activity": None}, "nonce": nonce})
        try:
            send_frame(sock, OP_FRAME, clear)
            print("[rpc-emit] clear sent.")
        except OSError:
            pass
        sock.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
