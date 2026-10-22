#!/usr/bin/env bash
# License boundary check for shellx-link (MIT package, must not depend on or copy GPL code).
# Exits 1 and prints the offending path when:
#   1. Package.swift has `path:` / `.package(path:` pointing outside shellx-link/
#   2. Package.swift has `.package(url:` (no external dependencies in P1)
#   3. a file under shellx-link/Sources contains the string "Manaflow"
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG="$ROOT/shellx-link"
MANIFEST="$PKG/Package.swift"
fail=0

if [ ! -f "$MANIFEST" ]; then
  echo "missing: $MANIFEST"
  exit 1
fi

# 1. paths escaping the package directory ("../" or absolute)
if grep -nE 'path:\s*"(\.\./|/|~)' "$MANIFEST"; then
  echo "violation: $MANIFEST has a path outside shellx-link/"
  fail=1
fi
# 2. external dependencies
if grep -n '\.package(url:' "$MANIFEST"; then
  echo "violation: $MANIFEST has .package(url:), external dependencies are not allowed in P1"
  fail=1
fi

# 3. Manaflow strings in sources
if [ -d "$PKG/Sources" ]; then
  hits="$(grep -rl 'Manaflow' "$PKG/Sources" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    echo "$hits"
    echo "violation: files above contain 'Manaflow'"
    fail=1
  fi
fi

exit $fail
