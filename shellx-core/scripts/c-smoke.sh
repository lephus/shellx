#!/bin/sh
# Build the staticlib and link it from a plain C program.
set -eu
cd "$(dirname "$0")/.."
cargo build -p shellx-core --lib --quiet
libs=$(cargo rustc --quiet --lib --crate-type staticlib -- --print native-static-libs 2>&1 \
  | sed -n 's/^note: native-static-libs: //p' | tail -1 \
  | tr ' ' '\n' | awk 'NF && $0 != "-lSystem" && !seen[$0]++' | tr '\n' ' ')
# shellcheck disable=SC2086
clang -Wall -Werror -I include tests/c/smoke.c target/debug/libshellx_core.a $libs -o target/c-smoke
target/c-smoke
