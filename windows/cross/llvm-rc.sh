#!/usr/bin/env bash
# RC_x86_64_pc_windows_msvc for embed-resource on a Linux host. embed-resource runs llvm-rc
# in the .rc file's directory (resources/), while rc.exe on Windows inherits the build
# script's cwd, the crate dir; shellx.rc names its files relative to the crate dir
# ("resources/app_icon.ico"). Add the crate dir (CARGO_MANIFEST_DIR, set by cargo for the
# build script) to the search path when compiling; the version probe passes through.
set -euo pipefail
if [[ -n "${CARGO_MANIFEST_DIR:-}" && " $* " == *" /fo "* ]]; then
  exec llvm-rc /I "$CARGO_MANIFEST_DIR" "$@"
fi
exec llvm-rc "$@"
