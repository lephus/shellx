#!/usr/bin/env bash
# Refuses an app or dmg that is not signed by the expected Apple team.
# Usage: check-team.sh <ShellX.app | ShellX-<version>.dmg> <team id>
set -euo pipefail

target="${1:?usage: check-team.sh <App.app|file.dmg> <team id>}"
expected="${2:?usage: check-team.sh <App.app|file.dmg> <team id>}"

# `|| true`: codesign exits 1 on unsigned code; the check below still says why.
team="$( { codesign -dv --verbose=2 "$target" 2>&1 || true; } | awk -F= '$1 == "TeamIdentifier" { print $2 }')"
if [[ "$team" != "$expected" ]]; then
  echo "::error::$target is signed by team '${team:-none}', expected $expected"
  exit 1
fi
echo "$target is signed by team $team"
