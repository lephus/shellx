#!/usr/bin/env bash
# Notarizes a signed .app or .dmg with notarytool (App Store Connect API key), then staples it.
# Usage: notarize.sh <ShellX.app | ShellX-<version>.dmg>
set -euo pipefail

target="${1:?usage: notarize.sh <App.app|file.dmg>}"
: "${APPLE_API_KEY_PATH:?path to the decoded AuthKey_<id>.p8}"
: "${APPLE_API_KEY_ID:?missing secret APPLE_API_KEY_ID}"
: "${APPLE_API_ISSUER_ID:?missing secret APPLE_API_ISSUER_ID}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

submission="$target"
if [[ "$target" == *.app ]]; then
  submission="$work/$(basename "$target" .app).zip"
  ditto -c -k --keepParent "$target" "$submission"
fi

auth=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID")
xcrun notarytool submit "$submission" "${auth[@]}" --wait --timeout 30m --output-format json > "$work/result.json" || true
status="$(plutil -extract status raw "$work/result.json" 2>/dev/null || echo unknown)"
if [[ "$status" != "Accepted" ]]; then
  echo "::error::Notarization of $target finished with status '$status'"
  cat "$work/result.json" || true
  if id="$(plutil -extract id raw "$work/result.json" 2>/dev/null)"; then
    xcrun notarytool log "$id" "${auth[@]}" || true
  fi
  exit 1
fi

xcrun stapler staple "$target"
xcrun stapler validate "$target"
if [[ "$target" == *.app ]]; then
  spctl --assess --type execute --verbose=2 "$target"
else
  spctl --assess --type open --context context:primary-signature --verbose=2 "$target"
fi
