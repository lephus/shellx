#!/usr/bin/env bash
# Build, sign, notarize and staple ShellX.app under Apple team W4RF3W4VTZ.
#
# Usage:
#   scripts/shellx/sign-and-notarize.sh --build [derived-data-dir]
#       Release build with ShellX ids and a local GhosttyKit; prints the .app path.
#       This is the one sanctioned non-tagged build: it uses ShellX ids, so it
#       cannot collide with a cmux install. Run it with CMUX_GHOSTTYKIT_NO_PREBUILT=1.
#   scripts/shellx/sign-and-notarize.sh <app-path>
#       Sign inside-out (scripts/sign-cmux-bundle.sh), notarize with the keychain
#       profile shellx-notary, staple, then verify with stapler and spctl.
#
# One-time setup, done by hand (this script never handles credentials):
#   xcrun notarytool store-credentials shellx-notary \
#     --apple-id <apple-id> --team-id W4RF3W4VTZ
#
# Optional env:
#   SHELLX_SIGNING_IDENTITY  default "Developer ID Application: Phu Le huu (W4RF3W4VTZ)"
#   SHELLX_NOTARY_PROFILE    default shellx-notary
#   SHELLX_UNIVERSAL=1       --build makes an arm64 + x86_64 app (public releases)
#
# Signing writes the Sparkle update key from scripts/shellx/release/sparkle-ed25519.pub
# into SUPublicEDKey first, so the signature covers it and the app can verify updates.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

IDENTITY="${SHELLX_SIGNING_IDENTITY:-Developer ID Application: Phu Le huu (W4RF3W4VTZ)}"
NOTARY_PROFILE="${SHELLX_NOTARY_PROFILE:-shellx-notary}"
PRODUCT_NAME="ShellX"
SPARKLE_PUBLIC_KEY_FILE="$REPO_ROOT/scripts/shellx/release/sparkle-ed25519.pub"
ENTITLEMENTS="$REPO_ROOT/shellx.release.entitlements"

usage() {
  echo "usage: $0 --build [derived-data-dir] | $0 <app-path>" >&2
  exit 2
}

build_app() {
  local derived="${1:-$REPO_ROOT/build-shellx}"
  local archs=(ARCHS=arm64 ONLY_ACTIVE_ARCH=YES)
  [[ "${SHELLX_UNIVERSAL:-0}" == 1 ]] && archs=("ARCHS=arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
  cd "$REPO_ROOT"
  "$REPO_ROOT/scripts/ensure-ghosttykit.sh" >&2
  # No Go toolchain is needed: the app no longer embeds the tunnel extension,
  # so its wireguard-go archive may be the stub (Release otherwise requires Go).
  # The Xcode 26.2 -O SIL linker crash on ghostty_surface_clear_selection is gone
  # since 122037ee4d (the app calls the GhosttyKit header symbol only), so this is
  # an optimized build.
  # ENABLE_DEBUG_DYLIB=NO: never split the app into cmux.debug.dylib and
  # __preview.dylib, which the inside-out signer never signs (notary rejects).
  CMUX_WIREGUARD_GO_REQUIRE=0 xcodebuild \
    -project cmux.xcodeproj \
    -scheme cmux \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived" \
    ENABLE_DEBUG_DYLIB=NO \
    "${archs[@]}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_ENTITLEMENTS= \
    build >&2
  # The app target itself is named ShellX (bundle id pro.shellx.desktop, Release
  # PRODUCT_NAME ShellX), so the build produces ShellX.app directly. The Cloud
  # tunnel system extension is no longer embedded in the app.
  local products="$derived/Build/Products/Release"
  echo "$products/$PRODUCT_NAME.app"
}

sign_and_notarize() {
  local app="$1"
  if [[ ! -d "$app" ]]; then
    echo "error: app bundle not found at $app" >&2
    exit 1
  fi
  app="$(cd "$app" && pwd)"
  cd "$REPO_ROOT"

  # Bundle the cmux-tui built from this fork; a failed build stops here instead of
  # leaving CMUX_TUI_CLIENT_LOCAL empty (the installer would then download one).
  local tui; tui="$(scripts/shellx/build-cmux-tui.sh --release --arch universal)"
  CMUX_TUI_CLIENT_LOCAL="$tui" scripts/install-cmux-tui-client.sh "$app"

  local sparkle_key; sparkle_key="$(tr -d '[:space:]' < "$SPARKLE_PUBLIC_KEY_FILE")"
  if [[ ! "$sparkle_key" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    echo "error: $SPARKLE_PUBLIC_KEY_FILE is not a Sparkle Ed25519 public key" >&2
    exit 1
  fi
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $sparkle_key" "$app/Contents/Info.plist"

  echo "==> signing $app"
  "$REPO_ROOT/scripts/sign-cmux-bundle.sh" "$app" "$ENTITLEMENTS" "$IDENTITY"

  local work zip
  work="$(mktemp -d "${TMPDIR:-/tmp}/shellx-notarize.XXXXXX")"
  # Expand now: the EXIT trap runs after this function's locals are gone (set -u).
  trap "rm -rf '$work'" EXIT
  zip="$work/ShellX.zip"
  /usr/bin/ditto -c -k --keepParent "$app" "$zip"

  echo "==> submitting to the Apple notary service (profile $NOTARY_PROFILE)"
  local result
  result="$(xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
  echo "$result"
  local status
  status="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("status", ""))' <<<"$result")"
  if [[ "$status" != "Accepted" ]]; then
    local id
    id="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))' <<<"$result")"
    echo "error: notarization finished with status '$status' (submission $id)" >&2
    [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    exit 1
  fi

  echo "==> stapling"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"

  echo "==> Gatekeeper assessment"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
  spctl -a -vv -t exec "$app" 2>&1 | tee "$work/spctl.txt"
  grep -q 'source=Notarized Developer ID' "$work/spctl.txt" || {
    echo "error: Gatekeeper did not report source=Notarized Developer ID" >&2
    exit 1
  }
  echo "==> signed, notarized and stapled: $app"
}

case "${1:-}" in
  --build) build_app "${2:-}" ;;
  ""|-h|--help|--*) usage ;;
  *) [[ $# -eq 1 ]] || usage; sign_and_notarize "$1" ;;
esac
