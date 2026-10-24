#!/usr/bin/env bash
# Regression test: reload.sh passes PRODUCT_BUNDLE_IDENTIFIER to xcodebuild, which
# stamps the app's identifier onto every SwiftPM resource bundle too. Asset
# catalogs are looked up by bundle identifier, so in a tagged build SwiftUI looked
# for ShellXIcons' coolicons in the app's own catalog ("No image named 'Settings'
# found in asset catalog") and the title bar's settings and search icons drew blank.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELOAD="$ROOT_DIR/scripts/reload.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Run the real function, not a copy of it.
functions="$(awk '
  /^give_resource_bundles_own_identifiers\(\) \{$/ { on = 1 }
  on { print }
  on && /^\}$/ { on = 0 }
' "$RELOAD")"
[[ "$functions" == *"give_resource_bundles_own_identifiers()"* ]] \
  || fail "could not find give_resource_bundles_own_identifiers in reload.sh"
eval "$functions"
grep -q '^give_resource_bundles_own_identifiers "\$APP_PATH" "\$BUNDLE_ID"$' "$RELOAD" \
  || fail "reload.sh never calls give_resource_bundles_own_identifiers on the built app"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

APP_ID="pro.shellx.desktop.debug.probe"
APP="$TMP_DIR/ShellX DEV probe.app"
plist_id() { /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist"; }
seed_bundle() {
  mkdir -p "$1/Contents"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $2" "$1/Contents/Info.plist" >/dev/null
}

seed_bundle "$APP" "$APP_ID"
seed_bundle "$APP/Contents/Resources/ShellXBrand_ShellXIcons.bundle" "$APP_ID"
seed_bundle "$APP/Contents/Resources/Bonsplit_Bonsplit.bundle" "$APP_ID"
seed_bundle "$APP/Contents/Resources/Own_Own.bundle" "own.Own.resources"
mkdir -p "$APP/Contents/Resources/bin"
ln -s ../ShellXBrand_ShellXIcons.bundle "$APP/Contents/Resources/bin/ShellXBrand_ShellXIcons.bundle"

give_resource_bundles_own_identifiers "$APP" "$APP_ID"

icons_id="$(plist_id "$APP/Contents/Resources/ShellXBrand_ShellXIcons.bundle")"
bonsplit_id="$(plist_id "$APP/Contents/Resources/Bonsplit_Bonsplit.bundle")"
[[ "$icons_id" != "$APP_ID" && "$bonsplit_id" != "$APP_ID" ]] \
  || fail "a resource bundle still carries the app's identifier ($icons_id, $bonsplit_id)"
[[ "$icons_id" != "$bonsplit_id" ]] || fail "two resource bundles share the identifier $icons_id"
[[ "$icons_id" =~ ^[A-Za-z0-9.-]+$ ]] || fail "'$icons_id' is not a valid bundle identifier"
echo "PASS: resource bundles get identifiers of their own, distinct from the app's"

[[ "$(plist_id "$APP")" == "$APP_ID" ]] || fail "the app's own identifier changed"
[[ "$(plist_id "$APP/Contents/Resources/Own_Own.bundle")" == "own.Own.resources" ]] \
  || fail "a resource bundle that already had its own identifier was renamed"
[[ -L "$APP/Contents/Resources/bin/ShellXBrand_ShellXIcons.bundle" ]] \
  || fail "the bin/ symlink to a resource bundle was replaced"
echo "PASS: the app, already-distinct bundles and bin/ symlinks are left alone"

# Running it again (an incremental reload) changes nothing further.
give_resource_bundles_own_identifiers "$APP" "$APP_ID"
[[ "$(plist_id "$APP/Contents/Resources/ShellXBrand_ShellXIcons.bundle")" == "$icons_id" ]] \
  || fail "a second run renamed the resource bundle again"
echo "PASS: a second run is a no-op"
