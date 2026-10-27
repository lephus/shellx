#!/usr/bin/env bash
# Licence boundary check for shellx-ios/, the closed-source ShellX iOS app. The app may use only
# Apple frameworks, its own code and the MIT package shellx-link/; never GPL code from ios/,
# Packages/, Sources/, cmux-tui/ or shellx-core/, and never a package downloaded from the network.
#
#   scripts/shellx/check-ios-license.sh [--root <repository root>]
#
# Exits 1 and prints each offending path when:
#   1. a Package.swift under shellx-ios/ declares a network package (`url:`, `.package(id:`) or has
#      a `path:` that resolves outside shellx-ios/ and shellx-link/;
#   2. a project.pbxproj under shellx-ios/ has an XCRemoteSwiftPackageReference, or a `path` or
#      `relativePath` that is absolute or resolves outside those two folders (relative values are
#      resolved against the folder holding the .xcodeproj, which errs on the strict side);
#   3. a .swift file under shellx-ios/ imports a module outside ALLOWED_MODULES;
#   4. a text file under shellx-ios/ contains the word "Manaflow" (any case);
#   5. scripts/shellx/check-link-license.sh (next to this script) fails.
#
# ALLOWED_MODULES is an allowlist on purpose: a new GPL module added under Packages/ is blocked
# without anyone having to remember to update this script.
set -u
set -f

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || { echo "check-ios-license: --root needs a directory" >&2; exit 2; }
      ROOT="$(cd "$2" && pwd -P)" || exit 2
      shift
      ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "check-ios-license: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done

APP="$ROOT/shellx-ios"
LINK="$ROOT/shellx-link"
if [ ! -d "$APP" ]; then
  echo "check-ios-license: missing $APP"
  exit 1
fi

ALLOWED_MODULES="
  Swift _Concurrency Darwin Dispatch Foundation os OSLog Observation Combine Synchronization RegexBuilder
  SwiftUI UIKit CoreFoundation CoreGraphics CoreImage CoreText CoreMedia CoreVideo CoreHaptics
  CoreTransferable QuartzCore ImageIO UniformTypeIdentifiers Accessibility TipKit
  CryptoKit Security LocalAuthentication AuthenticationServices Network
  Speech AVFoundation AVFAudio AVKit AudioToolbox Vision VisionKit PhotosUI
  UserNotifications BackgroundTasks AppIntents WidgetKit ActivityKit StoreKit SafariServices
  LinkPresentation NaturalLanguage MetricKit
  XCTest Testing PackageDescription
  ShellXLinkCore ShellXLinkRelay ShellXLinkSession ShellXLinkAccount
  ShellXAppCore ShellXAppTestSupport ShellX
"

fail=0
violation() {
  echo "violation: $1: $2"
  fail=1
}

# The path relative to the root, for messages.
rel() { echo "${1#"$ROOT"/}"; }

# Lexically normalises an absolute path (resolves "." and ".." without touching the disk).
normalize() {
  local out="" part IFS='/'
  for part in $1; do
    case "$part" in
      '' | .) ;;
      ..) out="${out%/*}" ;;
      *) out="$out/$part" ;;
    esac
  done
  echo "${out:-/}"
}

inside_allowed() {
  case "$1" in
    "$APP" | "$APP"/* | "$LINK" | "$LINK"/*) return 0 ;;
  esac
  return 1
}

# check_path <file> <base dir> <value> <what>
check_path() {
  case "$3" in
    /* | '~'*)
      violation "$(rel "$1")" "$4 \"$3\" is absolute"
      return
      ;;
  esac
  if ! inside_allowed "$(normalize "$2/$3")"; then
    violation "$(rel "$1")" "$4 \"$3\" points outside shellx-ios/ and shellx-link/"
  fi
}

# Every file under shellx-ios/ named $1, except build output.
app_files() {
  find "$APP" \( -name .build -o -name .derived -o -name .swiftpm -o -name xcuserdata -o -name DerivedData \) -prune \
    -o -type f -name "$1" -print
}

# 1. Swift package manifests.
while IFS= read -r manifest; do
  [ -n "$manifest" ] || continue
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    violation "$(rel "$manifest"):${hit%%:*}" "network package (${hit#*:})"
  done <<<"$(grep -nE '(^|[^A-Za-z_])url:[[:space:]]*"|\.package\([[:space:]]*id:' "$manifest")"
  while IFS= read -r value; do
    [ -n "$value" ] || continue
    check_path "$manifest" "$(dirname "$manifest")" "$value" "path"
  done <<<"$(grep -oE 'path:[[:space:]]*"[^"]*"' "$manifest" | sed -E 's/^path:[[:space:]]*"(.*)"$/\1/')"
done <<<"$(app_files Package.swift)"

# 2. Xcode projects.
while IFS= read -r pbxproj; do
  [ -n "$pbxproj" ] || continue
  project_dir="$(dirname "$(dirname "$pbxproj")")"
  if grep -q 'XCRemoteSwiftPackageReference' "$pbxproj"; then
    violation "$(rel "$pbxproj")" "XCRemoteSwiftPackageReference (a package downloaded from the network)"
  fi
  while IFS= read -r value; do
    [ -n "$value" ] || continue
    check_path "$pbxproj" "$project_dir" "$value" "path"
  done <<<"$(grep -oE '(^|[^A-Za-z_])(path|relativePath) = ("[^"]*"|[^;]*);' "$pbxproj" |
    sed -E 's/^[^A-Za-z_]?(path|relativePath) = //; s/;$//; s/^"(.*)"$/\1/')"
done <<<"$(app_files project.pbxproj)"

# 3. Swift imports.
import_line='^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]+'
import_module='s/^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*$/\7/'
while IFS= read -r source; do
  [ -n "$source" ] || continue
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    module="$(echo "${hit#*:}" | sed -E "$import_module")"
    case "$ALLOWED_MODULES" in
      *[[:space:]]"$module"[[:space:]]*) ;;
      *) violation "$(rel "$source"):${hit%%:*}" "imports $module, which is not on the allowlist" ;;
    esac
  done <<<"$(grep -nE "$import_line" "$source")"
done <<<"$(app_files '*.swift')"

# 4. The word Manaflow (any case; "manaflow-ai" and "cmux.manaflow.com" count, an identifier such
#    as testManaflowStringFails does not) in the app's text files.
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  violation "$(rel "$hit")" "mentions Manaflow"
done <<<"$(grep -rIilw --exclude-dir=.build --exclude-dir=.derived --exclude-dir=.swiftpm --exclude-dir=xcuserdata \
  --exclude-dir=DerivedData 'manaflow' "$APP")"

# 5. The shellx-link boundary.
if ! link_output="$(bash "$SCRIPT_DIR/check-link-license.sh" 2>&1)"; then
  echo "$link_output"
  violation "shellx-link" "scripts/shellx/check-link-license.sh failed"
fi

if [ "$fail" -eq 0 ]; then
  echo "check-ios-license: ok"
fi
exit "$fail"
