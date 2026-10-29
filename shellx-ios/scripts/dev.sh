#!/usr/bin/env bash
# Builds, installs and tests the ShellX iOS app. Together with release/mobile/ios.sh, this is the
# only place that runs xcodebuild for shellx-ios/.
#
#   dev.sh sim [--demo] [--api <url>] [--headless]
#       Debug build, installed and opened on the private simulator "ShellX Dev".
#       --demo sets SHELLX_DEMO=1, --api sets SHELLX_API_BASE (both honoured by Debug builds only),
#       --headless skips bringing up the Simulator window.
#   dev.sh device [--device-id <id>] [--demo] [--build-only]
#       Debug build signed automatically for team W4RF3W4VTZ, installed and opened with devicectl.
#       Device id: --device-id, then $SHELLX_IPHONE_DEVICE_ID, then ~/.config/shellx/iphone-device-id.
#       --build-only stops after the build (no device needed).
#   dev.sh build-release
#       Release build for a generic iPhone without signing (no Apple account), then
#       release/mobile/ios.sh --check-app --unsigned: bundle id, version, no embedded framework and
#       no Debug-only code (the demo, FakeMac, InMemorySecretStore...).
#   dev.sh test [core|app|release|all] [--runtime <ver>]
#       core: swift test for Packages/ShellXAppCore; app: the ShellXTests bundle on "ShellX Dev";
#       release: build-release; all: the three. Each also runs scripts/shellx/check-ios-license.sh
#       and scripts/check-strings.py.
#   dev.sh screenshots <dir> [--runtime <ver>]
#       Runs every *RenderTests class twice (-testLanguage en, then vi), writing PNGs into <dir>.
#   dev.sh clean
#       Deletes the private simulators and shellx-ios/.derived.
#
# The script never uses a simulator other than "ShellX Dev" (or "ShellX Dev (iOS <ver>)" for an
# explicit older --runtime), and keeps at most one of them booted. It never asks for a password.
set -euo pipefail

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
REPO_ROOT="$(cd "$IOS_DIR/.." && pwd -P)"
PROJECT="$IOS_DIR/ShellX.xcodeproj"
SCHEME="ShellX"
DERIVED="$IOS_DIR/.derived"
CORE_PACKAGE="$IOS_DIR/Packages/ShellXAppCore"
SIM_NAME="ShellX Dev"
DEBUG_BUNDLE_ID="com.shellx.dev"
DEVICE_ID_FILE="$HOME/.config/shellx/iphone-device-id"

die() { echo "dev.sh: $*" >&2; exit 1; }
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

# Prints "<runtime identifier> <version> <newest|older>" for the newest installed iOS runtime, or
# for the newest one matching <ver> (e.g. "18" or "18.4") when given.
resolve_runtime() {
  xcrun simctl list runtimes -j | python3 -c '
import json, sys
wanted = sys.argv[1]
def key(r):
    return tuple(int(p) for p in r["version"].split(".") if p.isdigit())
runtimes = sorted(
    (r for r in json.load(sys.stdin)["runtimes"] if r.get("platform") == "iOS" and r.get("isAvailable")),
    key=key)
if not runtimes:
    sys.exit("no iOS simulator runtime is installed (Xcode > Settings > Components)")
newest = runtimes[-1]
if wanted:
    matching = [r for r in runtimes if r["version"] == wanted or r["version"].startswith(wanted + ".")]
    if not matching:
        sys.exit("no installed iOS runtime matches %s" % wanted)
    chosen = matching[-1]
else:
    chosen = newest
print(chosen["identifier"], chosen["version"], "newest" if chosen is newest else "older")
' "${1:-}"
}

# Prints "<udid> <state> <name>" for every private simulator: "ShellX Dev" and "ShellX Dev (iOS <ver>)".
# The state has no spaces ("Shutting_Down"), so `read -r udid state name` splits the line right.
shellx_sims() {
  xcrun simctl list devices -j | python3 -c '
import json, sys
base = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d.get("isAvailable", True) and (d["name"] == base or d["name"].startswith(base + " (iOS ")):
            print(d["udid"], d["state"].replace(" ", "_"), d["name"])
' "$SIM_NAME"
}

# Prints the udid of the private simulator named $1, or nothing.
find_sim() {
  local udid state name
  while read -r udid state name; do
    if [ -n "$udid" ] && [ "$name" = "$1" ]; then echo "$udid"; return 0; fi
  done <<<"$(shellx_sims)"
}

# Prints the device type for a new simulator on runtime $1: iPhone 16 (393x852 pt, the size the
# snapshot tests render at) when the runtime has it, otherwise the newest iPhone it supports.
pick_device_type() {
  xcrun simctl list runtimes -j | python3 -c '
import json, sys
runtime = next(r for r in json.load(sys.stdin)["runtimes"] if r["identifier"] == sys.argv[1])
phones = [t["identifier"] for t in runtime.get("supportedDeviceTypes", []) if t.get("productFamily") == "iPhone"]
preferred = "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
if preferred in phones:
    print(preferred)
elif phones:
    print(phones[-1])
else:
    sys.exit("runtime %s supports no iPhone" % sys.argv[1])
' "$1"
}

# Creates (when needed) and boots the private simulator, shutting down any other booted
# "ShellX Dev*" simulator first. Prints its udid.
ensure_sim() {
  local runtime_line runtime_id runtime_version age name udid
  runtime_line="$(resolve_runtime "${1:-}")" || exit 1
  read -r runtime_id runtime_version age <<<"$runtime_line"
  name="$SIM_NAME"
  if [ "$age" = "older" ]; then name="$SIM_NAME (iOS $runtime_version)"; fi

  udid="$(find_sim "$name")"
  if [ -z "$udid" ]; then
    local device_type
    device_type="$(pick_device_type "$runtime_id")" || exit 1
    note "creating simulator \"$name\" ($device_type, iOS $runtime_version)"
    udid="$(xcrun simctl create "$name" "$device_type" "$runtime_id")"
  fi

  local other_udid other_state other_name
  while read -r other_udid other_state other_name; do
    if [ -n "$other_udid" ] && [ "$other_udid" != "$udid" ] && [ "$other_state" = "Booted" ]; then
      note "shutting down \"$other_name\" (only one ShellX simulator runs at a time)"
      xcrun simctl shutdown "$other_udid" >/dev/null 2>&1 || true
    fi
  done <<<"$(shellx_sims)"

  # -b boots the simulator when it is not running yet, then waits until it has finished booting.
  xcrun simctl bootstatus "$udid" -b >/dev/null
  echo "$udid"
}

xcodebuild_sim() {
  local action="$1" udid="$2"
  shift 2
  xcodebuild "$action" \
    -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$DERIVED" \
    "$@"
}

# Runs the ShellXTests bundle on simulator $1 (extra xcodebuild arguments follow). The full log goes
# to .derived/logs/; the terminal gets test results, errors and warnings.
xcodebuild_test() {
  local udid="$1"
  shift
  mkdir -p "$DERIVED/logs"
  local log="$DERIVED/logs/test-$(date +%Y%m%d-%H%M%S).log" status=0
  xcodebuild_sim test "$udid" -parallel-testing-enabled NO "$@" >"$log" 2>&1 || status=1
  grep -E "error:|warning:|Test Case .*(passed|failed|skipped)|Executed [0-9]+ test|\*\* TEST|Testing failed" "$log" |
    grep -v "Metadata extraction skipped" || true
  if [ "$status" -ne 0 ]; then note "full xcodebuild log: $log"; fi
  return $status
}

run_checks() {
  local status=0
  note "licence boundary"
  bash "$REPO_ROOT/scripts/shellx/check-ios-license.sh" || status=1
  note "strings catalog"
  python3 "$IOS_DIR/scripts/check-strings.py" || status=1
  return $status
}

cmd_sim() {
  local demo=0 api="" headless=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --demo) demo=1 ;;
      --api) [ $# -ge 2 ] || die "--api needs a URL"; api="$2"; shift ;;
      --headless) headless=1 ;;
      *) die "sim: unknown option $1" ;;
    esac
    shift
  done
  local udid app
  udid="$(ensure_sim)"
  note "building Debug for \"$SIM_NAME\""
  xcodebuild_sim build "$udid" -quiet
  app="$DERIVED/Build/Products/Debug-iphonesimulator/ShellX.app"
  [ -d "$app" ] || die "build produced no $app"
  xcrun simctl install "$udid" "$app"
  if [ "$headless" -eq 0 ]; then open -a Simulator --args -CurrentDeviceUDID "$udid"; fi
  (
    if [ "$demo" -eq 1 ]; then export SIMCTL_CHILD_SHELLX_DEMO=1; fi
    if [ -n "$api" ]; then export SIMCTL_CHILD_SHELLX_API_BASE="$api"; fi
    xcrun simctl launch --terminate-running-process "$udid" "$DEBUG_BUNDLE_ID" >/dev/null
  )
  note "ShellX Dev is running on simulator $udid"
  echo "$udid"
}

cmd_device() {
  local device_id="" demo=0 build_only=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --device-id) [ $# -ge 2 ] || die "--device-id needs a value"; device_id="$2"; shift ;;
      --demo) demo=1 ;;
      --build-only) build_only=1 ;;
      *) die "device: unknown option $1" ;;
    esac
    shift
  done
  if [ -z "$device_id" ]; then device_id="${SHELLX_IPHONE_DEVICE_ID:-}"; fi
  if [ -z "$device_id" ] && [ -f "$DEVICE_ID_FILE" ]; then
    device_id="$(tr -d '[:space:]' <"$DEVICE_ID_FILE")"
  fi

  note "building Debug for iPhone (automatic signing, team W4RF3W4VTZ)"
  xcodebuild build \
    -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates \
    -quiet
  local app="$DERIVED/Build/Products/Debug-iphoneos/ShellX.app"
  [ -d "$app" ] || die "build produced no $app"
  if [ "$build_only" -eq 1 ]; then
    note "built $(basename "$app") for iPhone; not installing (--build-only)"
    return 0
  fi

  [ -n "$device_id" ] || die "no device id: pass --device-id <id>, set SHELLX_IPHONE_DEVICE_ID, or write it to $DEVICE_ID_FILE (see: xcrun devicectl list devices)"
  note "installing on device $device_id"
  xcrun devicectl device install app --device "$device_id" "$app"
  local launch=(xcrun devicectl device process launch --device "$device_id" --terminate-existing)
  if [ "$demo" -eq 1 ]; then launch+=(--environment-variables '{"SHELLX_DEMO":"1"}'); fi
  "${launch[@]}" "$DEBUG_BUNDLE_ID"
}

cmd_build_release() {
  [ $# -eq 0 ] || die "build-release takes no options"
  mkdir -p "$DERIVED/logs"
  local log="$DERIVED/logs/build-release-$(date +%Y%m%d-%H%M%S).log" status=0
  note "building Release for iPhone, unsigned"
  xcodebuild build \
    -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO >"$log" 2>&1 || status=1
  grep -E "error:|warning:|\*\* BUILD (SUCCEEDED|FAILED) \*\*" "$log" | grep -v "Metadata extraction skipped" || true
  if [ "$status" -ne 0 ]; then
    note "full xcodebuild log: $log"
    return 1
  fi
  local app="$DERIVED/Build/Products/Release-iphoneos/ShellX.app"
  [ -d "$app" ] || die "build produced no $app"
  note "App Store checks that need no signature"
  "$REPO_ROOT/release/mobile/ios.sh" --check-app --unsigned "$app"
}

cmd_test() {
  local which="all" runtime=""
  while [ $# -gt 0 ]; do
    case "$1" in
      core|app|release|all) which="$1" ;;
      --runtime) [ $# -ge 2 ] || die "--runtime needs a version"; runtime="$2"; shift ;;
      *) die "test: unknown option $1" ;;
    esac
    shift
  done
  local status=0
  run_checks || status=1
  if [ "$which" = "core" ] || [ "$which" = "all" ]; then
    note "swift test ShellXAppCore"
    swift test --package-path "$CORE_PACKAGE" || status=1
  fi
  if [ "$which" = "app" ] || [ "$which" = "all" ]; then
    local udid
    udid="$(ensure_sim "$runtime")"
    note "ShellXTests on simulator $udid"
    xcodebuild_test "$udid" || status=1
  fi
  if [ "$which" = "release" ] || [ "$which" = "all" ]; then
    cmd_build_release || status=1
  fi
  if [ "$status" -ne 0 ]; then note "test $which: FAILED"; else note "test $which: passed"; fi
  return $status
}

cmd_screenshots() {
  local dir="" runtime=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --runtime) [ $# -ge 2 ] || die "--runtime needs a version"; runtime="$2"; shift ;;
      -*) die "screenshots: unknown option $1" ;;
      *) [ -z "$dir" ] || die "screenshots: one directory only"; dir="$1" ;;
    esac
    shift
  done
  [ -n "$dir" ] || die "screenshots needs an output directory"
  mkdir -p "$dir"
  dir="$(cd "$dir" && pwd -P)"

  local only=() file
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    only+=("-only-testing:ShellXTests/$(basename "$file" .swift)")
  done <<<"$(find "$IOS_DIR/ShellXTests" -name '*RenderTests.swift' | sort)"
  [ ${#only[@]} -gt 0 ] || die "no *RenderTests.swift under ShellXTests/"

  local udid lang
  udid="$(ensure_sim "$runtime")"
  for lang in en vi; do
    note "rendering ($lang) into $dir"
    TEST_RUNNER_SHELLX_SNAPSHOT_DIR="$dir" xcodebuild_test "$udid" -testLanguage "$lang" "${only[@]}"
  done
  note "screenshots written to $dir"
}

cmd_clean() {
  local udid state name
  while read -r udid state name; do
    [ -n "$udid" ] || continue
    note "deleting simulator \"$name\""
    if [ "$state" = "Booted" ]; then xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true; fi
    xcrun simctl delete "$udid"
  done <<<"$(shellx_sims)"
  note "removing $DERIVED"
  rm -rf "$DERIVED"
}

[ $# -gt 0 ] || usage 1
command="$1"
shift
case "$command" in
  sim) cmd_sim "$@" ;;
  device) cmd_device "$@" ;;
  build-release) cmd_build_release "$@" ;;
  test) cmd_test "$@" ;;
  screenshots) cmd_screenshots "$@" ;;
  clean) cmd_clean "$@" ;;
  -h|--help|help) usage 0 ;;
  *) echo "dev.sh: unknown command $command" >&2; usage 1 ;;
esac
