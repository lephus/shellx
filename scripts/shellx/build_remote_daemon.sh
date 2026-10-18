#!/usr/bin/env bash
# Cross-builds ShellX's SSH remote helper (shellx-remote) for every remote
# platform the app supports, then writes checksums.txt and manifest.json and
# verifies them with scripts/verify_remote_daemon_release.py.
#
#   scripts/shellx/build_remote_daemon.sh <version> [--output-dir <dir>]
#
# Output (default dir dist/shellx-remote/<version>/, git-ignored):
#   shellx-remote-darwin-arm64  shellx-remote-darwin-amd64
#   shellx-remote-linux-arm64   shellx-remote-linux-amd64
#   checksums.txt               manifest.json
#
# The manifest points at https://download.shellx.pro/desktop/shellx-remote/<version>/.
# Uploading the files there is a separate release step (Wave 3); this script
# never touches the network beyond Go's module download.
#
# Go comes from $GO when set, else from PATH.
set -euo pipefail

DOWNLOAD_BASE="https://download.shellx.pro/desktop/shellx-remote"
TARGETS=(
  "darwin arm64"
  "darwin amd64"
  "linux arm64"
  "linux amd64"
)

usage() {
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

VERSION=""
OUTPUT_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "error: unknown option $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$VERSION" ]]; then
        echo "error: unexpected argument $1" >&2
        exit 2
      fi
      VERSION="$1"
      shift
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  usage >&2
  exit 2
fi
# The version is a path segment on the remote host and in the download URL.
if [[ ! "$VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z._-]{0,63}$ ]]; then
  echo "error: invalid version '$VERSION' (letters, digits, '.', '_', '-' only)" >&2
  exit 2
fi

GO_BIN="${GO:-$(command -v go 2>/dev/null || true)}"
if [[ -z "$GO_BIN" || ! -x "$GO_BIN" ]]; then
  echo "error: go not found${GO:+ at GO=$GO}; install Go 1.22 (daemon/remote/go.mod) and put it on PATH, or set GO=/path/to/go" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DAEMON_ROOT="$REPO_ROOT/daemon/remote"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/dist/shellx-remote/$VERSION}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
rm -f "$OUTPUT_DIR"/shellx-remote-* "$OUTPUT_DIR/checksums.txt" "$OUTPUT_DIR/manifest.json"

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

LDFLAGS="-s -w -X main.version=${VERSION}"
PIDS=()
LABELS=()
for target in "${TARGETS[@]}"; do
  read -r goos goarch <<<"$target"
  # The Go package directory keeps upstream's internal name.
  GOOS="$goos" GOARCH="$goarch" CGO_ENABLED=0 \
    "$GO_BIN" -C "$DAEMON_ROOT" build -trimpath -buildvcs=false -ldflags "$LDFLAGS" \
    -o "$OUTPUT_DIR/shellx-remote-${goos}-${goarch}.build" ./cmd/cmuxd-remote &
  PIDS+=("$!")
  LABELS+=("${goos}/${goarch}")
done

FAILED=0
for index in "${!PIDS[@]}"; do
  if ! wait "${PIDS[$index]}"; then
    echo "error: shellx-remote build failed for ${LABELS[$index]}" >&2
    FAILED=1
  fi
done
if [[ "$FAILED" -ne 0 ]]; then
  rm -f "$OUTPUT_DIR"/shellx-remote-*.build
  exit 1
fi

ENTRIES=""
: > "$OUTPUT_DIR/checksums.txt"
for target in "${TARGETS[@]}"; do
  read -r goos goarch <<<"$target"
  name="shellx-remote-${goos}-${goarch}"
  mv "$OUTPUT_DIR/$name.build" "$OUTPUT_DIR/$name"
  chmod 755 "$OUTPUT_DIR/$name"
  digest="$(sha256_of "$OUTPUT_DIR/$name")"
  printf '%s  %s\n' "$digest" "$name" >> "$OUTPUT_DIR/checksums.txt"
  ENTRIES+="${goos} ${goarch} ${name} ${digest}"$'\n'
done

RELEASE_URL="$DOWNLOAD_BASE/$VERSION"
printf '%s' "$ENTRIES" | python3 -c '
import json, sys
version, release_url, path = sys.argv[1:]
entries = []
for line in sys.stdin.read().splitlines():
    go_os, go_arch, name, digest = line.split()
    entries.append({"goOS": go_os, "goArch": go_arch, "assetName": name,
                    "downloadURL": f"{release_url}/{name}", "sha256": digest})
manifest = {"schemaVersion": 1, "appVersion": version, "releaseTag": f"v{version}",
            "releaseURL": release_url, "checksumsAssetName": "checksums.txt",
            "checksumsURL": f"{release_url}/checksums.txt", "entries": entries}
with open(path, "w", encoding="utf-8") as f:
    f.write(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
' "$VERSION" "$RELEASE_URL" "$OUTPUT_DIR/manifest.json"

python3 "$REPO_ROOT/scripts/verify_remote_daemon_release.py" \
  --manifest "$OUTPUT_DIR/manifest.json" --assets-dir "$OUTPUT_DIR"

echo "Built shellx-remote $VERSION in $OUTPUT_DIR (upload to $RELEASE_URL/)"
