#!/usr/bin/env bash
# Imports the Developer ID Application certificate (.p12, base64) into a temporary keychain.
# Exports MACOS_SIGNING_IDENTITY (SHA-1 of the identity) and MACOS_KEYCHAIN via $GITHUB_ENV.
# Only an identity of team APPLE_TEAM_ID is accepted.
set -euo pipefail

if [[ -z "${MACOS_CERTIFICATE_P12_BASE64:-}" || -z "${MACOS_CERTIFICATE_PASSWORD:-}" ]]; then
  echo "::error::missing secret MACOS_CERTIFICATE_P12_BASE64 or MACOS_CERTIFICATE_PASSWORD in the GitHub Environment 'release' (see release/README.md); a real release is never published unsigned for macOS"
  exit 1
fi
: "${APPLE_TEAM_ID:?set APPLE_TEAM_ID}"
: "${RUNNER_TEMP:?RUNNER_TEMP must be set}"
: "${GITHUB_ENV:?GITHUB_ENV must be set}"

keychain="$RUNNER_TEMP/shellx-signing.keychain-db"
keychain_password="$(openssl rand -base64 24)"
certificate="$RUNNER_TEMP/developer-id.p12"

printf '%s' "$MACOS_CERTIFICATE_P12_BASE64" | base64 --decode > "$certificate"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$certificate" -P "$MACOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$keychain"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" > /dev/null
security list-keychain -d user -s "$keychain"
rm -f "$certificate"

identity="$(security find-identity -v -p codesigning "$keychain" |
  awk -v team="($APPLE_TEAM_ID)\"" '/"Developer ID Application: / && index($0, team) { print $2; exit }')"
if [[ -z "$identity" ]]; then
  echo "::error::The certificate in MACOS_CERTIFICATE_P12_BASE64 has no 'Developer ID Application' identity of team $APPLE_TEAM_ID"
  security find-identity -v -p codesigning "$keychain" | sed -E 's/[0-9A-F]{40}/<sha1>/' || true
  exit 1
fi
echo "Imported Developer ID Application identity $identity"
{
  echo "MACOS_SIGNING_IDENTITY=$identity"
  echo "MACOS_KEYCHAIN=$keychain"
} >> "$GITHUB_ENV"
