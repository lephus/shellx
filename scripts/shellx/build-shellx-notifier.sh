#!/usr/bin/env bash
# Build ShellX Notifier.app, the helper that posts automation banners.
#
# Usage:
#   scripts/shellx/build-shellx-notifier.sh --output <path/ShellX Notifier.app> \
#     --bundle-id <id> [--archs "arm64 x86_64"] [--icon <AppIcon.icns>]
#
# Compiles workers/shellx-notifier/main.swift once per architecture with
# `xcrun --sdk macosx swiftc`, joins the slices with lipo, assembles the bundle
# from workers/shellx-notifier/Info.plist and signs it ad hoc. Release signing
# (scripts/sign-cmux-bundle.sh) replaces the ad hoc signature with Developer ID.
# Without --icon the helper ships without an icon.

set -euo pipefail

REPO_ROOT="${SRCROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SOURCE_DIR="$REPO_ROOT/workers/shellx-notifier"
EXECUTABLE="shellx-notifier"
MIN_MACOS="14.0"

output=""
bundle_id=""
archs=""
icon=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) output="${2:-}"; shift 2 ;;
    --bundle-id) bundle_id="${2:-}"; shift 2 ;;
    --archs) archs="${2:-}"; shift 2 ;;
    --icon) icon="${2:-}"; shift 2 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [[ -z "$output" || -z "$bundle_id" ]]; then
  echo "usage: $0 --output <app> --bundle-id <id> [--archs <archs>] [--icon <icns>]" >&2
  exit 2
fi
if [[ "$output" != *.app ]]; then
  echo "error: --output must end in .app: $output" >&2
  exit 2
fi
[[ -n "$archs" ]] || archs="$(uname -m)"

work="$(mktemp -d "${TMPDIR:-/tmp}/shellx-notifier.XXXXXX")"
trap 'rm -rf "$work"' EXIT

slices=()
for arch in $archs; do
  xcrun --sdk macosx swiftc \
    -swift-version 6 \
    -O \
    -target "${arch}-apple-macos${MIN_MACOS}" \
    "$SOURCE_DIR/main.swift" \
    -o "$work/$EXECUTABLE-$arch"
  slices+=("$work/$EXECUTABLE-$arch")
done

app="$work/ShellX Notifier.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ ${#slices[@]} -eq 1 ]]; then
  cp "${slices[0]}" "$app/Contents/MacOS/$EXECUTABLE"
else
  /usr/bin/lipo -create "${slices[@]}" -output "$app/Contents/MacOS/$EXECUTABLE"
fi
chmod 0755 "$app/Contents/MacOS/$EXECUTABLE"

cp "$SOURCE_DIR/Info.plist" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXECUTABLE" "$app/Contents/Info.plist"
if [[ -n "$icon" && -f "$icon" ]]; then
  cp "$icon" "$app/Contents/Resources/AppIcon.icns"
else
  /usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$app/Contents/Info.plist"
fi
/usr/bin/plutil -lint "$app/Contents/Info.plist" >/dev/null

# A stable bundle-id requirement, as for the other nested helper, so the ad hoc
# identity is not CDHash-only.
/usr/bin/codesign \
  --force \
  --sign - \
  --timestamp=none \
  --identifier "$bundle_id" \
  --requirements "=designated => identifier \"${bundle_id}\"" \
  "$app"
/usr/bin/codesign --verify --deep --strict "$app"

mkdir -p "$(dirname "$output")"
rm -rf "$output"
mv "$app" "$output"
echo "ShellX Notifier.app built at: $output (id $bundle_id)"
