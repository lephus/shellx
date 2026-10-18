#!/usr/bin/env bash
# ShellX: build the cmux-tui client that ships in Contents/Resources/bin from this
# fork's cmux-tui/ sources, and print the absolute path of the built binary.
#
#   scripts/shellx/build-cmux-tui.sh [--release] [--arch native|universal]
#
#   --release   cargo release profile (default: dev profile, for local builds)
#   --arch      native (default): the host slice, built without --target so a
#               shared CARGO_TARGET_DIR stays warm; universal: aarch64 + x86_64
#               apple-darwin slices lipo'd into one binary (release/CI).
#
# Default cargo features only; the cloud transport feature is never enabled.
# The result goes to the app with:
#   CMUX_TUI_CLIENT_LOCAL="$(scripts/shellx/build-cmux-tui.sh)" \
#     CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag <tag>
# ShellX never installs a published upstream client, so a manifest override
# (CMUX_TUI_CLIENT_MANIFEST_URL) is refused with exit 2.
#
# Env: CARGO_TARGET_DIR (default cmux-tui/target), CMUX_GHOSTTY_SRC (default the
# ghostty submodule at the repo root; `git submodule update --init ghostty`).
# Only the path is written to stdout; cargo output goes to stderr.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE="${ROOT}/cmux-tui"

usage() { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//' >&2; }

if [[ -n "${CMUX_TUI_CLIENT_MANIFEST_URL:-}" ]]; then
  echo "error: CMUX_TUI_CLIENT_MANIFEST_URL is set; ShellX bundles a cmux-tui built from this fork only. Unset it." >&2
  exit 2
fi

PROFILE="debug"
ARCH="native"
while (( $# )); do
  case "$1" in
    --release) PROFILE="release" ;;
    --arch)
      shift
      ARCH="${1:-}"
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage; exit 64 ;;
  esac
  shift
done
case "$ARCH" in
  native|universal) ;;
  *) echo "error: --arch must be native or universal, got '${ARCH}'" >&2; exit 64 ;;
esac

command -v cargo >/dev/null 2>&1 || { echo "error: cargo is required to build cmux-tui" >&2; exit 1; }

TARGET_DIR="${CARGO_TARGET_DIR:-${WORKSPACE}/target}"
case "$TARGET_DIR" in
  /*) ;;
  *) TARGET_DIR="${WORKSPACE}/${TARGET_DIR}" ;;  # cargo resolves it against the cwd
esac

# Stamp the source the binary came from (shown by `cmux-tui --version`).
if [[ -z "${CMUX_TUI_BUILD_COMMIT:-}" ]]; then
  CMUX_TUI_BUILD_COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
fi
if [[ -z "${CMUX_TUI_GHOSTTY_COMMIT:-}" && -z "${CMUX_GHOSTTY_SRC:-}" ]]; then
  CMUX_TUI_GHOSTTY_COMMIT="$(git -C "$ROOT/ghostty" rev-parse HEAD 2>/dev/null || true)"
fi
export CMUX_TUI_BUILD_COMMIT CMUX_TUI_GHOSTTY_COMMIT

cargo_args=(build -p cmux-tui --bin cmux-tui --locked)
[[ "$PROFILE" == release ]] && cargo_args+=(--release)

build_slice() { # [<rust-target>]
  local -a args=("${cargo_args[@]}")
  [[ $# -gt 0 ]] && args+=(--target "$1")
  (cd "$WORKSPACE" && cargo "${args[@]}") >&2
}

if [[ "$ARCH" == native ]]; then
  build_slice
  OUT="${TARGET_DIR}/${PROFILE}/cmux-tui"
else
  slices=()
  for target in aarch64-apple-darwin x86_64-apple-darwin; do
    if command -v rustup >/dev/null 2>&1 \
        && ! (cd "$WORKSPACE" && rustup target list --installed) | grep -qx "$target"; then
      (cd "$WORKSPACE" && rustup target add "$target") >&2
    fi
    build_slice "$target"
    slices+=("${TARGET_DIR}/${target}/${PROFILE}/cmux-tui")
  done
  OUT="${TARGET_DIR}/universal-apple-darwin/${PROFILE}/cmux-tui"
  mkdir -p "$(dirname "$OUT")"
  lipo -create -output "$OUT.tmp" "${slices[@]}"
  mv -f "$OUT.tmp" "$OUT"
  for arch in arm64 x86_64; do lipo "$OUT" -verify_arch "$arch"; done
fi

[[ -x "$OUT" ]] || { echo "error: expected cmux-tui at $OUT" >&2; exit 1; }
printf '%s\n' "$OUT"
