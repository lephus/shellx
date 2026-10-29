#!/usr/bin/env bash
# Package a signed, notarized ShellX.app into ShellX-<version>.dmg, then sign, notarize and staple
# the dmg itself, so the first open from a browser download shows only the standard prompt.
#
# Usage: scripts/shellx/release/make-dmg.sh <ShellX.app> <version> <out-dir>
#   Prints the dmg path. The app must already be through scripts/shellx/sign-and-notarize.sh.
#
# Optional env: SHELLX_SIGNING_IDENTITY, SHELLX_NOTARY_PROFILE (same defaults as sign-and-notarize.sh).

set -euo pipefail

IDENTITY="${SHELLX_SIGNING_IDENTITY:-Developer ID Application: Phu Le huu (W4RF3W4VTZ)}"
NOTARY_PROFILE="${SHELLX_NOTARY_PROFILE:-shellx-notary}"

[[ $# -eq 3 ]] || { echo "usage: $0 <ShellX.app> <version> <out-dir>" >&2; exit 2; }
app="$1" version="$2" out_dir="$3"
[[ -d "$app" ]] || { echo "error: app bundle not found at $app" >&2; exit 1; }
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: version '$version' is not X.Y.Z" >&2; exit 1; }
bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$bundle_version" == "$version" ]] || { echo "error: $app is version $bundle_version, not $version" >&2; exit 1; }
xcrun stapler validate "$app" >&2

mkdir -p "$out_dir"
dmg="$(cd "$out_dir" && pwd)/ShellX-$version.dmg"
[[ ! -e "$dmg" ]] || { echo "error: $dmg already exists" >&2; exit 1; }

stage="$(mktemp -d "${TMPDIR:-/tmp}/shellx-dmg.XXXXXX")"
trap "rm -rf '$stage'" EXIT
/usr/bin/ditto "$app" "$stage/ShellX.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "ShellX $version" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg" >&2

echo "==> signing $dmg" >&2
/usr/bin/codesign --force --timestamp --sign "$IDENTITY" "$dmg" >&2

echo "==> submitting $dmg to the Apple notary service (profile $NOTARY_PROFILE)" >&2
result="$(xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
echo "$result" >&2
status="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("status", ""))' <<<"$result")"
if [[ "$status" != "Accepted" ]]; then
  id="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))' <<<"$result")"
  echo "error: notarization finished with status '$status' (submission $id)" >&2
  [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
  exit 1
fi

xcrun stapler staple "$dmg" >&2
xcrun stapler validate "$dmg" >&2
spctl -a -vv -t open --context context:primary-signature "$dmg" 2>&1 | tee "$stage/spctl.txt" >&2
grep -q 'source=Notarized Developer ID' "$stage/spctl.txt" || {
  echo "error: Gatekeeper did not report source=Notarized Developer ID for $dmg" >&2
  exit 1
}
echo "$dmg"
