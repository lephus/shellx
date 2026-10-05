#!/bin/bash
# Xcode "Build shellx-term" Run Script phase of the Runner target (spec §4, §10.4): builds
# shellx-term from term/ with cargo and puts it at ShellX.app/Contents/Helpers/shellx-term, where
# ShellX copies it from when terminal sharing is turned on.
#
# Debug: the host architecture only. Profile/Release: universal (arm64 + x86_64) through lipo,
# which needs both Rust targets: rustup target add aarch64-apple-darwin x86_64-apple-darwin.
# The copy gets a local signature (Xcode's identity, or ad hoc); release/macos/sign-app.sh
# re-signs it with the Developer ID, hardened runtime and a timestamp before the app.
set -euo pipefail

# Xcode starts scripts with a minimal PATH; rustup installs into ~/.cargo/bin.
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"

repo="$(cd "${SRCROOT:?run from Xcode}/../../.." && pwd)"
manifest="$repo/term/Cargo.toml"
dest_dir="${TARGET_BUILD_DIR:?}/${CONTENTS_FOLDER_PATH:?}/Helpers"

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found: install Rust (https://rustup.rs) to build shellx-term" >&2
  exit 1
fi

host_target() {
  case "$(uname -m)" in
    arm64) echo aarch64-apple-darwin ;;
    x86_64) echo x86_64-apple-darwin ;;
    *) echo "error: unsupported host architecture $(uname -m)" >&2; return 1 ;;
  esac
}

if [[ "${CONFIGURATION:-Debug}" == "Debug" ]]; then
  targets=("$(host_target)")
else
  targets=(aarch64-apple-darwin x86_64-apple-darwin)
fi

if command -v rustup >/dev/null 2>&1; then
  installed="$(rustup target list --installed)"
  for target in "${targets[@]}"; do
    if ! grep -qx "$target" <<<"$installed"; then
      echo "error: Rust target $target is missing: rustup target add ${targets[*]}" >&2
      exit 1
    fi
  done
fi

# Xcode's environment carries settings meant for clang (SDKROOT is fine; these are not).
unset LD LDFLAGS CFLAGS CXXFLAGS
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"

outputs=()
for target in "${targets[@]}"; do
  cargo build --release --locked --manifest-path "$manifest" --target "$target"
  outputs+=("$repo/term/target/$target/release/shellx-term")
done

mkdir -p "$dest_dir"
tmp="$dest_dir/.shellx-term.tmp"
if [[ ${#outputs[@]} -eq 1 ]]; then
  cp -f "${outputs[0]}" "$tmp"
else
  lipo -create -output "$tmp" "${outputs[@]}"
fi
chmod 755 "$tmp"
identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
codesign --force --options runtime --sign "${identity:--}" "$tmp"
mv -f "$tmp" "$dest_dir/shellx-term"
echo "shellx-term ($(lipo -archs "$dest_dir/shellx-term")) -> $dest_dir/shellx-term"
