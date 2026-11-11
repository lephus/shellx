#!/usr/bin/env bash
# Checks windows/vendor/gpui-0.2.2 against the published gpui-0.2.2.crate (see README.md):
# every file must equal the crate's, except the patched files, and the patched files must be
# exactly those whose first line is the Apache-2.0 §4(b) notice "// Modified by ShellX: ...".
# Prints "gpui-0.2.2: pristine" or "gpui-0.2.2: N patched file(s): <list>"; exit 1 otherwise.
set -euo pipefail
export LC_ALL=C

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
copy="$here/gpui-0.2.2"
# Hard-coded: windows/Cargo.lock no longer carries gpui's checksum once it is a path dependency.
crate_sha256=979b45cfa6ec723b6f42330915a1b3769b930d02b2d505f9697f8ca602bee707
notice='// Modified by ShellX:'

[[ -d "$copy" ]] || { echo "check-gpui: $copy is missing" >&2; exit 1; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-gpui.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

crate=""
for c in "${CARGO_HOME:-$HOME/.cargo}"/registry/cache/*/gpui-0.2.2.crate; do
  if [[ -f "$c" ]]; then crate="$c"; break; fi
done
if [[ -z "$crate" ]]; then
  crate="$tmp/gpui-0.2.2.crate"
  curl -sSfL -o "$crate" https://static.crates.io/crates/gpui/gpui-0.2.2.crate
fi
actual="$(shasum -a 256 "$crate" | awk '{print $1}')"
[[ "$actual" == "$crate_sha256" ]] || { echo "check-gpui: $crate has sha256 $actual, expected $crate_sha256" >&2; exit 1; }
mkdir "$tmp/crate"
tar -xzf "$crate" -C "$tmp/crate"
orig="$tmp/crate/gpui-0.2.2"

(cd "$orig" && find . ! -type d | sed 's|^\./||' | sort) > "$tmp/orig.list"
(cd "$copy" && find . ! -type d | sed 's|^\./||' | sort) > "$tmp/copy.list"
fail=0
while IFS= read -r f; do
  echo "check-gpui: only in the crate: $f" >&2; fail=1
done < <(comm -23 "$tmp/orig.list" "$tmp/copy.list")
while IFS= read -r f; do
  echo "check-gpui: only in the copy: $f" >&2; fail=1
done < <(comm -13 "$tmp/orig.list" "$tmp/copy.list")

: > "$tmp/differ.list"
: > "$tmp/notice.list"
while IFS= read -r f; do
  cmp -s "$orig/$f" "$copy/$f" || echo "$f" >> "$tmp/differ.list"
done < <(comm -12 "$tmp/orig.list" "$tmp/copy.list")
while IFS= read -r f; do
  start="$(head -c "${#notice}" "$copy/$f" | tr -d '\000')"
  [[ "$start" != "$notice" ]] || echo "$f" >> "$tmp/notice.list"
done < "$tmp/copy.list"
while IFS= read -r f; do
  echo "check-gpui: differs from the crate without the notice line: $f" >&2; fail=1
done < <(comm -23 "$tmp/differ.list" "$tmp/notice.list")
while IFS= read -r f; do
  echo "check-gpui: carries the notice line but equals the crate (or is not in it): $f" >&2; fail=1
done < <(comm -13 "$tmp/differ.list" "$tmp/notice.list")
[[ $fail -eq 0 ]] || exit 1

count="$(wc -l < "$tmp/differ.list" | tr -d ' ')"
if [[ "$count" -eq 0 ]]; then
  echo "gpui-0.2.2: pristine"
else
  echo "gpui-0.2.2: $count patched file(s): $(paste -sd ' ' "$tmp/differ.list")"
fi
