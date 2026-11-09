#!/usr/bin/env bash
# Builds, installs and tests the ShellX Android app. Together with release/mobile/android.sh (plan 3H), this is
# the only place that runs Gradle for shellx-android/ and shellx-link/kotlin/.
#
#   dev.sh test [link|core|app|screenshots|all]
#       link: the JVM tests of shellx-link/kotlin; core: the :core tests; app: the :app unit tests of the debug
#       and release variants (Robolectric); screenshots: the *RenderTest classes; all (the default): all of
#       them, the script tests and build-release. Every test command first runs
#       scripts/shellx/check-android-license.sh, scripts/import-strings.py --check and the version catalog check.
#   dev.sh screenshots record <dir>
#       Runs every *RenderTest class and writes <name>-<light|dark>-<en|vi>.png into <dir>.
#   dev.sh emulator --api <26|36> [--headless]
#       Creates (first time) and boots the private emulator "ShellX_Dev_API_<n>" from an installed system image,
#       shutting the other one down, then installs and opens the debug app "ShellX Dev" on it.
#   dev.sh device [--serial <id>]
#       Installs and opens the debug app on a phone. Serial: --serial, then $SHELLX_ANDROID_SERIAL, then
#       ~/.config/shellx/android-serial, then the only phone `adb devices` lists.
#   dev.sh build-release
#       Unsigned release build (R8 on), then checks app id com.shellx.prod, label "ShellX", the version in
#       version.properties, the min and target SDK, the locale config, the permissions (check-release-permissions),
#       no cleartext, and that it is not debuggable.
#   dev.sh lock
#       Rewrites every gradle.lockfile after a dependency change. Then update
#       scripts/shellx/android-license-allowlist.txt until check-android-license.sh passes.
#   dev.sh clean
#       Deletes the private emulators and the build/ folders of both builds.
#
# JAVA_HOME defaults to Android Studio's JDK and ANDROID_HOME to ~/Library/Android/sdk. The script never
# downloads SDK packages (the user installs them with sdkmanager), never installs a release (non-debuggable) APK on a phone,
# and keeps at most one ShellX emulator running.
set -euo pipefail

ANDROID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
REPO_ROOT="$(cd "$ANDROID_DIR/.." && pwd -P)"
LINK_DIR="$REPO_ROOT/shellx-link/kotlin"
APP_ID="com.shellx.prod"
RELEASE_APP_ID="$APP_ID"
MAIN_ACTIVITY="com.shellx.app.MainActivity"
SERIAL_FILE="$HOME/.config/shellx/android-serial"

: "${JAVA_HOME:=/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
: "${ANDROID_HOME:=$HOME/Library/Android/sdk}"
export JAVA_HOME ANDROID_HOME
ADB="$ANDROID_HOME/platform-tools/adb"
AVDMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"
EMULATOR="$ANDROID_HOME/emulator/emulator"
AVD_HOME="${ANDROID_AVD_HOME:-${ANDROID_USER_HOME:-$HOME/.android}/avd}"

die() { echo "dev.sh: $1" >&2; exit "${2:-1}"; }
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

check_java() {
  local line major
  line="$("$JAVA_HOME/bin/java" -version 2>&1 | head -1)" || die "JDK 17 or newer needed (JAVA_HOME=$JAVA_HOME)"
  major="$(printf '%s' "$line" | sed -E 's/.*version "([0-9]+).*/\1/')"
  case "$major" in
    ''|*[!0-9]*) die "JDK 17 or newer needed (JAVA_HOME=$JAVA_HOME)" ;;
  esac
  [ "$major" -ge 17 ] || die "JDK 17 or newer needed (JAVA_HOME=$JAVA_HOME)"
}

gradle_android() { "$ANDROID_DIR/gradlew" -p "$ANDROID_DIR" --console=plain "$@"; }
gradle_link() { "$LINK_DIR/gradlew" -p "$LINK_DIR" --console=plain "$@"; }

catalog_value() { sed -n -E "s/^$2 = \"([^\"]*)\".*/\1/p" "$1" | head -1; }

run_checks() {
  note "licence boundary"
  bash "$REPO_ROOT/scripts/shellx/check-android-license.sh"
  note "strings"
  python3 "$ANDROID_DIR/scripts/import-strings.py" --check
  note "version catalogs"
  local key a b
  for key in kotlin junit; do
    a="$(catalog_value "$LINK_DIR/gradle/libs.versions.toml" "$key")"
    b="$(catalog_value "$ANDROID_DIR/gradle/libs.versions.toml" "$key")"
    if [ -z "$a" ] || [ "$a" != "$b" ]; then
      die "shellx-link/kotlin and shellx-android pin different $key versions ($a vs $b)"
    fi
  done
  echo "version catalogs agree: kotlin $(catalog_value "$ANDROID_DIR/gradle/libs.versions.toml" kotlin), junit $(catalog_value "$ANDROID_DIR/gradle/libs.versions.toml" junit)"
}

cmd_test() {
  local which="${1:-all}"
  case "$which" in
    link|core|app|screenshots|all) ;;
    *) die "unknown test target: $which (link, core, app, screenshots or all)" 2 ;;
  esac
  check_java
  run_checks
  local status=0
  case "$which" in
    link) gradle_link test || status=$? ;;
    core) gradle_android :core:test || status=$? ;;
    app) gradle_android --continue :app:testDebugUnitTest :app:testReleaseUnitTest || status=$? ;;
    screenshots) gradle_android :app:testDebugUnitTest --tests 'com.shellx.app.screenshots.*' || status=$? ;;
    all)
      python3 -m unittest discover -s "$ANDROID_DIR/scripts/tests" -t "$ANDROID_DIR/scripts/tests" || status=$?
      [ "$status" -ne 0 ] || gradle_link test || status=$?
      [ "$status" -ne 0 ] || gradle_android :core:test || status=$?
      [ "$status" -ne 0 ] || gradle_android --continue :app:testDebugUnitTest :app:testReleaseUnitTest || status=$?
      [ "$status" -ne 0 ] || (cmd_build_release) || status=$?
      ;;
  esac
  if [ "$status" -eq 0 ]; then
    note "test $which: passed"
  else
    note "test $which: FAILED"
  fi
  return "$status"
}

contains() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
has_line() { grep -qxF -- "$2" <<<"$1"; }
prop_value() { sed -n -E "s/^$2=(.*)$/\1/p" "$1" | head -1; }

aapt2_path() {
  local tools
  tools="$(ls "$ANDROID_HOME/build-tools" 2>/dev/null | sort -V | tail -1)" || tools=""
  [ -n "$tools" ] && [ -x "$ANDROID_HOME/build-tools/$tools/aapt2" ] || die "aapt2 not found under $ANDROID_HOME/build-tools"
  printf '%s\n' "$ANDROID_HOME/build-tools/$tools/aapt2"
}

# The release APK's permissions (3D): network, network state and the camera for the pairing QR code, the camera
# optional, and no storage, media, biometric or fingerprint access. androidx.credentials pulls androidx.biometric,
# whose manifest asks for USE_BIOMETRIC and USE_FINGERPRINT; app/src/main/AndroidManifest.xml removes them (review A I-3).
check_release_permissions() {
  local apk="$1" aapt2 badging want
  aapt2="$(aapt2_path)" || exit 1
  badging="$("$aapt2" dump badging "$apk")" || die "aapt2 dump badging failed on $apk"
  for want in INTERNET ACCESS_NETWORK_STATE CAMERA; do
    contains "$badging" "uses-permission: name='android.permission.$want'" \
      || die "release APK: expected uses-permission: name='android.permission.$want'"
  done
  if grep -qE "uses-permission: name='android\.permission\.(READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE|MANAGE_EXTERNAL_STORAGE|READ_MEDIA_[A-Z_]*)'" <<<"$badging"; then
    die "release APK: expected no storage or media permission (READ_/WRITE_/MANAGE_EXTERNAL_STORAGE, READ_MEDIA_*)"
  fi
  for want in USE_BIOMETRIC USE_FINGERPRINT; do
    if contains "$badging" "uses-permission: name='android.permission.$want'"; then
      die "release APK: expected no android.permission.$want (the app has no biometric sign-in)"
    fi
  done
  contains "$badging" "uses-feature-not-required: name='android.hardware.camera'" \
    || die "release APK: expected uses-feature-not-required: name='android.hardware.camera' (the camera is optional)"
}

# Each step checks its own status: cmd_test runs this in a subshell after `||`, where set -e does not apply.
cmd_build_release() {
  check_java
  gradle_android :app:assembleRelease || die "release build failed"
  local apk="$ANDROID_DIR/app/build/outputs/apk/release/app-release-unsigned.apk"
  local mapping="$ANDROID_DIR/app/build/outputs/mapping/release/mapping.txt"
  [ -f "$apk" ] || die "release APK missing: $apk"
  local AAPT2 VC VN T badging manifest want
  AAPT2="$(aapt2_path)" || exit 1
  VC="$(prop_value "$ANDROID_DIR/version.properties" VERSION_CODE)"
  VN="$(prop_value "$ANDROID_DIR/version.properties" VERSION_NAME)"
  T="$(catalog_value "$ANDROID_DIR/gradle/libs.versions.toml" androidTargetSdk)"
  [ -n "$VC" ] && [ -n "$VN" ] && [ -n "$T" ] || die "could not read VERSION_CODE, VERSION_NAME or androidTargetSdk"
  badging="$("$AAPT2" dump badging "$apk")" || die "aapt2 dump badging failed on $apk"
  for want in "package: name='$RELEASE_APP_ID' versionCode='$VC' versionName='$VN'" "minSdkVersion:'26'" \
    "targetSdkVersion:'$T'" "application-label:'ShellX'"; do
    contains "$badging" "$want" || die "release APK: expected $want"
  done
  if contains "$badging" "application-debuggable"; then die "release APK is debuggable"; fi
  check_release_permissions "$apk"
  manifest="$("$AAPT2" dump xmltree --file AndroidManifest.xml "$apk")" || die "aapt2 dump xmltree failed on $apk"
  contains "$manifest" "localeConfig" || die "release APK: the manifest has no localeConfig"
  if contains "$manifest" "networkSecurityConfig" || contains "$manifest" "usesCleartextTraffic"; then
    die "release APK: expected no networkSecurityConfig and no usesCleartextTraffic (cleartext is debug only)"
  fi
  [ -f "$mapping" ] || die "release APK: $mapping is missing (R8 did not run)"
  if [ ! -f "$ANDROID_DIR/app/google-services.json" ]; then
    note "Firebase: not configured (no google-services.json); push stays off in this build"
  fi
  note "release checks passed ($RELEASE_APP_ID $VN ($VC), target SDK $T)"
}

cmd_screenshots() {
  [ "${1:-}" = "record" ] && [ $# -eq 2 ] && [ -n "$2" ] || die "usage: dev.sh screenshots record <dir>" 2
  local dir="$2"
  mkdir -p "$dir" || die "cannot create $dir"
  dir="$(cd "$dir" && pwd -P)" || die "cannot open $dir"
  check_java
  gradle_android :app:testDebugUnitTest --tests 'com.shellx.app.screenshots.*' --rerun -Pshellx.snapshot.dir="$dir" \
    || die "render tests failed"
  note "screenshots written to $dir"
}

# Serials `adb devices` lists, one per line: in state $1, or in any state when $1 is empty.
adb_serials() {
  local out
  out="$("$ADB" devices 2>/dev/null)" || die "adb failed ($ADB)"
  printf '%s\n' "$out" | awk -v want="${1:-}" 'NR > 1 && NF >= 2 && (want == "" || $2 == want) { print $1 }'
}

# The AVD name an emulator serial runs ("" when it does not answer). A port alone does not say whose it is.
avd_name() {
  local out try=0
  while [ "$try" -lt 5 ]; do
    out="$("$ADB" -s "$1" emu avd name 2>/dev/null)" || out=""
    out="$(printf '%s\n' "$out" | sed -n '1p' | tr -d '\r')"
    if [ -n "$out" ]; then printf '%s\n' "$out"; return 0; fi
    try=$((try + 1)); sleep 1
  done
  return 0
}

# The serial of the running emulator whose AVD is $1, or nothing.
serial_of_avd() {
  local s
  for s in $(adb_serials | grep '^emulator-' || true); do
    if [ "$(avd_name "$s")" = "$1" ]; then printf '%s\n' "$s"; return 0; fi
  done
  return 0
}

# Shuts down the ShellX emulator on <serial> (AVD <name>) and waits up to 60 s for it to exit.
stop_emulator() {
  local serial="$1" name="$2" waited=0
  note "shutting down $name on $serial"
  "$ADB" -s "$serial" emu kill >/dev/null 2>&1 || true
  while has_line "$(adb_serials)" "$serial"; do
    [ "$waited" -lt 60 ] || die "$name on $serial did not shut down"
    sleep 2; waited=$((waited + 2))
  done
}

# Refuses an APK that must not go onto <target> (phone or emulator). Debug and release share the id
# com.shellx.prod, so the package alone cannot tell them apart: a phone gets only a debuggable APK, and a
# release build never lands on a real phone from this script. An emulator takes any com.shellx.prod APK
# (the plan's debug-signed release build included).
check_apk() {
  local target="$1" apk="$2" aapt2 badging
  case "$target" in phone|emulator) ;; *) die "check-apk: target must be phone or emulator" 2 ;; esac
  aapt2="$(aapt2_path)" || exit 1
  badging="$("$aapt2" dump badging "$apk")" || die "aapt2 dump badging failed on $apk"
  contains "$badging" "package: name='$APP_ID' " || die "$apk is not $APP_ID; refusing to install it"
  if [ "$target" = "phone" ] && ! contains "$badging" "application-debuggable"; then
    die "$apk is not debuggable (a release build); refusing to install it on a phone"
  fi
}

# Builds the debug app, installs it on <serial> (a phone or an emulator, see check_apk) and opens it.
build_and_open() {
  local serial="$1" target="$2" apk="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk" out
  gradle_android :app:assembleDebug >&2 || die "debug build failed"
  check_apk "$target" "$apk"
  "$ADB" -s "$serial" install -r "$apk" >&2 || die "could not install $APP_ID on $serial"
  out="$("$ADB" -s "$serial" shell am start -W -S -n "$APP_ID/$MAIN_ACTIVITY" 2>&1)" \
    || die "could not start $APP_ID on $serial: $out"
  printf '%s\n' "$out" >&2
  contains "$out" "Status: ok" || die "$APP_ID did not start on $serial"
}

cmd_emulator() {
  local api="" headless=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --api) [ $# -ge 2 ] || die "emulator: --api needs 26 or 36" 2; api="$2"; shift 2 ;;
      --headless) headless=1; shift ;;
      *) die "emulator: unknown option $1 (use --api <26|36> [--headless])" 2 ;;
    esac
  done
  local port other_api
  case "$api" in
    26) port=5580; other_api=36 ;;
    36) port=5582; other_api=26 ;;
    *) die "emulator: --api must be 26 or 36" 2 ;;
  esac
  check_java
  local name="ShellX_Dev_API_$api" serial="emulator-$port" tag="" t avds config log pid waited boot running other
  for t in google_apis_playstore google_apis default; do
    if [ -d "$ANDROID_HOME/system-images/android-$api/$t/arm64-v8a" ]; then tag="$t"; break; fi
  done
  [ -n "$tag" ] || die "no arm64-v8a system image for API $api; ask the user to run: sdkmanager --install \"system-images;android-$api;google_apis;arm64-v8a\""

  avds="$("$AVDMANAGER" list avd -c 2>/dev/null)" || die "avdmanager failed ($AVDMANAGER)"
  if ! has_line "$avds" "$name"; then
    note "creating $name from system-images;android-$api;$tag;arm64-v8a"
    echo no | "$AVDMANAGER" create avd -n "$name" -k "system-images;android-$api;$tag;arm64-v8a" -d pixel_5 >&2 \
      || die "could not create $name"
    config="$AVD_HOME/$name.avd/config.ini"
    [ -f "$config" ] || die "$config is missing after avdmanager create"
    sed -i '' -e '/^hw\.ramSize=/d' -e '/^hw\.keyboard=/d' "$config"
    printf 'hw.ramSize=2048\nhw.keyboard=yes\n' >>"$config"
  fi

  # One ShellX emulator at a time: the other ShellX AVD is shut down, on whatever port it runs. Emulators of
  # other AVDs are never touched, even on a ShellX port.
  other="$(serial_of_avd "ShellX_Dev_API_$other_api")"
  [ -z "$other" ] || stop_emulator "$other" "ShellX_Dev_API_$other_api"

  pid=""
  running="$(serial_of_avd "$name")"
  if [ -n "$running" ]; then
    serial="$running"
  elif has_line "$(adb_serials)" "$serial"; then
    die "$serial runs another emulator ($(avd_name "$serial")), not $name; stop it or free port $port"
  else
    mkdir -p "$ANDROID_DIR/build/dev"
    log="$ANDROID_DIR/build/dev/emulator-$api.log"
    note "starting $name on $serial (log: $log)"
    if [ "$headless" -eq 1 ]; then
      nohup "$EMULATOR" -avd "$name" -port "$port" -no-snapshot-save -no-boot-anim -no-window </dev/null >"$log" 2>&1 &
    else
      nohup "$EMULATOR" -avd "$name" -port "$port" -no-snapshot-save -no-boot-anim </dev/null >"$log" 2>&1 &
    fi
    pid=$!
  fi

  # Waits for the device and then for sys.boot_completed, polling every 2 s for at most 300 s.
  waited=0
  while :; do
    boot="$("$ADB" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" || boot=""
    [ "$boot" = "1" ] && break
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then die "the emulator stopped; see $log"; fi
    [ "$waited" -lt 300 ] || die "$serial did not finish booting in 300 s"
    sleep 2; waited=$((waited + 2))
  done

  build_and_open "$serial" emulator
  note "ShellX Dev is running on $serial"
  echo "$serial"
}

cmd_device() {
  local serial="" phones count
  while [ $# -gt 0 ]; do
    case "$1" in
      --serial) [ $# -ge 2 ] && [ -n "$2" ] || die "device: --serial needs an id" 2; serial="$2"; shift 2 ;;
      *) die "device: unknown option $1 (use [--serial <id>])" 2 ;;
    esac
  done
  [ -n "$serial" ] || serial="${SHELLX_ANDROID_SERIAL:-}"
  if [ -z "$serial" ] && [ -f "$SERIAL_FILE" ]; then
    serial="$(head -1 "$SERIAL_FILE" | tr -d '[:space:]')"
  fi
  if [ -z "$serial" ]; then
    phones="$(adb_serials device | grep -v '^emulator-' || true)"
    count="$(printf '%s' "$phones" | grep -c . || true)"
    [ "$count" = "1" ] || die "no single phone to use ($count connected); pass --serial, set SHELLX_ANDROID_SERIAL or write $SERIAL_FILE"
    serial="$phones"
  fi
  case "$serial" in
    emulator-*) die "$serial is an emulator; use dev.sh emulator --api <26|36>" 2 ;;
  esac
  check_java
  [ "$("$ADB" -s "$serial" get-state 2>/dev/null | tr -d '\r')" = "device" ] \
    || die "phone $serial is not ready: unlock it and allow USB debugging"
  build_and_open "$serial" phone
  note "ShellX Dev is running on $serial"
}

cmd_clean() {
  local api serial avds dir
  # Only ShellX AVDs are shut down (by name, on any port), and each one has exited before its AVD is deleted.
  for api in 26 36; do
    serial="$(serial_of_avd "ShellX_Dev_API_$api")"
    [ -z "$serial" ] || stop_emulator "$serial" "ShellX_Dev_API_$api"
  done
  if [ -x "$AVDMANAGER" ]; then
    check_java
    avds="$("$AVDMANAGER" list avd -c 2>/dev/null)" || die "avdmanager failed ($AVDMANAGER)"
    for api in 26 36; do
      if has_line "$avds" "ShellX_Dev_API_$api"; then
        note "deleting ShellX_Dev_API_$api"
        "$AVDMANAGER" delete avd -n "ShellX_Dev_API_$api" >&2 || die "could not delete ShellX_Dev_API_$api"
      fi
    done
  fi
  for dir in "$ANDROID_DIR/build" "$ANDROID_DIR/app/build" "$ANDROID_DIR/core/build" \
    "$LINK_DIR/build" "$LINK_DIR/link-core/build" "$LINK_DIR/link-account/build"; do
    rm -rf "$dir"
  done
  note "clean: done"
}

cmd_lock() {
  check_java
  gradle_link :link-core:dependencies :link-account:dependencies --write-locks -q >/dev/null
  gradle_android :core:dependencies :app:dependencies --write-locks -q >/dev/null
}

[ $# -gt 0 ] || usage 2
command="$1"
shift
case "$command" in
  -h|--help|help) usage 0 ;;
  test) cmd_test "$@" ;;
  lock) cmd_lock ;;
  build-release) cmd_build_release ;;
  screenshots) cmd_screenshots "$@" ;;
  emulator) cmd_emulator "$@" ;;
  device) cmd_device "$@" ;;
  clean) cmd_clean ;;
  check-apk) [ $# -eq 2 ] || usage 2; check_apk "$@" ;;
  check-release-permissions) [ $# -eq 1 ] || usage 2; check_release_permissions "$1" ;;
  *) echo "dev.sh: unknown command: $command" >&2; usage 2 ;;
esac
