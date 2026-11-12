#!/usr/bin/env bash
# Builds the Google Play app bundle of the ShellX Android app (shellx-android/, com.shellx.prod), signed with
# the upload key, and checks it. It never uploads: the maintainer uploads the bundle in Play Console by hand.
# See release/mobile/README.md: "Android: every release", and "Android: what android.sh refuses" for the checks.
#
#   release/mobile/android.sh
#       Release bundle (R8 on) signed with the upload key, then every check. Writes
#       build/release/android/ShellX-<version>-<code>.aab, its R8 mapping (.mapping.txt) and the commit it was
#       built from (.source). Refuses uncommitted changes in shellx-android/, shellx-link/, release/mobile/ or the
#       licence check files, a commit that is not on origin/develop or origin/main (fetched first), and a version
#       code that was already uploaded.
#   release/mobile/android.sh --check-aab <file.aab> [<mapping.txt>]
#       Only the bundle checks and the upload-key signature check, on a bundle that is already built.
#   release/mobile/android.sh --mark-uploaded
#       Records that the checked bundle of the current version was uploaded in Play Console
#       (ShellX-<version>-<code>.uploaded). From then on the build refuses this version code.
#
# The upload key's properties file (storeFile, storePassword, keyAlias, keyPassword) is
# $SHELLX_ANDROID_KEY_PROPERTIES, default ~/.shellx-release/key.properties (mode 600, outside the repo).
# The script never prints a password: keytool reads the store password from the environment.
set -euo pipefail

APP_ID=com.shellx.prod
MIN_BUNDLETOOL=1.17.0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
ANDROID_DIR="$REPO_ROOT/shellx-android"
OUT_DIR="$REPO_ROOT/build/release/android"
CHECKER="$REPO_ROOT/release/mobile/check_android_bundle.py"
# What the build is made from; the build refuses when any of it has uncommitted changes.
SOURCE_PATHS=(shellx-android shellx-link release/mobile
  scripts/shellx/check-android-license.sh scripts/shellx/check_android_license.py
  scripts/shellx/android-license-allowlist.txt scripts/shellx/check-link-license.sh)

: "${JAVA_HOME:=/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
: "${ANDROID_HOME:=$HOME/Library/Android/sdk}"
: "${SHELLX_ANDROID_KEY_PROPERTIES:=$HOME/.shellx-release/key.properties}"
export JAVA_HOME ANDROID_HOME SHELLX_ANDROID_KEY_PROPERTIES

die() { echo "android.sh: $*" >&2; exit 1; }
note() { echo "==> $*"; }

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
cleanup() { if [ -n "$WORK" ]; then rm -r -f "${WORK:?}"; fi; }
trap cleanup EXIT
work_dir() {
  if [ -z "$WORK" ]; then WORK="$(mktemp -d)"; fi
}

VERSION_FILE="$ANDROID_DIR/version.properties"
VERSION_NAME=""
VERSION_CODE=""
NAME=""
read_version() {
  [ -f "$VERSION_FILE" ] || die "missing $VERSION_FILE"
  VERSION_NAME="$(sed -n 's/^VERSION_NAME=//p' "$VERSION_FILE" | tail -n 1)"
  VERSION_CODE="$(sed -n 's/^VERSION_CODE=//p' "$VERSION_FILE" | tail -n 1)"
  [[ "$VERSION_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    die "VERSION_NAME '$VERSION_NAME' in shellx-android/version.properties is not X.Y.Z"
  if ! [[ "$VERSION_CODE" =~ ^[1-9][0-9]{0,9}$ ]] || [ "$VERSION_CODE" -gt 2100000000 ]; then
    die "VERSION_CODE '$VERSION_CODE' in shellx-android/version.properties is not an integer from 1 to 2100000000"
  fi
  NAME="ShellX-$VERSION_NAME-$VERSION_CODE"
}

require_clean_and_pushed() {
  local dirty head
  dirty="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=normal -- "${SOURCE_PATHS[@]}")"
  if [ -n "$dirty" ]; then
    echo "android.sh: uncommitted changes in shellx-android/, shellx-link/, release/mobile/ or the licence check; commit them first:" >&2
    printf '%s\n' "$dirty" | head -n 20 >&2
    exit 1
  fi
  git -C "$REPO_ROOT" fetch --quiet origin 2>/dev/null ||
    die "could not fetch origin, so HEAD cannot be checked against origin/develop and origin/main"
  head="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  local ref
  for ref in refs/remotes/origin/develop refs/remotes/origin/main; do
    if git -C "$REPO_ROOT" show-ref --verify --quiet "$ref" &&
       git -C "$REPO_ROOT" merge-base --is-ancestor "$head" "$ref"; then
      return 0
    fi
  done
  die "HEAD $head is not on origin/develop or origin/main; push it first (git push origin develop)"
}

KEYTOOL=""
JARSIGNER=""
require_tools() {
  local first major version
  first="$("$JAVA_HOME/bin/java" -version 2>&1 | head -n 1 || true)"
  major="$(printf '%s\n' "$first" | sed -n 's/.*"\([0-9][0-9]*\)[."].*/\1/p')"
  if ! [[ "$major" =~ ^[0-9]+$ ]] || [ "$major" -lt 17 ]; then
    die "JDK 17 or newer needed (JAVA_HOME=$JAVA_HOME)"
  fi
  KEYTOOL="$JAVA_HOME/bin/keytool"
  JARSIGNER="$JAVA_HOME/bin/jarsigner"
  [ -x "$KEYTOOL" ] && [ -x "$JARSIGNER" ] || die "keytool or jarsigner missing in $JAVA_HOME/bin"
  command -v bundletool >/dev/null 2>&1 || die "bundletool not found; install it with: brew install bundletool"
  version="$(bundletool version 2>/dev/null | tail -n 1 || true)"
  if [ -z "$version" ] || [ "$(printf '%s\n%s\n' "$MIN_BUNDLETOOL" "$version" | sort -V | head -n 1)" != "$MIN_BUNDLETOOL" ]; then
    die "bundletool ${version:-?} is too old; $MIN_BUNDLETOOL or newer prints the 16 KB alignment (brew upgrade bundletool)"
  fi
  command -v python3 >/dev/null 2>&1 || die "python3 not found on PATH"
}

# Prints the first value of key $1 in the key properties file, verbatim. Never echo its result.
prop() {
  sed -n "s/^[[:space:]]*$1[[:space:]]*[=:][[:space:]]*//p" "$SHELLX_ANDROID_KEY_PROPERTIES" | head -n 1
}

STORE_PATH=""
KEY_ALIAS=""
read_key_properties() {
  local kp="$SHELLX_ANDROID_KEY_PROPERTIES" mode key store_file
  [ -f "$kp" ] || die "no upload key properties at $kp (release/mobile/README.md, \"Android: upload key and tools\")"
  mode="$(stat -f '%Lp' "$kp" 2>/dev/null || stat -c '%a' "$kp")"
  case "$mode" in
    *00) ;;
    *) die "$kp is readable by other users; run: chmod 600 $kp" ;;
  esac
  for key in storeFile storePassword keyAlias keyPassword; do
    [ -n "$(prop "$key")" ] || die "$kp lacks $key"
  done
  store_file="$(prop storeFile)"
  case "$store_file" in
    "~/"*) STORE_PATH="$HOME/${store_file#??}" ;;
    /*) STORE_PATH="$store_file" ;;
    *) STORE_PATH="$(dirname "$kp")/$store_file" ;;
  esac
  [ -f "$STORE_PATH" ] || die "the keystore $STORE_PATH named by storeFile does not exist"
  KEY_ALIAS="$(prop keyAlias)"
}

check_signature() {
  local aab="$1" listing sha256 sha1 verify cert owner actual
  if ! listing="$(SHELLX_STOREPASS="$(prop storePassword)" "$KEYTOOL" -list -v -keystore "$STORE_PATH" \
      -alias "$KEY_ALIAS" -storepass:env SHELLX_STOREPASS 2>/dev/null)"; then
    die "keytool could not read the upload key (wrong storePassword or keyAlias in $SHELLX_ANDROID_KEY_PROPERTIES?)"
  fi
  sha256="$(printf '%s\n' "$listing" | awk '$1 == "SHA256:" { print $2; exit }')"
  sha1="$(printf '%s\n' "$listing" | awk '$1 == "SHA1:" { print $2; exit }')"
  [ -n "$sha256" ] || die "keytool printed no SHA-256 for the upload key"
  verify="$("$JARSIGNER" -verify "$aab" 2>&1 || true)"
  case "$verify" in
    "jar verified."*) ;;
    *) die "jarsigner could not verify $aab" ;;
  esac
  cert="$("$KEYTOOL" -printcert -jarfile "$aab" 2>/dev/null || true)"
  owner="$(printf '%s\n' "$cert" | sed -n 's/^Owner: //p' | head -n 1)"
  case "$owner" in
    *"CN=Android Debug"*) die "$aab is signed with an Android debug key ($owner)" ;;
  esac
  actual="$(printf '%s\n' "$cert" | awk '$1 == "SHA256:" { print $2; exit }')"
  [ "$actual" = "$sha256" ] || die "$aab is signed by SHA-256 $actual, expected the upload key $sha256"
  note "upload key: SHA-256 $sha256 (SHA-1 $sha1)"
}

# run_checker <sources|bundle> <args...>: the Python checker, from the repository root.
run_checker() {
  local command="$1"
  shift
  (
    cd "$REPO_ROOT"
    ledger=()
    if [ -f docs/superpowers/ledgers/shellx-signin-rollout.md ]; then
      ledger=(--rollout-ledger docs/superpowers/ledgers/shellx-signin-rollout.md)
    fi
    python3 -I "$CHECKER" "$command" \
      --google-services shellx-android/app/google-services.json \
      --google-oauth shellx-android/app/src/main/res/values/google_oauth.xml \
      ${ledger[@]+"${ledger[@]}"} "$@"
  )
}

# check_bundle <aab> <extra checker args...>
check_bundle() {
  local aab="$1" catalog
  shift
  catalog="$(sed -n 's/^[[:space:]]*androidTargetSdk[[:space:]]*=[[:space:]]*"\([0-9][0-9]*\)".*/\1/p' \
    "$ANDROID_DIR/gradle/libs.versions.toml" | head -n 1)"
  [ -n "$catalog" ] || die "no androidTargetSdk in shellx-android/gradle/libs.versions.toml"
  work_dir
  bundletool dump manifest --bundle="$aab" >"$WORK/manifest.xml" 2>/dev/null || die "bundletool could not read $aab"
  bundletool dump config --bundle="$aab" >"$WORK/bundle-config.json" 2>/dev/null || die "bundletool could not read $aab"
  run_checker bundle --aab "$aab" --manifest-xml "$WORK/manifest.xml" --bundle-config "$WORK/bundle-config.json" \
    --version-name "$VERSION_NAME" --version-code "$VERSION_CODE" --catalog-target-sdk "$catalog" \
    --play-rules release/mobile/android-play-target-sdk.txt --permissions release/mobile/android-permissions.txt \
    --today "$(date +%F)" "$@"
}

cmd_build() {
  read_version
  if [ -f "$OUT_DIR/$NAME.uploaded" ]; then
    die "ShellX $VERSION_NAME ($VERSION_CODE) was uploaded ($(cat "$OUT_DIR/$NAME.uploaded")); Google Play refuses a versionCode it has seen. Raise VERSION_CODE in shellx-android/version.properties"
  fi
  require_clean_and_pushed
  require_tools
  read_key_properties
  note "ShellX Android $VERSION_NAME ($VERSION_CODE): release bundle signed with the upload key"

  note "licence boundary"
  bash "$REPO_ROOT/scripts/shellx/check-android-license.sh" ||
    die "the licence check failed (scripts/shellx/check-android-license.sh)"
  note "source checks"
  run_checker sources --lockfile shellx-android/app/gradle.lockfile || die "the source checks failed (above)"

  local dirs=() dir cleartext
  for dir in shellx-android/app/src/main shellx-android/app/src/release; do
    if [ -d "$REPO_ROOT/$dir" ]; then dirs+=("$dir"); fi
  done
  cleartext="$(cd "$REPO_ROOT" && grep -rlI 'cleartextTrafficPermitted="true"' ${dirs[@]+"${dirs[@]}"} | tr '\n' ' ' || true)"
  cleartext="${cleartext% }"
  [ -z "$cleartext" ] || die "a release source set permits cleartext traffic: $cleartext"

  local aab="$ANDROID_DIR/app/build/outputs/bundle/release/app-release.aab"
  local mapping="$ANDROID_DIR/app/build/outputs/mapping/release/mapping.txt"
  rm -f "${OUT_DIR:?}/${NAME:?}.aab" "${OUT_DIR:?}/${NAME:?}.mapping.txt" "${OUT_DIR:?}/${NAME:?}.source" "${aab:?}" "${mapping:?}"

  local log_name="gradle-$NAME-$(date +%Y%m%d-%H%M%S).log" log
  mkdir -p "$OUT_DIR/logs"
  log="$OUT_DIR/logs/$log_name"
  note "Gradle :app:bundleRelease (log: build/release/android/logs/$log_name)"
  if ! "$ANDROID_DIR/gradlew" -p "$ANDROID_DIR" --console=plain --no-configuration-cache :app:bundleRelease >"$log" 2>&1; then
    grep -E 'error:|warning:|What went wrong|FAILURE|BUILD (SUCCESSFUL|FAILED)' "$log" || true
    die "Gradle failed; full log: $log"
  fi
  grep -E 'error:|warning:|What went wrong|FAILURE|BUILD (SUCCESSFUL|FAILED)' "$log" || true
  [ -f "$aab" ] || die "Gradle produced no $aab"

  check_signature "$aab"
  check_bundle "$aab" --mapping "$mapping" --lockfile shellx-android/app/gradle.lockfile ||
    die "refused $aab (the checks above); nothing was written to build/release/android/"

  cp "$aab" "$OUT_DIR/$NAME.aab"
  cp "$mapping" "$OUT_DIR/$NAME.mapping.txt"
  echo "$(git -C "$REPO_ROOT" rev-parse HEAD) clean" >"$OUT_DIR/$NAME.source"

  local ios=""
  if [ -f "$REPO_ROOT/shellx-ios/Config/Version.xcconfig" ]; then
    ios="$(sed -n 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*\([^[:space:]]*\).*/\1/p' \
      "$REPO_ROOT/shellx-ios/Config/Version.xcconfig" | tail -n 1)"
  fi
  if [ -n "$ios" ] && [ "$ios" != "$VERSION_NAME" ]; then
    note "note: VERSION_NAME $VERSION_NAME is not the iPhone's MARKETING_VERSION $ios (contracts §7: the same features carry the same version)"
  fi
  note "build/release/android/$NAME.aab (and .mapping.txt, .source)"
  echo "Not uploaded. Upload it in Play Console (release/mobile/README.md, \"Android: every release\"), then run: release/mobile/android.sh --mark-uploaded"
}

cmd_check_aab() {
  { [ "$#" -ge 1 ] && [ "$#" -le 2 ]; } || usage 2
  local aab="$1" mapping="${2:-}"
  [ -f "$aab" ] || die "$aab is not a file"
  case "$aab" in /*) ;; *) aab="$PWD/$aab" ;; esac
  if [ -n "$mapping" ]; then
    [ -f "$mapping" ] || die "$mapping is not a file"
    case "$mapping" in /*) ;; *) mapping="$PWD/$mapping" ;; esac
  fi
  read_version
  require_tools
  read_key_properties
  check_signature "$aab"
  if [ -n "$mapping" ]; then
    check_bundle "$aab" --mapping "$mapping" || die "refused $aab (the checks above)"
  else
    check_bundle "$aab" || die "refused $aab (the checks above)"
  fi
}

cmd_mark_uploaded() {
  read_version
  local uploaded="$OUT_DIR/$NAME.uploaded"
  [ ! -f "$uploaded" ] || die "ShellX $VERSION_NAME ($VERSION_CODE) is already marked uploaded ($(cat "$uploaded"))"
  if [ ! -f "$OUT_DIR/$NAME.aab" ] || [ ! -f "$OUT_DIR/$NAME.source" ]; then
    die "no checked bundle of ShellX $VERSION_NAME ($VERSION_CODE); run release/mobile/android.sh first"
  fi
  local sha
  sha="$(awk '{ print $1; exit }' "$OUT_DIR/$NAME.source")"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) from $sha" >"$uploaded"
  note "recorded: ShellX $VERSION_NAME ($VERSION_CODE) uploaded. The next upload needs VERSION_CODE $((VERSION_CODE + 1)) or higher."
}

if [ "$#" -eq 0 ]; then
  cmd_build
else
  case "$1" in
    --check-aab) shift; cmd_check_aab "$@" ;;
    --mark-uploaded) [ "$#" -eq 1 ] || usage 2; cmd_mark_uploaded ;;
    -h|--help|help) usage 0 ;;
    *) echo "android.sh: unknown option $1" >&2; usage 2 ;;
  esac
fi
