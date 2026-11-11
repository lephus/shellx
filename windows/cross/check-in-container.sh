#!/usr/bin/env bash
# Compile check of the Windows app for x86_64-pc-windows-msvc: no installer, no exe.
# Runs inside shellx-wincheck (check.Dockerfile, scripts/shellx/check-windows-build.sh) or
# shellx-winbuild (Dockerfile). /src holds windows, cmux-tui, shellx-core and ghostty from
# the checked commit; /cache is the cache volume.
#
# cargo's dev profile: gpui compiles its HLSL shaders only without debug assertions, so this
# needs neither wine nor fxc.exe.
set -euo pipefail

# /src is a git archive, so cmux-remote's build.rs cannot ask git for HEAD: the driver passes
# the exported commit.
[[ "${CMUX_TUI_BUILD_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]] || { echo "set CMUX_TUI_BUILD_COMMIT to the exported commit" >&2; exit 1; }
unset CMUX_GHOSTTY_SRC
export CARGO_TARGET_DIR=/cache/target ZIG_LOCAL_CACHE_DIR=/cache/zig-local
# shellcheck source=zig-libc-msvc.sh
source "$(dirname "${BASH_SOURCE[0]}")/zig-libc-msvc.sh"

cd /src/windows
rustc --version; cargo-xwin --version; zig version
cargo xwin check --locked --target x86_64-pc-windows-msvc -p shellx-model -p shellx-remote -p shellx-app --all-targets
echo "== windows check: OK"
