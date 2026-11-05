#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cmux-bundled-resources-test.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE \
  GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX

SRCROOT="$TMP_DIR/src"
BUILD_DIR="$TMP_DIR/build"
mkdir -p "$SRCROOT/ghostty/zig-out/share/ghostty/nested" \
  "$SRCROOT/ghostty/zig-out/share/terminfo" \
  "$SRCROOT/ghostty/src/shell-integration/zsh" \
  "$SRCROOT/Resources/shell-integration" \
  "$SRCROOT/Resources/terminfo-overlay" \
  "$BUILD_DIR/cmux.app/Contents/Resources/CmuxFoundation_CmuxFoundation.bundle/Contents" \
  "$SRCROOT/scripts" "$BUILD_DIR/Resources" "$BUILD_DIR/Products"

printf 'resource-v1\n' > "$SRCROOT/ghostty/zig-out/share/ghostty/nested/file"
printf 'shell\n' > "$SRCROOT/ghostty/src/shell-integration/zsh/ghostty-integration"
printf 'term\n' > "$SRCROOT/ghostty/zig-out/share/terminfo/x"
printf 'cmux\n' > "$SRCROOT/Resources/shell-integration/cmux.zsh"
# ShellX's default dark theme ships from Resources even when the Ghostty share
# comes from the submodule build.
mkdir -p "$SRCROOT/Resources/ghostty/themes"
printf 'background = #0b0716\n' > "$SRCROOT/Resources/ghostty/themes/ShellX"
printf 'alternate\n' > "$SRCROOT/Resources/shell-integration/alternate.zsh"
ln -s cmux.zsh "$SRCROOT/Resources/shell-integration/current.zsh"
printf 'plist\n' > "$BUILD_DIR/Products/Info.plist"
printf 'localized-v1\n' > "$BUILD_DIR/cmux.app/Contents/Resources/CmuxFoundation_CmuxFoundation.bundle/Contents/Localizable.strings"
# A tracked source file outside every directory the phase copies, so only the
# Ghostty worktree part of the stamp can notice it changing.
printf 'helper-source-v1\n' > "$SRCROOT/ghostty/src/main.zig"

git -C "$SRCROOT/ghostty" init -q
git -C "$SRCROOT/ghostty" config user.email test@example.invalid
git -C "$SRCROOT/ghostty" config user.name test
git -C "$SRCROOT/ghostty" add .
git -C "$SRCROOT/ghostty" commit -q -m fixture

cat > "$SRCROOT/scripts-build-helper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
while [[ $# -gt 0 ]]; do
  [[ "$1" == "--output" ]] && output="$2" && shift 2 || shift
done
mkdir -p "$(dirname "$output")"
printf 'ghostty-helper\n' > "$output"
chmod +x "$output"
EOF
cat > "$SRCROOT/scripts-build-cua" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
helper_app=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --helper-app) helper_app="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$(dirname "$output")"
printf 'cua-helper\n' > "$output"
printf 'license\n' > "$(dirname "$output")/cmux-cua-LICENSE.md"
chmod +x "$output"
if [[ -z "$helper_app" && "$output" == *.app/Contents/Resources/bin/cmux-cua ]]; then
  helper_app="${output%/Resources/bin/cmux-cua}/Library/cmux Computer Use.app"
fi
if [[ -n "$helper_app" ]]; then
  mkdir -p "$helper_app/Contents/MacOS" "$helper_app/Contents/Resources"
  printf 'cua-helper-app\n' > "$helper_app/Contents/MacOS/cmux-cua"
  chmod +x "$helper_app/Contents/MacOS/cmux-cua"
  printf 'plist\n' > "$helper_app/Contents/Info.plist"
  printf 'managed\n' > "$helper_app/Contents/Resources/.cmux-cua-managed-helper"
fi
EOF
cat > "$SRCROOT/scripts-build-notifier" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
bundle_id=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --bundle-id) bundle_id="$2"; shift 2 ;;
    *) shift ;;
  esac
done
rm -rf "$output"
mkdir -p "$output/Contents/MacOS"
printf 'notifier\n' > "$output/Contents/MacOS/shellx-notifier"
chmod +x "$output/Contents/MacOS/shellx-notifier"
printf '%s\n' "$bundle_id" > "$output/Contents/Info.plist"
EOF
chmod +x "$SRCROOT/scripts-build-helper" "$SRCROOT/scripts-build-cua" "$SRCROOT/scripts-build-notifier"
mkdir -p "$SRCROOT/scripts/shellx" "$SRCROOT/workers/shellx-notifier"
printf 'notifier-source-v1\n' > "$SRCROOT/workers/shellx-notifier/main.swift"
ln -s "$SRCROOT/scripts-build-notifier" "$SRCROOT/scripts/shellx/build-shellx-notifier.sh"
printf 'apply-v1\n' > "$SRCROOT/scripts/apply-cmux-cua-patch.sh"
printf 'patch-v1\n' > "$SRCROOT/scripts/cmux-cua-codex-delivery-mode.patch"
ln -s "$SRCROOT/scripts-build-helper" "$SRCROOT/scripts/build-ghostty-cli-helper.sh"
ln -s "$SRCROOT/scripts-build-cua" "$SRCROOT/scripts/build-cmux-cua.sh"
ln -s "$ROOT_DIR/scripts/build-app-bundled-resources.sh" "$SRCROOT/scripts/build-app-bundled-resources.sh"

# Upstream coverage of the Computer Use helper build, which ShellX turns off
# by default (the ShellX case is at the end).
run_phase() {
  CMUX_CUA_HELPER_BUILD="${CMUX_CUA_HELPER_BUILD-1}" \
  TARGET_BUILD_DIR="$BUILD_DIR" \
  DERIVED_FILE_DIR="$BUILD_DIR/Derived" \
  UNLOCALIZED_RESOURCES_FOLDER_PATH=Resources \
  INFOPLIST_PATH=Products/Info.plist \
  SRCROOT="$SRCROOT" \
  ARCHS=arm64 \
  bash "$ROOT_DIR/scripts/build-app-bundled-resources.sh" "$@"
}

run_app_phase() {
  CMUX_CUA_HELPER_BUILD="${CMUX_CUA_HELPER_BUILD-1}" \
  TARGET_BUILD_DIR="$BUILD_DIR" \
  DERIVED_FILE_DIR="$BUILD_DIR/Derived" \
  UNLOCALIZED_RESOURCES_FOLDER_PATH="cmux.app/Contents/Resources" \
  INFOPLIST_PATH=Products/Info.plist \
  SRCROOT="$SRCROOT" \
  ARCHS=arm64 \
  bash "$ROOT_DIR/scripts/build-app-bundled-resources.sh" "$@"
}

run_phase > "$TMP_DIR/first.log"
if [[ "$(cat "$BUILD_DIR/Resources/ghostty/themes/ShellX" 2>/dev/null)" != 'background = #0b0716' ]]; then
  echo 'FAIL: the ShellX theme was not bundled with the submodule Ghostty share' >&2
  exit 1
fi
run_phase > "$TMP_DIR/second.log"
grep -q 'skipping helper rebuilds' "$TMP_DIR/second.log"

chmod -x "$BUILD_DIR/Resources/bin/ghostty"
run_phase > "$TMP_DIR/non-executable-helper.log"
if grep -q 'skipping helper rebuilds' "$TMP_DIR/non-executable-helper.log"; then
  echo 'FAIL: non-executable Ghostty helper did not invalidate the stamp' >&2
  exit 1
fi
[[ -x "$BUILD_DIR/Resources/bin/ghostty" ]]

rm "$SRCROOT/Resources/shell-integration/current.zsh"
ln -s alternate.zsh "$SRCROOT/Resources/shell-integration/current.zsh"
run_phase > "$TMP_DIR/symlink.log"
if grep -q 'skipping helper rebuilds' "$TMP_DIR/symlink.log"; then
  echo 'FAIL: retargeted resource symlink did not invalidate the fingerprint' >&2
  exit 1
fi
[[ "$(readlink "$BUILD_DIR/Resources/shell-integration/current.zsh")" == "alternate.zsh" ]]

GIT_DIR="$TMP_DIR/poison.git" GIT_WORK_TREE="$TMP_DIR/poison-worktree" \
  run_phase > "$TMP_DIR/git-env.log"
grep -q 'skipping helper rebuilds' "$TMP_DIR/git-env.log"

rm "$BUILD_DIR/Resources/ghostty/nested/file"
run_phase > "$TMP_DIR/third.log"
if grep -q 'skipping helper rebuilds' "$TMP_DIR/third.log"; then
  echo 'FAIL: deleted nested output was not regenerated' >&2
  exit 1
fi
[[ -f "$BUILD_DIR/Resources/ghostty/nested/file" ]]

APP_BIN="$BUILD_DIR/cmux.app/Contents/Resources/bin"
mkdir -p "$APP_BIN"
printf 'legacy-client\n' > "$APP_BIN/cmux-cua"
chmod +x "$APP_BIN/cmux-cua"
printf 'legacy-license\n' > "$APP_BIN/cmux-cua-LICENSE.md"
RESOURCE_BUNDLE="$BUILD_DIR/cmux.app/Contents/Resources/CmuxFoundation_CmuxFoundation.bundle"
CLI_RESOURCE_BUNDLE="$BUILD_DIR/cmux.app/Contents/Resources/bin/CmuxFoundation_CmuxFoundation.bundle"
# A build directory from before the CLI linked its bundles holds a real copy.
mkdir -p "$CLI_RESOURCE_BUNDLE/Contents"
printf 'stale-copy\n' > "$CLI_RESOURCE_BUNDLE/Contents/Localizable.strings"
run_app_phase > "$TMP_DIR/app-first.log"
# The Computer Use helper's executable is the only copy of the cmux-cua
# engine in the app. A second copy in Resources/bin costs ~11.5 MiB per
# architecture and is removed from bundles built before the change.
if [[ -e "$APP_BIN/cmux-cua" || -e "$APP_BIN/cmux-cua-LICENSE.md" ]]; then
  echo 'FAIL: the app bundle still ships Resources/bin/cmux-cua' >&2
  exit 1
fi
[[ -x "$BUILD_DIR/cmux.app/Contents/Library/cmux Computer Use.app/Contents/MacOS/cmux-cua" ]]
# The CLI, one directory deeper, reaches each package bundle through a relative
# link to the app's copy, so every bundle ships once.
if [[ ! -L "$CLI_RESOURCE_BUNDLE" || "$(readlink "$CLI_RESOURCE_BUNDLE")" != "../CmuxFoundation_CmuxFoundation.bundle" ]]; then
  echo 'FAIL: the CLI resource bundle is not a link to the app resource bundle' >&2
  exit 1
fi
[[ "$(cat "$CLI_RESOURCE_BUNDLE/Contents/Localizable.strings")" == 'localized-v1' ]]
run_app_phase > "$TMP_DIR/app-second.log"
grep -q 'skipping helper rebuilds' "$TMP_DIR/app-second.log"

printf 'localized-v2\n' > "$RESOURCE_BUNDLE/Contents/Localizable.strings"
run_app_phase > "$TMP_DIR/app-bundle-changed.log"
if grep -q 'skipping helper rebuilds' "$TMP_DIR/app-bundle-changed.log"; then
  echo 'FAIL: changed SwiftPM resource bundle did not invalidate the manifest' >&2
  exit 1
fi
[[ "$(cat "$CLI_RESOURCE_BUNDLE/Contents/Localizable.strings")" == 'localized-v2' ]]

OTHER_BUNDLE="$BUILD_DIR/cmux.app/Contents/Resources/Bonsplit_Bonsplit.bundle"
mkdir -p "$OTHER_BUNDLE/Contents"
printf 'other\n' > "$OTHER_BUNDLE/Contents/Info.plist"
run_app_phase > "$TMP_DIR/app-bundle-added.log"
[[ -L "$BUILD_DIR/cmux.app/Contents/Resources/bin/Bonsplit_Bonsplit.bundle" ]]
rm -rf "$OTHER_BUNDLE"
run_app_phase > "$TMP_DIR/app-bundle-removed.log"
if [[ -e "$BUILD_DIR/cmux.app/Contents/Resources/bin/Bonsplit_Bonsplit.bundle" || -L "$BUILD_DIR/cmux.app/Contents/Resources/bin/Bonsplit_Bonsplit.bundle" ]]; then
  echo 'FAIL: a removed package bundle left its CLI link behind' >&2
  exit 1
fi

HELPER_APP="$BUILD_DIR/cmux.app/Contents/Library/cmux Computer Use.app"
rm "$HELPER_APP/Contents/Info.plist"
run_app_phase > "$TMP_DIR/app-missing-plist.log"
if grep -q 'skipping helper rebuilds' "$TMP_DIR/app-missing-plist.log"; then
  echo 'FAIL: missing cmux-cua helper Info.plist did not invalidate the manifest' >&2
  exit 1
fi
[[ -f "$HELPER_APP/Contents/Info.plist" ]]

rm "$HELPER_APP/Contents/Resources/.cmux-cua-managed-helper"
run_app_phase > "$TMP_DIR/app-missing-owner.log"
if grep -q 'skipping helper rebuilds' "$TMP_DIR/app-missing-owner.log"; then
  echo 'FAIL: missing cmux-cua ownership marker did not invalidate the manifest' >&2
  exit 1
fi
[[ -f "$HELPER_APP/Contents/Resources/.cmux-cua-managed-helper" ]]

echo 'PASS: bundled-resource invalidation covers copied trees, Git environment, and complete helper bundles'


# The Ghostty part of the stamp is HEAD plus the differences from it, not a hash of
# every tracked file. Each kind of source change must still invalidate the stamp, and
# an unchanged tree must go back to skipping afterwards.
expect_rebuild_then_skip() {
  local label="$1"
  run_phase > "$TMP_DIR/changed.log"
  if grep -q 'skipping helper rebuilds' "$TMP_DIR/changed.log"; then
    echo "FAIL: $label did not invalidate the bundled-resource stamp" >&2
    exit 1
  fi
  run_phase > "$TMP_DIR/settled.log"
  if ! grep -q 'skipping helper rebuilds' "$TMP_DIR/settled.log"; then
    echo "FAIL: unchanged tree did not skip after $label" >&2
    exit 1
  fi
  echo "PASS: $label invalidates the stamp, then skips again"
}

run_phase > "$TMP_DIR/settle.log"
run_phase > "$TMP_DIR/settle.log"
grep -q 'skipping helper rebuilds' "$TMP_DIR/settle.log"

printf 'helper-source-v2\n' > "$SRCROOT/ghostty/src/main.zig"
expect_rebuild_then_skip 'a modified tracked Ghostty source file'

printf 'scratch\n' > "$SRCROOT/ghostty/untracked-note.txt"
expect_rebuild_then_skip 'a new untracked Ghostty file'

# Committing the same content changes HEAD and empties the diff in one step.
git -C "$SRCROOT/ghostty" add .
git -C "$SRCROOT/ghostty" commit -q -m 'fixture v2'
expect_rebuild_then_skip 'a new Ghostty commit'

# Clean before and clean after: only HEAD can tell these two states apart.
printf 'helper-source-v3\n' > "$SRCROOT/ghostty/src/main.zig"
git -C "$SRCROOT/ghostty" commit -q -am 'fixture v3'
expect_rebuild_then_skip 'a Ghostty revision change on a clean tree'

printf 'patch-v2\n' > "$SRCROOT/scripts/cmux-cua-codex-delivery-mode.patch"
expect_rebuild_then_skip 'a changed cmux-cua compatibility patch'

printf 'apply-v2\n' > "$SRCROOT/scripts/apply-cmux-cua-patch.sh"
expect_rebuild_then_skip 'a changed cmux-cua patch application helper'

cat > "$SRCROOT/fake-zig" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_ZIG_VERSION:-test-zig-v1}"
EOF
chmod +x "$SRCROOT/fake-zig"
CMUX_ZIG="$SRCROOT/fake-zig" run_phase > "$TMP_DIR/toolchain.log"
if grep -q 'skipping helper rebuilds' "$TMP_DIR/toolchain.log"; then
  echo 'FAIL: changed Zig toolchain did not invalidate the stamp' >&2
  exit 1
fi
CMUX_ZIG="$SRCROOT/fake-zig" run_phase > "$TMP_DIR/toolchain-settled.log"
grep -q 'skipping helper rebuilds' "$TMP_DIR/toolchain-settled.log"
FAKE_ZIG_VERSION=test-zig-v2 CMUX_ZIG="$SRCROOT/fake-zig" run_phase > "$TMP_DIR/toolchain-version.log"
if grep -q 'skipping helper rebuilds' "$TMP_DIR/toolchain-version.log"; then
  echo 'FAIL: changed Zig version did not invalidate the stamp' >&2
  exit 1
fi

# ShellX: by default no Computer Use helper is built, and one left in the
# product by an earlier build is removed.
HELPER_APP="$BUILD_DIR/cmux.app/Contents/Library/cmux Computer Use.app"
[[ -d "$HELPER_APP" ]]
CMUX_CUA_HELPER_BUILD=0 run_app_phase > "$TMP_DIR/shellx-no-helper.log"
if [[ -e "$HELPER_APP" ]]; then
  echo 'FAIL: the ShellX build kept the cmux Computer Use helper' >&2
  exit 1
fi
CMUX_CUA_HELPER_BUILD=0 run_app_phase > "$TMP_DIR/shellx-no-helper-settled.log"
grep -q 'skipping helper rebuilds' "$TMP_DIR/shellx-no-helper-settled.log"
[[ ! -e "$HELPER_APP" ]]

# ShellX Notifier: built into Contents/Library with the host id plus ".notifier",
# rebuilt when its source changes or its executable goes missing.
NOTIFIER_APP="$BUILD_DIR/cmux.app/Contents/Library/ShellX Notifier.app"
run_notifier_phase() {
  PRODUCT_BUNDLE_IDENTIFIER=pro.shellx.desktop.test CMUX_CUA_HELPER_BUILD=0 run_app_phase
}
run_notifier_phase > "$TMP_DIR/notifier.log"
[[ -x "$NOTIFIER_APP/Contents/MacOS/shellx-notifier" ]]
grep -qx 'pro.shellx.desktop.test.notifier' "$NOTIFIER_APP/Contents/Info.plist"
run_notifier_phase > "$TMP_DIR/notifier-settled.log"
grep -q 'skipping helper rebuilds' "$TMP_DIR/notifier-settled.log"
rm "$NOTIFIER_APP/Contents/MacOS/shellx-notifier"
run_notifier_phase > "$TMP_DIR/notifier-missing.log"
if grep -q 'skipping helper rebuilds' "$TMP_DIR/notifier-missing.log"; then
  echo 'FAIL: a missing ShellX Notifier executable did not invalidate the stamp' >&2
  exit 1
fi
[[ -x "$NOTIFIER_APP/Contents/MacOS/shellx-notifier" ]]
printf 'notifier-source-v2\n' > "$SRCROOT/workers/shellx-notifier/main.swift"
run_notifier_phase > "$TMP_DIR/notifier-source.log"
if grep -q 'skipping helper rebuilds' "$TMP_DIR/notifier-source.log"; then
  echo 'FAIL: a changed ShellX Notifier source did not invalidate the stamp' >&2
  exit 1
fi
echo 'PASS: the ShellX Notifier helper is built, kept and rebuilt'
