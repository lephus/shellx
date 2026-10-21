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
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/shellx/share-e2e.mjs"


def main() -> int:
    node = os.environ.get("NODE") or shutil.which("node") or "/opt/homebrew/bin/node"
    if not (ROOT / "relay/node_modules/tsx").is_dir():
        print("FAIL: run `npm ci` in relay/ first (tsx, ws)", file=sys.stderr)
        return 1
    result = subprocess.run([node, str(SCRIPT)], cwd=ROOT, timeout=900)
    if result.returncode != 0:
        print("FAIL: share-e2e.mjs failed", file=sys.stderr)
        return 1
    print("PASS: share links end to end")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
