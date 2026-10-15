#!/usr/bin/env bash
# Builds the App Store ipa of apps/mobile, checks its signature, and with --upload sends it to App
# Store Connect (TestFlight). Runs on a Mac whose Xcode is signed in to team W4RF3W4VTZ (Xcode →
# Settings → Accounts); no secret is needed. See release/mobile/README.md.
# Usage: release/mobile/ios.sh [--upload]
set -euo pipefail

TEAM_ID=W4RF3W4VTZ
BUNDLE_ID=com.shellx.prod
# App Store Connect → ShellX → App Information → Apple ID. The "Open the App Store" button of the
# update-required screen opens this listing; empty, it opens https://shellx.pro/ instead.
APP_STORE_ID=

usage='usage: release/mobile/ios.sh [--upload]'
upload=false
case "${1:-}" in
  --upload) upload=true ;;
  '') ;;
  *) echo "$usage" >&2; exit 2 ;;
esac

repo="$(cd "$(dirname "$0")/../.." && pwd)"
app="$repo/apps/mobile"
version="$(sed -n 's/^version:[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$app/pubspec.yaml")"
name="${version%%+*}"
build="${version#*+}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
  echo "error: apps/mobile/pubspec.yaml version '$version' is not X.Y.Z+N" >&2
  exit 1
fi

defines=()
if [[ -n "$APP_STORE_ID" ]]; then
  defines+=("--dart-define=SHELLX_APP_STORE_URL=https://apps.apple.com/app/id$APP_STORE_ID")
else
  echo "warning: APP_STORE_ID is empty in release/mobile/ios.sh, so \"Open the App Store\" opens https://shellx.pro/" >&2
fi

echo "==> ShellX iOS $name ($build)"
cd "$app"
rm -rf build/ios/ipa build/ios/archive
flutter build ipa --release --export-options-plist="$repo/release/mobile/ExportOptions.plist" ${defines[@]+"${defines[@]}"}

ipa="$(ls build/ios/ipa/*.ipa)"
archive="build/ios/archive/Runner.xcarchive"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The ipa must be what App Store Connect expects: this team, this bundle id, the pubspec version,
# and a distribution signature (push in production, no debugger).
unzip -q "$ipa" -d "$work/ipa"
bundle="$(ls -d "$work"/ipa/Payload/*.app)"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null || true; }
codesign -d --entitlements - --xml "$bundle" > "$work/entitlements.plist" 2>/dev/null
team="$( { codesign -dv --verbose=2 "$bundle" 2>&1 || true; } | awk -F= '$1 == "TeamIdentifier" { print $2 }')"
fail=()
[[ "$team" == "$TEAM_ID" ]] || fail+=("signed by team '${team:-none}', expected $TEAM_ID")
[[ "$(plist CFBundleIdentifier "$bundle/Info.plist")" == "$BUNDLE_ID" ]] || fail+=("bundle id is not $BUNDLE_ID")
[[ "$(plist CFBundleShortVersionString "$bundle/Info.plist")" == "$name" ]] || fail+=("CFBundleShortVersionString is not $name")
[[ "$(plist CFBundleVersion "$bundle/Info.plist")" == "$build" ]] || fail+=("CFBundleVersion is not $build")
[[ "$(plist aps-environment "$work/entitlements.plist")" == production ]] || fail+=("aps-environment is not production")
[[ "$(plist get-task-allow "$work/entitlements.plist")" != true ]] || fail+=("get-task-allow is true (development signature)")
if ((${#fail[@]})); then
  printf 'error: %s: %s\n' "$ipa" "${fail[@]}" >&2
  exit 1
fi
echo "==> $ipa: team $team, $BUNDLE_ID $name ($build), aps-environment production"

if ! $upload; then
  echo "Not uploaded. Upload this build with: release/mobile/ios.sh --upload"
  exit 0
fi

# Same archive, same signing, destination=upload: Xcode's account session uploads it.
cp "$repo/release/mobile/ExportOptions.plist" "$work/upload.plist"
/usr/libexec/PlistBuddy -c "Set :destination upload" "$work/upload.plist"
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$work/upload.plist" \
  -exportPath "$work/upload" -allowProvisioningUpdates
echo "==> Uploaded ShellX $name ($build). App Store Connect → ShellX → TestFlight shows it after processing (about 5–30 minutes)."
