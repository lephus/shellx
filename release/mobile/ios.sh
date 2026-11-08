#!/usr/bin/env bash
# Builds and checks the App Store ipa of the ShellX iOS app (shellx-ios/), and uploads a checked
# build to App Store Connect (TestFlight). Runs on a Mac whose Xcode is signed in to team
# W4RF3W4VTZ (Xcode > Settings > Accounts); no secret is needed. See release/mobile/README.md.
#
#   release/mobile/ios.sh
#       Release archive for a generic iPhone with automatic signing, then an App Store export.
#       Writes build/release/ios/ShellX-<version>-<build>.xcarchive and .ipa, and checks the ipa.
#       Refuses a build number that was already uploaded.
#   release/mobile/ios.sh --upload
#       Uploads the archive that the previous run built and checked for the current version and
#       build. Refuses when there is none, when shellx-ios/, shellx-link/ or release/mobile/ has
#       uncommitted changes or a commit made since that build, or when this build number was
#       already uploaded. Run it only when the maintainer says so.
#   release/mobile/ios.sh --check-app [--unsigned] <path.app>
#       Only the checks, on an app bundle that is already built. --unsigned skips the signature
#       checks (team, get-task-allow, aps-environment); shellx-ios/scripts/dev.sh build-release uses it.
#
# Signing runs with -allowProvisioningUpdates, so Xcode may create or renew a profile or a
# certificate without asking. ios.sh lists the team's provisioning profiles, the certificates they
# name and the keychain's signing identities before and after each signing step, and prints
# anything that changed.
#
# The version and build number come from shellx-ios/Config/Version.xcconfig. Together with
# shellx-ios/scripts/dev.sh, this is the only place that runs xcodebuild for shellx-ios/.
set -euo pipefail

TEAM_ID=W4RF3W4VTZ
BUNDLE_ID=com.shellx.prod
# Names that exist only in Debug builds: the test fakes and the Debug demo's launch switch. The in-app demo
# (ShellXDemo: FakeMac, DemoRelay, DemoComposition) ships on purpose ("Try without an account").
DEBUG_ONLY_NAMES='FakeRelayAccount|FakeIdentityProvider|InMemorySecretStore|FakeTranscriber|FakeVoicePermissions|SHELLX_DEMO|ShellXAppTestSupport'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
IOS_DIR="$REPO_ROOT/shellx-ios"
PROJECT="$IOS_DIR/ShellX.xcodeproj"
SCHEME="ShellX"
DERIVED="$IOS_DIR/.derived"
VERSION_FILE="$IOS_DIR/Config/Version.xcconfig"
EXPORT_OPTIONS="$REPO_ROOT/release/mobile/ExportOptions.plist"
OUT_DIR="$REPO_ROOT/build/release/ios"
# What the build is made from; --upload refuses when any of it changed since the build.
SOURCE_PATHS=(shellx-ios shellx-link release/mobile)
PROFILE_DIRS=(
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  "$HOME/Library/MobileDevice/Provisioning Profiles"
)

die() { echo "ios.sh: $*" >&2; exit 1; }
note() { echo "==> $*" >&2; }

usage() {
  local status="${1:-0}"
  if [ "$status" -eq 0 ]; then
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"
  else
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}" >&2
  fi
  exit "$status"
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
NAME=""
read_version() {
  [ -f "$VERSION_FILE" ] || die "missing $VERSION_FILE"
  VERSION="$(xcconfig_value MARKETING_VERSION)"
  BUILD="$(xcconfig_value CURRENT_PROJECT_VERSION)"
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    die "MARKETING_VERSION '$VERSION' in shellx-ios/Config/Version.xcconfig is not X.Y.Z"
  [[ "$BUILD" =~ ^[1-9][0-9]*$ ]] ||
    die "CURRENT_PROJECT_VERSION '$BUILD' in shellx-ios/Config/Version.xcconfig is not a positive integer"
  NAME="ShellX-$VERSION-$BUILD"
}

# Prints key $1 of plist $2, or nothing (status 1) when the key is missing.
plist_value() { /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null; }

# Checks app bundle $2 against this release. $1 is "signed", or "unsigned" to skip the signature
# checks; $3 names the ipa the app came from, for the messages. Prints every problem and returns 1
# when there is any. Callers run it inside `if`, where set -e is off, so each step checks its own
# status.
check_app() {
  local mode="$1" app="${2%/}" label="${3:-$2}"
  [ -d "$app" ] && [ -f "$app/Info.plist" ] || die "$app is not an app bundle"
  work_dir
  local info="$app/Info.plist" fail=() team="" value bundle_id version build executable

  bundle_id="$(plist_value CFBundleIdentifier "$info" || true)"
  version="$(plist_value CFBundleShortVersionString "$info" || true)"
  build="$(plist_value CFBundleVersion "$info" || true)"
  [ "$bundle_id" = "$BUNDLE_ID" ] || fail+=("bundle id is not $BUNDLE_ID (it is '$bundle_id')")
  [ "$version" = "$VERSION" ] ||
    fail+=("CFBundleShortVersionString is '$version', Version.xcconfig says $VERSION")
  [ "$build" = "$BUILD" ] || fail+=("CFBundleVersion is '$build', Version.xcconfig says $BUILD")
  # Plain HTTP to the local network serves only the Debug relay override (ShellXEndpoints); the App
  # Store build keeps App Transport Security whole.
  if [ "$(plist_value NSAppTransportSecurity:NSAllowsLocalNetworking "$info" || true)" = "true" ]; then
    fail+=("allows plain HTTP to the local network (NSAllowsLocalNetworking), which only Debug builds need")
  fi
  # Google sign-in needs the real iOS OAuth client of com.shellx.prod (SHELLX_GOOGLE_IOS_CLIENT in
  # Release.xcconfig); the placeholder only serves builds that never reach the store.
  value="$(plist_value ShellXGoogleClientID "$info" || true)"
  if ! [[ "$value" =~ ^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$ ]]; then
    if [ "$mode" = "signed" ]; then
      fail+=("ShellXGoogleClientID is '$value', not a Google iOS client id (set SHELLX_GOOGLE_IOS_CLIENT in shellx-ios/Config/Release.xcconfig)")
    else
      note "$label: ShellXGoogleClientID is not a Google iOS client id yet ('$value'): Continue with Google cannot work in this build"
    fi
  fi
  # Google's branding guidelines want the official "G" (asset GoogleG) and Google Sans on the Continue with Google
  # button (contracts §11); without them the button shows its text only.
  local google_mark="" google_font=""
  if [ -f "$app/Assets.car" ] && assetutil --info "$app/Assets.car" 2>/dev/null | grep -Eq '"Name" *: *"GoogleG"'; then google_mark=yes; fi
  if [ -f "$app/GoogleSans.ttf" ]; then google_font=yes; fi
  if [ -z "$google_mark" ] || [ -z "$google_font" ]; then
    if [ "$mode" = "signed" ]; then
      fail+=("lacks Google's sign-in branding (the GoogleG asset or GoogleSans.ttf); see shellx-ios/README.md, Assets")
    else
      note "$label: no Google “G” mark or Google Sans yet: Continue with Google shows its text-only fallback"
    fi
  fi

  if [ "$mode" = "signed" ]; then
    local entitlements="$WORK/entitlements.plist"
    team="$( { codesign -dv --verbose=2 "$app" 2>&1 || true; } | awk -F= '$1 == "TeamIdentifier" { print $2 }')"
    if [ "$team" = "not set" ]; then team=""; fi
    [ "$team" = "$TEAM_ID" ] || fail+=("signed by team '${team:-none}', expected $TEAM_ID")
    if ! codesign -d --entitlements - --xml "$app" >"$entitlements" 2>/dev/null; then : >"$entitlements"; fi
    if [ "$(plist_value get-task-allow "$entitlements" || true)" = "true" ]; then
      fail+=("get-task-allow is true (a development signature)")
    fi
    # Push is optional until P4; when the entitlement is there it must point at production APNs.
    if value="$(plist_value aps-environment "$entitlements")" && [ "$value" != "production" ]; then
      fail+=("aps-environment is '$value', expected production")
    fi
    # Sign in with Apple (S1 §6.6).
    if [ "$(plist_value com.apple.developer.applesignin:0 "$entitlements" || true)" != "Default" ]; then
      fail+=("lacks the Sign in with Apple entitlement (com.apple.developer.applesignin = Default)")
    fi
  fi

  # P3 embeds no framework: everything is linked statically into the executable.
  if [ -d "$app/Frameworks" ]; then
    local framework
    if find "$app/Frameworks" -maxdepth 1 -name '*.framework' >"$WORK/frameworks.txt"; then
      while IFS= read -r framework; do
        if [ -n "$framework" ]; then fail+=("embeds Frameworks/$(basename "$framework"), expected no framework"); fi
      done <"$WORK/frameworks.txt"
    else
      fail+=("could not list Frameworks/")
    fi
  fi

  # The test fakes stay out of the App Store build because Release.xcconfig leaves ShellXAppTestSupport out of
  # the link and the SHELLX_DEMO switch is under #if DEBUG; Swift keeps type names in a stripped binary, so every
  # Mach-O file in the bundle (the executable, dylibs, frameworks, plug-ins) is searched for them.
  executable="$(plist_value CFBundleExecutable "$info" || true)"
  if [ -z "$executable" ] || [ ! -f "$app/$executable" ]; then
    fail+=("has no executable (CFBundleExecutable is '$executable')")
  fi
  local file kind status scanned=0 executable_scanned=0
  if find "$app" -type f >"$WORK/files.txt"; then
    while IFS= read -r file; do
      [ -n "$file" ] || continue
      kind="$(file -b "$file" 2>/dev/null)" || kind=""
      case "$kind" in Mach-O*) ;; *) continue ;; esac
      scanned=$((scanned + 1))
      if [ -n "$executable" ] && [ "$file" = "$app/$executable" ]; then executable_scanned=1; fi
      if ! strings -a "$file" >"$WORK/strings.txt" 2>/dev/null; then
        fail+=("could not read the strings of ${file#"$app"/}")
        continue
      fi
      status=0
      grep -oE "$DEBUG_ONLY_NAMES" "$WORK/strings.txt" >"$WORK/found.txt" || status=$?
      case "$status" in
        0) fail+=("${file#"$app"/} contains Debug-only code: $(LC_ALL=C sort -u "$WORK/found.txt" | tr '\n' ' ' | sed 's/ $//')") ;;
        1) ;;
        *) fail+=("could not search ${file#"$app"/} for Debug-only code") ;;
      esac
    done <"$WORK/files.txt"
  else
    fail+=("could not list the files of the bundle")
  fi
  if [ -n "$executable" ] && [ -f "$app/$executable" ] && [ "$executable_scanned" -eq 0 ]; then
    fail+=("the executable $executable is not a Mach-O file")
  fi

  if [ ${#fail[@]} -gt 0 ]; then
    local problem
    for problem in "${fail[@]}"; do echo "ios.sh: $label: $problem" >&2; done
    return 1
  fi
  if [ "$mode" = "signed" ]; then
    note "$label: team $team, $bundle_id $version ($build); no framework, no Debug-only code in $scanned Mach-O files"
  else
    note "$label: unsigned, $bundle_id $version ($build); no framework, no Debug-only code in $scanned Mach-O files"
  fi
}

# Writes to $1 what automatic signing can change, one sorted line each: the keychain's valid
# signing identities, and team W4RF3W4VTZ's provisioning profiles with the certificates they name.
# Names and SHA-1 hashes only.
signing_snapshot() {
  {
    security find-identity -v -p codesigning 2>/dev/null |
      sed -n 's/^[[:space:]]*[0-9][0-9]*) \([0-9A-F]\{40\}\) \(".*"\)[[:space:]]*$/identity \1 \2/p' || true
    python3 -I - "$TEAM_ID" "${PROFILE_DIRS[@]}" <<'PY' || true
import glob, hashlib, os, plistlib, re, subprocess, sys

team, dirs = sys.argv[1], sys.argv[2:]
for directory in dirs:
    for path in sorted(glob.glob(os.path.join(directory, "*.mobileprovision"))):
        decoded = subprocess.run(["security", "cms", "-D", "-i", path], capture_output=True).stdout
        try:
            profile = plistlib.loads(decoded)
        except Exception:
            print("profile %s (unreadable)" % os.path.basename(path))
            continue
        if team not in profile.get("TeamIdentifier", []):
            continue
        print('profile %s "%s"' % (profile.get("UUID"), profile.get("Name")))
        for der in profile.get("DeveloperCertificates", []):
            subject = subprocess.run(["openssl", "x509", "-inform", "DER", "-noout", "-subject"],
                                     input=der, capture_output=True).stdout.decode(errors="replace")
            match = re.search(r"CN\s*=\s*([^,/\n]+)", subject)
            print('certificate %s "%s"' % (hashlib.sha1(der).hexdigest().upper(),
                                           match.group(1).strip() if match else "?"))
PY
  } | LC_ALL=C sort -u >"$1"
}

# Prints what step $3 changed between signing snapshots $1 and $2: prominently when anything did.
signing_report() {
  local added removed
  added="$(LC_ALL=C comm -13 "$1" "$2")"
  removed="$(LC_ALL=C comm -23 "$1" "$2")"
  if [ -z "$added" ] && [ -z "$removed" ]; then
    note "$3: no new or removed profile, certificate or signing identity"
    return 0
  fi
  {
    echo "!!! ========================================================================"
    echo "!!! $3 changed team $TEAM_ID's signing assets (-allowProvisioningUpdates):"
    if [ -n "$added" ]; then printf '%s\n' "$added" | sed 's/^/!!!   new:  /'; fi
    if [ -n "$removed" ]; then printf '%s\n' "$removed" | sed 's/^/!!!   gone: /'; fi
    echo "!!! Review them in the developer account (Certificates, Identifiers & Profiles)."
    echo "!!! ========================================================================"
  } >&2
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

# Runs xcodebuild like run_xcodebuild, between two signing snapshots, and reports what changed.
signed_xcodebuild() {
  local name="$1" step="$2"
  shift 2
  work_dir
  signing_snapshot "$WORK/signing-before.txt"
  local status=0
  run_xcodebuild "$name" "$@" || status=1
  signing_snapshot "$WORK/signing-after.txt"
  signing_report "$WORK/signing-before.txt" "$WORK/signing-after.txt" "$step"
  return $status
}

# Prints "<commit> clean" or "<commit> dirty": whether the build's sources (SOURCE_PATHS) have
# uncommitted changes, untracked files included.
source_state() {
  local head changes
  head="$(git -C "$REPO_ROOT" rev-parse HEAD)" || die "cannot read the commit of $REPO_ROOT"
  changes="$(git -C "$REPO_ROOT" status --porcelain -- "${SOURCE_PATHS[@]}")" ||
    die "cannot read the git status of $REPO_ROOT"
  if [ -n "$changes" ]; then echo "$head dirty"; else echo "$head clean"; fi
}

# Unzips ipa $1 and checks its app (signed).
check_ipa() {
  work_dir
  rm -rf "$WORK/ipa"
  mkdir -p "$WORK/ipa"
  unzip -q "$1" -d "$WORK/ipa" || die "cannot unzip $1"
  local app
  app="$(find "$WORK/ipa/Payload" -maxdepth 1 -name '*.app' | head -n 1)"
  [ -n "$app" ] || die "$1 has no Payload/*.app"
  check_app signed "$app" "$1"
}

cmd_check_app() {
  local mode="signed"
  if [ "${1:-}" = "--unsigned" ]; then
    mode="unsigned"
    shift
  fi
  [ $# -eq 1 ] || usage 2
  read_version
  if ! check_app "$mode" "$1"; then exit 1; fi
}

cmd_build() {
  read_version
  [ -f "$EXPORT_OPTIONS" ] || die "missing $EXPORT_OPTIONS"
  local archive="$OUT_DIR/$NAME.xcarchive" ipa="$OUT_DIR/$NAME.ipa"
  local source="$OUT_DIR/$NAME.source" uploaded="$OUT_DIR/$NAME.uploaded"
  if [ -e "$uploaded" ]; then
    die "ShellX $VERSION ($BUILD) was uploaded ($(cat "$uploaded")); its archive stays. Raise CURRENT_PROJECT_VERSION in shellx-ios/Config/Version.xcconfig."
  fi
  mkdir -p "$OUT_DIR"
  rm -rf "$archive" "$ipa" "$source"
  work_dir
  # Taken before the build, so a change made while it runs makes --upload refuse it.
  source_state >"$WORK/source"

  note "ShellX iOS $VERSION ($BUILD): Release archive (automatic signing, team $TEAM_ID)"
  signed_xcodebuild "archive-$NAME" "archive" archive \
    -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED" \
    -archivePath "$archive" \
    -allowProvisioningUpdates ||
    die "archive failed; if signing failed, check Xcode > Settings > Accounts (team $TEAM_ID)"

  note "App Store export"
  signed_xcodebuild "export-$NAME" "export" -exportArchive \
    -archivePath "$archive" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$WORK/export" \
    -allowProvisioningUpdates ||
    die "export failed; if signing failed, check Xcode > Settings > Accounts (team $TEAM_ID)"
  local exported
  exported="$(find "$WORK/export" -maxdepth 1 -name '*.ipa')"
  [ -n "$exported" ] || die "the export produced no ipa"
  [ "$(printf '%s\n' "$exported" | wc -l | tr -d ' ')" -eq 1 ] || die "the export produced more than one ipa"
  mv "$exported" "$ipa"

  if ! check_ipa "$ipa"; then
    rm -f "$ipa"
    die "refused the ipa (removed); the archive is kept at $archive"
  fi
  cp "$WORK/source" "$source"
  if [ "$(cut -d ' ' -f 2 "$source")" = "dirty" ]; then
    note "built from uncommitted changes: fine for testing, but --upload refuses it"
  fi
  echo "Not uploaded. After testing it, upload this build with: release/mobile/ios.sh --upload"
}

cmd_upload() {
  read_version
  [ -f "$EXPORT_OPTIONS" ] || die "missing $EXPORT_OPTIONS"
  local archive="$OUT_DIR/$NAME.xcarchive" ipa="$OUT_DIR/$NAME.ipa"
  local source="$OUT_DIR/$NAME.source" uploaded="$OUT_DIR/$NAME.uploaded"
  if [ -e "$uploaded" ]; then
    die "ShellX $VERSION ($BUILD) was already uploaded ($(cat "$uploaded")). Raise CURRENT_PROJECT_VERSION and run release/mobile/ios.sh."
  fi
  [ -d "$archive" ] || die "no archive of ShellX $VERSION ($BUILD); run release/mobile/ios.sh first"
  [ -f "$ipa" ] && [ -f "$source" ] ||
    die "the archive of ShellX $VERSION ($BUILD) did not pass the checks; run release/mobile/ios.sh first"
  local built current
  built="$(cat "$source")"
  current="$(source_state)"
  [ "${current#* }" = "clean" ] ||
    die "shellx-ios/, shellx-link/ or release/mobile/ has uncommitted changes; commit them, then run release/mobile/ios.sh again"
  [ "$built" = "$current" ] ||
    die "the archive was built from '$built', the checkout is now '$current'; run release/mobile/ios.sh again"
  if ! check_ipa "$ipa"; then die "refused the ipa"; fi

  # The checked archive, signed the same way, with destination=upload: Xcode's account session
  # uploads it.
  note "uploading ShellX $VERSION ($BUILD) to App Store Connect"
  work_dir
  cp "$EXPORT_OPTIONS" "$WORK/upload.plist"
  /usr/libexec/PlistBuddy -c "Set :destination upload" "$WORK/upload.plist"
  signed_xcodebuild "upload-$NAME" "upload" -exportArchive \
    -archivePath "$archive" \
    -exportOptionsPlist "$WORK/upload.plist" \
    -exportPath "$WORK/upload" \
    -allowProvisioningUpdates ||
    die "upload failed"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) from ${built% *}" >"$uploaded"
  note "uploaded ShellX $VERSION ($BUILD). App Store Connect > ShellX > TestFlight lists it after processing (about 5-30 minutes)."
}

case "${1:-}" in
  "") cmd_build ;;
  --upload) [ $# -eq 1 ] || usage 2; cmd_upload ;;
  --check-app) shift; cmd_check_app "$@" ;;
  -h|--help|help) usage 0 ;;
  *) echo "ios.sh: unknown option $1" >&2; usage 2 ;;
esac
