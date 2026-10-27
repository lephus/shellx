#!/usr/bin/env bash
# Builds the App Store ipa of the ShellX iOS app (shellx-ios/), checks it, and with --upload sends
# it to App Store Connect (TestFlight). Runs on a Mac whose Xcode is signed in to team W4RF3W4VTZ
# (Xcode > Settings > Accounts); no secret is needed. See release/mobile/README.md.
#
#   release/mobile/ios.sh
#       Release archive for a generic iPhone with automatic signing, then an App Store export.
#       Writes build/release/ios/ShellX-<version>-<build>.ipa next to its .xcarchive, and checks it.
#   release/mobile/ios.sh --upload
#       The same, then exports that archive again with destination=upload, which sends it to App
#       Store Connect. Run it only when the maintainer says so.
#   release/mobile/ios.sh --check-app <path.app>
#       Only the checks, on an app bundle that is already built.
#
# The version and build number come from shellx-ios/Config/Version.xcconfig. Together with
# shellx-ios/scripts/dev.sh, this is the only place that runs xcodebuild for shellx-ios/.
set -euo pipefail

TEAM_ID=W4RF3W4VTZ
BUNDLE_ID=com.shellx.prod
# Names that exist only in Debug builds: the demo, its fake Mac and account, the test fakes.
DEBUG_ONLY_NAMES='FakeMac|FakeRelayAccount|DemoComposition|DemoScript|InMemorySecretStore|SHELLX_DEMO|ShellXAppTestSupport'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
IOS_DIR="$REPO_ROOT/shellx-ios"
PROJECT="$IOS_DIR/ShellX.xcodeproj"
SCHEME="ShellX"
DERIVED="$IOS_DIR/.derived"
VERSION_FILE="$IOS_DIR/Config/Version.xcconfig"
EXPORT_OPTIONS="$REPO_ROOT/release/mobile/ExportOptions.plist"
OUT_DIR="$REPO_ROOT/build/release/ios"

die() { echo "ios.sh: $*" >&2; exit 1; }
note() { echo "==> $*" >&2; }

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"
  exit "${1:-0}"
}

WORK=""
cleanup() { if [ -n "$WORK" ]; then rm -rf "$WORK"; fi; }
trap cleanup EXIT
work_dir() {
  if [ -z "$WORK" ]; then WORK="$(mktemp -d)"; fi
}

# Prints the value of $1 in Version.xcconfig.
xcconfig_value() {
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([^[:space:]]*\).*/\1/p" "$VERSION_FILE" | tail -n 1
}

VERSION=""
BUILD=""
read_version() {
  [ -f "$VERSION_FILE" ] || die "missing $VERSION_FILE"
  VERSION="$(xcconfig_value MARKETING_VERSION)"
  BUILD="$(xcconfig_value CURRENT_PROJECT_VERSION)"
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    die "MARKETING_VERSION '$VERSION' in shellx-ios/Config/Version.xcconfig is not X.Y.Z"
  [[ "$BUILD" =~ ^[1-9][0-9]*$ ]] ||
    die "CURRENT_PROJECT_VERSION '$BUILD' in shellx-ios/Config/Version.xcconfig is not a positive integer"
}

# Prints key $1 of plist $2, or nothing (status 1) when the key is missing.
plist_value() { /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null; }

# Checks that app bundle $1 is what App Store Connect expects for this release; $2 names the ipa it
# came from, for the messages. Prints the problems and returns 1 when there is any.
check_app() {
  local app="${1%/}" label="${2:-$1}"
  [ -d "$app" ] && [ -f "$app/Info.plist" ] || die "$app is not an app bundle"
  work_dir
  local info="$app/Info.plist" entitlements="$WORK/entitlements.plist" team bundle_id version build
  local value fail=()

  team="$( { codesign -dv --verbose=2 "$app" 2>&1 || true; } | awk -F= '$1 == "TeamIdentifier" { print $2 }')"
  if [ "$team" = "not set" ]; then team=""; fi
  if ! codesign -d --entitlements - --xml "$app" >"$entitlements" 2>/dev/null; then : >"$entitlements"; fi
  bundle_id="$(plist_value CFBundleIdentifier "$info" || true)"
  version="$(plist_value CFBundleShortVersionString "$info" || true)"
  build="$(plist_value CFBundleVersion "$info" || true)"

  [ "$team" = "$TEAM_ID" ] || fail+=("signed by team '${team:-none}', expected $TEAM_ID")
  [ "$bundle_id" = "$BUNDLE_ID" ] || fail+=("bundle id is not $BUNDLE_ID (it is '$bundle_id')")
  [ "$version" = "$VERSION" ] ||
    fail+=("CFBundleShortVersionString is '$version', Version.xcconfig says $VERSION")
  [ "$build" = "$BUILD" ] || fail+=("CFBundleVersion is '$build', Version.xcconfig says $BUILD")
  if [ "$(plist_value get-task-allow "$entitlements" || true)" = "true" ]; then
    fail+=("get-task-allow is true (a development signature)")
  fi
  # Push is optional until P4; when the entitlement is there it must point at production APNs.
  if value="$(plist_value aps-environment "$entitlements")" && [ "$value" != "production" ]; then
    fail+=("aps-environment is '$value', expected production")
  fi
  # P3 embeds no framework: everything is linked statically into the executable.
  if [ -d "$app/Frameworks" ]; then
    local framework
    while IFS= read -r framework; do
      if [ -n "$framework" ]; then fail+=("embeds Frameworks/$(basename "$framework"), expected no framework"); fi
    done <<<"$(find "$app/Frameworks" -maxdepth 1 -name '*.framework' | sort)"
  fi
  # The Debug demo and the test fakes stay out of the App Store build (Release.xcconfig leaves
  # ShellXAppTestSupport out of the link; the rest is under #if DEBUG). Swift keeps type names in a
  # stripped executable, so they show up in its strings.
  local executable debug_names
  executable="$app/$(plist_value CFBundleExecutable "$info" || true)"
  if [ -f "$executable" ]; then
    debug_names="$(strings -a "$executable" | grep -oE "$DEBUG_ONLY_NAMES" | sort -u | tr '\n' ' ' || true)"
    if [ -n "$debug_names" ]; then fail+=("contains Debug-only code: ${debug_names% }"); fi
  fi

  if [ ${#fail[@]} -gt 0 ]; then
    local problem
    for problem in "${fail[@]}"; do echo "ios.sh: $label: $problem" >&2; done
    return 1
  fi
  note "$label: team $team, $bundle_id $version ($build)"
}

# Runs xcodebuild with the arguments that follow $1 (a log name). The full log goes to
# build/release/ios/logs/; the terminal gets errors, warnings and the result line.
run_xcodebuild() {
  local name="$1"
  shift
  mkdir -p "$OUT_DIR/logs"
  local log="$OUT_DIR/logs/$name-$(date +%Y%m%d-%H%M%S).log" status=0
  xcodebuild "$@" >"$log" 2>&1 || status=1
  grep -E "error:|warning:|\*\* [A-Z ]+ (SUCCEEDED|FAILED) \*\*" "$log" |
    grep -v "Metadata extraction skipped" || true
  if [ "$status" -ne 0 ]; then
    note "full xcodebuild log: $log"
    return 1
  fi
}

cmd_check_app() {
  [ $# -eq 1 ] || usage 2
  read_version
  check_app "$1"
}

cmd_release() {
  local upload="$1"
  read_version
  [ -f "$EXPORT_OPTIONS" ] || die "missing $EXPORT_OPTIONS"
  local name="ShellX-$VERSION-$BUILD"
  local archive="$OUT_DIR/$name.xcarchive" ipa="$OUT_DIR/$name.ipa"
  mkdir -p "$OUT_DIR"
  rm -rf "$archive" "$ipa"
  work_dir

  note "ShellX iOS $VERSION ($BUILD): Release archive (automatic signing, team $TEAM_ID)"
  run_xcodebuild "archive-$name" archive \
    -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED" \
    -archivePath "$archive" \
    -allowProvisioningUpdates ||
    die "archive failed; if signing failed, check Xcode > Settings > Accounts (team $TEAM_ID)"

  note "App Store export"
  run_xcodebuild "export-$name" -exportArchive \
    -archivePath "$archive" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$WORK/export" \
    -allowProvisioningUpdates ||
    die "export failed; if signing failed, check Xcode > Settings > Accounts (team $TEAM_ID)"
  [ -f "$WORK/export/$SCHEME.ipa" ] || die "the export produced no $SCHEME.ipa"
  mv "$WORK/export/$SCHEME.ipa" "$ipa"

  mkdir -p "$WORK/ipa"
  unzip -q "$ipa" -d "$WORK/ipa"
  local app
  app="$(find "$WORK/ipa/Payload" -maxdepth 1 -name '*.app' | head -n 1)"
  [ -n "$app" ] || die "$ipa has no Payload/*.app"
  if ! check_app "$app" "$ipa"; then
    rm -f "$ipa"
    die "refused the ipa (removed); the archive is kept at $archive"
  fi

  if [ "$upload" -eq 0 ]; then
    echo "Not uploaded. Upload this build with: release/mobile/ios.sh --upload"
    return 0
  fi

  # The same archive and signing with destination=upload: Xcode's account session uploads it.
  note "uploading ShellX $VERSION ($BUILD) to App Store Connect"
  cp "$EXPORT_OPTIONS" "$WORK/upload.plist"
  /usr/libexec/PlistBuddy -c "Set :destination upload" "$WORK/upload.plist"
  run_xcodebuild "upload-$name" -exportArchive \
    -archivePath "$archive" \
    -exportOptionsPlist "$WORK/upload.plist" \
    -exportPath "$WORK/upload" \
    -allowProvisioningUpdates ||
    die "upload failed"
  note "uploaded ShellX $VERSION ($BUILD). App Store Connect > ShellX > TestFlight lists it after processing (about 5-30 minutes)."
}

case "${1:-}" in
  "") cmd_release 0 ;;
  --upload) [ $# -eq 1 ] || usage 2; cmd_release 1 ;;
  --check-app) shift; cmd_check_app "$@" ;;
  -h|--help|help) usage 0 ;;
  *) echo "ios.sh: unknown option $1" >&2; usage 2 ;;
esac
