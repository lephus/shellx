#!/bin/sh
# Build the staticlib and link it from a plain C program.
set -eu
cd "$(dirname "$0")/.."
# ring compiles C/asm via cc; build and link for the same macOS target as the app
# (cmux.xcodeproj MACOSX_DEPLOYMENT_TARGET) so ld does not warn about newer objects.
if [ "$(uname -s)" = Darwin ]; then
  MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
  export MACOSX_DEPLOYMENT_TARGET
fi
cargo build -p shellx-core --lib --quiet
# Capture first so a failing `cargo rustc` aborts (set -e); no pipe masks its status.
rustc_out=$(cargo rustc --quiet --lib --crate-type staticlib -- --print native-static-libs 2>&1)
# Keep `-framework X` pairs together (rustls-platform-verifier links Security and
# CoreFoundation); drop duplicates and the implicit -lSystem.
libs=$(printf '%s\n' "$rustc_out" | sed -n 's/^note: native-static-libs: //p' | tail -1 \
  | awk '{ out = ""; for (i = 1; i <= NF; i++) { t = $i; if (t == "-framework" && i < NF) { i++; t = t " " $i }
           if (t != "-lSystem" && !seen[t]++) out = out t " " } print out }')
# shellcheck disable=SC2086
clang -Wall -Werror -I include tests/c/smoke.c target/debug/libshellx_core.a $libs -o target/c-smoke
target/c-smoke
