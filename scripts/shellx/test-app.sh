#!/usr/bin/env bash
# Run app-hosted cmuxTests suites through the cmux-unit scheme.
# Usage: scripts/shellx/test-app.sh <Suite> [<Suite>...]
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: scripts/shellx/test-app.sh <Suite> [<Suite>...]" >&2
  echo "  runs xcodebuild test limited to -only-testing:cmuxTests/<Suite>" >&2
  exit 2
fi

cd "$(dirname "$0")/../.."

args=(test)
for suite in "$@"; do
  args+=("-only-testing:cmuxTests/${suite}")
done

exec scripts/test-unit.sh "${args[@]}"
