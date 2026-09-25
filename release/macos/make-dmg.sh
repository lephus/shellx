#!/usr/bin/env bash
# Builds a compressed, read-only DMG with ShellX.app and an /Applications shortcut.
# Usage: make-dmg.sh <path/to/ShellX.app> <out/ShellX-<version>.dmg>
set -euo pipefail

app="${1:?usage: make-dmg.sh <App.app> <out.dmg>}"
out="${2:?usage: make-dmg.sh <App.app> <out.dmg>}"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

ditto "$app" "$staging/ShellX.app"
ln -s /Applications "$staging/Applications"
mkdir -p "$(dirname "$out")"
rm -f "$out"
hdiutil create -volname ShellX -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$out"
hdiutil verify "$out"
