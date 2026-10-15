#!/usr/bin/env bash
# Notarizes a signed .app or .dmg with notarytool, then staples it. Signs in with the App Store
# Connect API key when APPLE_API_KEY_PATH is set, otherwise with the Apple ID, an app-specific
# password and the team ID.
# Usage: notarize.sh <ShellX.app | ShellX-<version>.dmg>
set -euo pipefail

target="${1:?usage: notarize.sh <App.app|file.dmg>}"
if [[ -n "${APPLE_API_KEY_PATH:-}" ]]; then
  : "${APPLE_API_KEY_ID:?missing secret APPLE_API_KEY_ID}"
  : "${APPLE_API_ISSUER_ID:?missing secret APPLE_API_ISSUER_ID}"
  auth=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID")
else
  : "${APPLE_ID:?set APPLE_ID (the Apple account) or APPLE_API_KEY_PATH}"
  : "${APPLE_TEAM_ID:?set APPLE_TEAM_ID}"
  if [[ -z "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    echo "::error::missing secret APPLE_APP_SPECIFIC_PASSWORD (an app-specific password of $APPLE_ID, see release/README.md), or an App Store Connect API key"
    exit 1
  fi
  auth=(--apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID")
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

submission="$target"
if [[ "$target" == *.app ]]; then
  submission="$work/$(basename "$target" .app).zip"
  ditto -c -k --keepParent "$target" "$submission"
fi

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
