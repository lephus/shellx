#!/usr/bin/env bash
# Run app-hosted cmuxTests suites through the cmux-unit scheme.
# Usage: scripts/shellx/test-app.sh <Suite> [<Suite>...] [-- <extra xcodebuild args>...]
# Arguments after a `--` separator are forwarded to xcodebuild unchanged.
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: scripts/shellx/test-app.sh <Suite> [<Suite>...]" >&2
  echo "  runs xcodebuild test limited to -only-testing:cmuxTests/<Suite>" >&2
  exit 2
fi

cd "$(dirname "$0")/../.."

args=(test)
extra=()
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--" ]; then
    shift
    extra=("$@")
    break
  fi
  args+=("-only-testing:cmuxTests/$1")
  shift
done

exec scripts/test-unit.sh "${args[@]}" ${extra[@]+"${extra[@]}"}
