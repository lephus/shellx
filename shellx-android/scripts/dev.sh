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
#       version.properties, the min and target SDK, the locale config, and that it is not debuggable.
#   dev.sh lock
#       Rewrites every gradle.lockfile after a dependency change. Then update
#       scripts/shellx/android-license-allowlist.txt until check-android-license.sh passes.
#   dev.sh clean
#       Deletes the private emulators and the build/ folders of both builds.
#
# JAVA_HOME defaults to Android Studio's JDK and ANDROID_HOME to ~/Library/Android/sdk. The script never
# downloads SDK packages (the user installs them with sdkmanager), never installs com.shellx.prod on a phone,
# and keeps at most one ShellX emulator running.
set -euo pipefail

ANDROID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
REPO_ROOT="$(cd "$ANDROID_DIR/.." && pwd -P)"
LINK_DIR="$REPO_ROOT/shellx-link/kotlin"
DEBUG_APP_ID="com.shellx.dev"
RELEASE_APP_ID="com.shellx.prod"
MAIN_ACTIVITY="com.shellx.app.MainActivity"
SERIAL_FILE="$HOME/.config/shellx/android-serial"

: "${JAVA_HOME:=/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
: "${ANDROID_HOME:=$HOME/Library/Android/sdk}"
export JAVA_HOME ANDROID_HOME
ADB="$ANDROID_HOME/platform-tools/adb"

die() { echo "dev.sh: $*" >&2; exit "${2:-1}"; }
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
    link|core|all) ;;
    app|screenshots) die "test $which comes with a later task" 2 ;;
    *) die "unknown test target: $which (link, core, app, screenshots or all)" 2 ;;
  esac
  check_java
  run_checks
  local status=0
  case "$which" in
    link) gradle_link test || status=$? ;;
    core) gradle_android :core:test || status=$? ;;
    all)
      python3 -m unittest discover -s "$ANDROID_DIR/scripts/tests" -t "$ANDROID_DIR/scripts/tests" || status=$?
      [ "$status" -ne 0 ] || gradle_link test || status=$?
      [ "$status" -ne 0 ] || gradle_android :core:test || status=$?
      ;;
  esac
  if [ "$status" -eq 0 ]; then
    note "test $which: passed"
  else
    note "test $which: FAILED"
  fi
  return "$status"
}

cmd_lock() {
  check_java
  gradle_link :link-core:dependencies :link-account:dependencies --write-locks -q >/dev/null
  gradle_android :core:dependencies --write-locks -q >/dev/null
}

[ $# -gt 0 ] || usage 2
command="$1"
shift
case "$command" in
  -h|--help|help) usage 0 ;;
  test) cmd_test "$@" ;;
  lock) cmd_lock ;;
  screenshots|emulator|device|build-release|clean) die "$command comes with a later task" 2 ;;
  *) echo "dev.sh: unknown command: $command" >&2; usage 2 ;;
esac
