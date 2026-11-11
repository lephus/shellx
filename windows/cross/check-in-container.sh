#!/usr/bin/env bash
# Compile check of the Windows app for x86_64-pc-windows-msvc: no installer, no exe.
# Runs inside shellx-wincheck (check.Dockerfile, scripts/shellx/check-windows-build.sh) or
# shellx-winbuild (Dockerfile). /src holds windows, cmux-tui, shellx-core and ghostty from
# the checked commit; /cache is the cache volume.
#
# cargo's dev profile: gpui compiles its HLSL shaders only without debug assertions, so this
# needs neither wine nor fxc.exe.
# SHELLX_WINCHECK_PROFILE=release: the same check in the release profile, so code that exists
# only there (gpui's embedded shader bytes, cfg(not(debug_assertions))) is type-checked too.
# gpui's build script then calls fxc-standin.sh instead of fxc.exe, which compiles no shader:
# nothing may ever be built into an exe this way (a check builds none). Its own target dir
# keeps the dev cache valid.
set -euo pipefail

# /src is a git archive, so cmux-remote's build.rs cannot ask git for HEAD: the driver passes
# the exported commit.
[[ "${CMUX_TUI_BUILD_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]] || { echo "set CMUX_TUI_BUILD_COMMIT to the exported commit" >&2; exit 1; }
unset CMUX_GHOSTTY_SRC
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CARGO_TARGET_DIR=/cache/target ZIG_LOCAL_CACHE_DIR=/cache/zig-local
profile_args=()
ok_line="== windows check: OK"
case "${SHELLX_WINCHECK_PROFILE:-dev}" in
  dev) export SHELLX_WINCHECK_PROFILE=dev ;;
  release)
    [[ -x "$here/fxc-standin.sh" ]] || { echo "release check: $here/fxc-standin.sh is missing" >&2; exit 1; }
    # fxc-standin.sh refuses to run without SHELLX_WINCHECK_PROFILE=release; only this mode sets it.
    export CARGO_TARGET_DIR=/cache/target-release GPUI_FXC_PATH="$here/fxc-standin.sh" SHELLX_WINCHECK_PROFILE=release
    profile_args=(--release)
    ok_line="== windows check: OK (release profile, stand-in shader compiler)" ;;
  *) echo "SHELLX_WINCHECK_PROFILE must be dev or release: '$SHELLX_WINCHECK_PROFILE'" >&2; exit 1 ;;
esac
# shellcheck source=zig-libc-msvc.sh
source "$here/zig-libc-msvc.sh"

cd /src/windows
rustc --version; cargo-xwin --version; zig version
cargo xwin check ${profile_args[@]+"${profile_args[@]}"} --locked --target x86_64-pc-windows-msvc \
  -p shellx-model -p shellx-remote -p shellx-app --all-targets
echo "$ok_line"
