#!/usr/bin/env bash
# GPUI_FXC_PATH for `scripts/shellx/check-windows-build.sh --release` ONLY. NOT a shader compiler.
#
# gpui's build script compiles its HLSL with fxc.exe only in the release profile, and the Rust
# code that embeds the result (and anything behind cfg(not(debug_assertions))) exists only
# there. This stand-in lets that release-only Rust code be type-checked without wine or the
# Windows SDK: for each `fxc ... /Fh <header> /Vn <name> ...` it writes a header of the shape
# gpui's build script reads, `const BYTE <name>[] = { 68, 88, 66, 67 };` (the 4-byte "DXBC"
# tag, no shader). No real shader is compiled, so nothing built with it may ever be run or
# shipped; the --release mode is `cargo check` and builds no exe, which keeps that true.
# It refuses to run unless check-in-container.sh set SHELLX_WINCHECK_PROFILE=release.
set -euo pipefail
if [[ "${SHELLX_WINCHECK_PROFILE:-}" != release ]]; then
  echo "fxc-standin: refusing: only check-windows-build.sh --release may use this stand-in" \
    "(it compiles no shader; SHELLX_WINCHECK_PROFILE=release is not set)" >&2
  exit 1
fi
header="" name=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    /Fh) header="${2:-}"; shift 2 || shift ;;
    /Vn) name="${2:-}"; shift 2 || shift ;;
    *) shift ;;
  esac
done
if [[ -z "$header" || ! "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "fxc-standin: expected /Fh <header> and /Vn <name>" >&2
  exit 1
fi
printf 'const BYTE %s[] =\n{\n     68,  88,  66,  67\n};\n' "$name" > "$header"
