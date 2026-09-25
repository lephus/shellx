#!/usr/bin/env bash
# Signs a Flutter macOS app bundle inside-out with hardened runtime and a secure timestamp.
# Usage: MACOS_SIGNING_IDENTITY=<sha1 or "-"> sign-app.sh <ShellX.app> <entitlements.plist>
set -euo pipefail

app="${1:?usage: sign-app.sh <ShellX.app> <entitlements.plist>}"
entitlements="${2:?usage: sign-app.sh <ShellX.app> <entitlements.plist>}"
: "${MACOS_SIGNING_IDENTITY:?set by import-certificate.sh (use - for an ad-hoc test signature)}"

# Spec §8.5: distributed outside the Mac App Store with App Sandbox OFF (the sandbox forbids
# spawning the user's shell). Refuse to ship a bundle whose entitlements turn it on.
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements" 2>/dev/null || true)" == "true" ]]; then
  echo "::error::$entitlements enables com.apple.security.app-sandbox; the agent must not be sandboxed"
  exit 1
fi

sign() {
  codesign --force --timestamp --options runtime --sign "$MACOS_SIGNING_IDENTITY" "$@"
}

# 1. Loose dylibs anywhere in the bundle.
while IFS= read -r -d '' item; do
  sign "$item"
done < <(find "$app/Contents" -type f -name '*.dylib' -print0)

# 2. Nested bundles, deepest first (frameworks, helper apps, XPC services).
while IFS= read -r -d '' item; do
  sign "$item"
done < <(find "$app/Contents" -depth -type d \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' \) -print0)

# 3. The app itself, with its entitlements.
sign --entitlements "$entitlements" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
