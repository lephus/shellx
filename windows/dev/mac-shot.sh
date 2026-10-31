#!/bin/bash
# Development only: start the release build of the window on a Mac, wait, save
# a PNG of its window, and stop it. The Windows app is built and tested on
# Windows; this exists so the UI can be checked with screenshots from a Mac.
#
#   cargo build --release -p shellx-app   (from windows/; never a debug build)
#   dev/mac-shot.sh out.png [wait_seconds=6]
#
# The caller's environment is passed through (for example SHELLX_LANG=en).
set -euo pipefail

out="${1:-}"
wait_seconds="${2:-6}"
if [ -z "$out" ]; then
  echo "usage: $0 <out.png> [wait_seconds=6]" >&2
  exit 64
fi

here="$(cd "$(dirname "$0")" && pwd)"
bin="$here/../target/release/shellx-desktop"
if [ ! -x "$bin" ]; then
  echo "mac-shot: $bin not found; run 'cargo build --release -p shellx-app' in windows/" >&2
  exit 1
fi

log="$(mktemp -t shellx-mac-shot)"
"$bin" >"$log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; rm -f "$log"' EXIT

sleep "$wait_seconds"

if ! kill -0 "$pid" 2>/dev/null; then
  echo "mac-shot: shellx-desktop exited before the screenshot:" >&2
  cat "$log" >&2
  exit 1
fi

# Window number of the process we started (owner name is the binary name).
id="$(swift -e '
import CoreGraphics
let pid = Int(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as! [[String: Any]]
for w in list where (w["kCGWindowOwnerPID"] as? Int ?? 0) == pid {
  if (w["kCGWindowLayer"] as? Int ?? 0) == 0 { print(w["kCGWindowNumber"]!); break }
}
' "$pid" 2>/dev/null || true)"

if [ -z "$id" ]; then
  echo "mac-shot: no shellx-desktop window appeared after ${wait_seconds}s" >&2
  cat "$log" >&2
  exit 1
fi

screencapture -x -o -l"$id" "$out"
echo "mac-shot: wrote $out (window $id)"
