#!/usr/bin/env bash
# Usage: source-tarball.sh <commit-ish> <out-dir>
# Writes <out-dir>/relay2-src-<sha>.tar.gz with the relay2 build inputs only.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <commit-ish> <out-dir>" >&2
  exit 2
fi

repo="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
sha="$(git -C "$repo" rev-parse --verify "$1^{commit}")"
mkdir -p "$2"
out="$(cd "$2" && pwd)/relay2-src-${sha}.tar.gz"
trap '[ "${ok:-0}" = 1 ] || rm -f "$out"' EXIT

git -C "$repo" archive --format=tar.gz --prefix="${sha}/" -o "$out" "$sha" -- \
  cmux-tui/Cargo.toml cmux-tui/Cargo.lock cmux-tui/rust-toolchain.toml \
  cmux-tui/crates cmux-tui/bindings cmux-tui/vendor cmux-tui/build-support \
  scripts/shellx/relay2

if tar -tzf "$out" | grep -q "^${sha}/cmux-tui/relays/"; then
  rm -f "$out"
  echo "archive contains cmux-tui/relays/, refusing" >&2
  exit 1
fi

ok=1
echo "$out"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$out" | cut -d' ' -f1
else
  shasum -a 256 "$out" | cut -d' ' -f1
fi
echo "$sha"
