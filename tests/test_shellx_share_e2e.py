#!/usr/bin/env python3
"""Share links end to end on loopback (L7 Task B9).

Runs scripts/shellx/share-e2e.mjs: the real cmux-relay (Origin allowlist
https://shellx.pro), the Node API from relay/src, the Swift `ShareHost` through
the test-only `share-e2e-host` executable, and the web viewer's session module
driven from Node. Checks welcome -> replay, typed `echo hi\\r` on a type share,
input dropped on a view share, revoke -> `revoked` within 1 s, expiry ->
`expired`, the one-time QR share, and the relay/API origin rules.

Needs macOS with Swift 6, `cargo` (cmux-relay is built when missing), Node 22+
and `npm ci` in relay/. Takes about 15 s after the first build.
"""
from __future__ import annotations

import os
import shutil
import signal
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/shellx/share-e2e.mjs"
TIMEOUT_S = 900


def stop_group(proc: subprocess.Popen[bytes]) -> None:
    """SIGTERM node's process group (its handlers clean up), then SIGKILL whatever is left."""
    for sig, grace in ((signal.SIGTERM, 10), (signal.SIGKILL, 5)):
        try:
            os.killpg(proc.pid, sig)
        except ProcessLookupError:
            return
        try:
            proc.wait(timeout=grace)
            return
        except subprocess.TimeoutExpired:
            continue


def main() -> int:
    node = os.environ.get("NODE") or shutil.which("node") or "/opt/homebrew/bin/node"
    if not (ROOT / "relay/node_modules/tsx").is_dir():
        print("FAIL: run `npm ci` in relay/ first (tsx, ws)", file=sys.stderr)
        return 1
    # Own process group, so a timeout or Ctrl-C reaches node and the relay/host it spawned.
    proc = subprocess.Popen([node, str(SCRIPT)], cwd=ROOT, start_new_session=True)
    try:
        returncode = proc.wait(timeout=TIMEOUT_S)
    except subprocess.TimeoutExpired:
        print(f"FAIL: share-e2e.mjs timed out after {TIMEOUT_S} s", file=sys.stderr)
        stop_group(proc)
        return 1
    except KeyboardInterrupt:
        stop_group(proc)
        raise
    if returncode != 0:
        print("FAIL: share-e2e.mjs failed", file=sys.stderr)
        return 1
    print("PASS: share links end to end")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
