#!/usr/bin/env bash
# ShellX: build shellx-core as a static library for the cmux app target.
#
# Xcode Run Script phase "ShellX core" (before Compile Sources). Mirrors
# scripts/build-command-palette-nucleo-ffi.sh: Rust targets come from
# TARGET_TRIPLE / ARCHS, each is built with `cargo build --release --locked`, and
# the slices are lipo'd into $(TARGET_BUILD_DIR)/shellx-core/libshellx_core.a,
# which the target links with -lshellx_core (LIBRARY_SEARCH_PATHS) plus the
# frameworks `cargo rustc -- --print native-static-libs` reports (Security,
# CoreFoundation for rustls-platform-verifier).
#
# Unlike the nucleo FFI this library is not optional: a missing cargo fails the
# build instead of skipping it, since the app does not link without it.
#
# Outside Xcode it builds the host slice into shellx-core/target/shellx-core.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CRATE_DIR="${ROOT}/shellx-core"
LIB_NAME="libshellx_core.a"
CARGO_TARGET="${CARGO_TARGET_DIR:-${CRATE_DIR}/target}"
BUILD_OUTPUT_DIR="${TARGET_BUILD_DIR:-${CRATE_DIR}/target}/shellx-core"
# shellcheck source=scripts/build-phase-caller-path.sh
. "${ROOT}/scripts/build-phase-caller-path.sh"

# Xcode exports the app target's deployment target; ring's C/asm objects must be
# built for the same one or ld warns about newer objects. 14.0 = cmux target.
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo is required to build ${LIB_NAME} (install Rust: https://rustup.rs)" >&2
  exit 1
fi

rust_target_for_arch() {
  case "$1" in
    arm64|arm64e) echo "aarch64-apple-darwin" ;;
    x86_64) echo "x86_64-apple-darwin" ;;
    *)
      echo "error: unsupported Rust macOS arch $1" >&2
      return 1
      ;;
  esac
}

rust_target_for_triple() {
  case "$1" in
    aarch64-apple-darwin|x86_64-apple-darwin) echo "$1" ;;
    arm64-*|arm64e-*|aarch64-*) echo "aarch64-apple-darwin" ;;
    x86_64-*) echo "x86_64-apple-darwin" ;;
    *)
      echo "error: unsupported Rust macOS target triple $1" >&2
      return 1
      ;;
  esac
}

ensure_rust_target() {
  local target="$1"
  if command -v rustup >/dev/null 2>&1; then
    if rustup target list --installed | grep -qx "$target"; then
      return
    fi
    rustup target add "$target"
  fi
}

# ARCHS first: a universal Release build lists every slice there, and the link
# step needs all of them in the one library. TARGET_TRIPLE covers callers that
# set only that.
requested_targets=""
if [ -z "${ARCHS:-}" ] && [ -n "${TARGET_TRIPLE:-}" ]; then
  requested_targets="$(rust_target_for_triple "${TARGET_TRIPLE}")"
fi

if [ -z "${requested_targets}" ]; then
  requested_archs="${ARCHS:-}"
  if [ -z "${requested_archs}" ]; then
    case "$(uname -m)" in
      arm64|aarch64) requested_archs="arm64" ;;
      x86_64) requested_archs="x86_64" ;;
      *)
        echo "error: cannot infer Rust macOS target for host arch $(uname -m)" >&2
        exit 1
        ;;
    esac
  fi

  for arch in ${requested_archs}; do
    requested_targets="${requested_targets} $(rust_target_for_arch "$arch")"
  done
fi

mkdir -p "${BUILD_OUTPUT_DIR}"
libs=()
seen_targets=""
for target in ${requested_targets}; do
  case " ${seen_targets} " in
    *" ${target} "*) continue ;;
  esac
  seen_targets="${seen_targets} ${target}"
  ensure_rust_target "$target"
  cargo build --manifest-path "${CRATE_DIR}/Cargo.toml" -p shellx-core --lib \
    --release --locked --target "$target"
  source_lib="${CARGO_TARGET}/${target}/release/${LIB_NAME}"
  if [ ! -f "${source_lib}" ]; then
    echo "error: expected shellx-core library at ${source_lib}" >&2
    exit 1
  fi
  libs+=("${source_lib}")
done

if [ "${#libs[@]}" -eq 0 ]; then
  echo "error: no Rust macOS architectures requested" >&2
  exit 1
fi

# The phase is alwaysOutOfDate (cargo decides what is stale), so replace the
# library only when its bytes changed: an untouched .a keeps its mtime and the
# app is not relinked on every build.
DEST_LIB="${BUILD_OUTPUT_DIR}/${LIB_NAME}"
STAGED_LIB="${BUILD_OUTPUT_DIR}/.${LIB_NAME}.$$"
trap 'rm -f "${STAGED_LIB}"' EXIT
if [ "${#libs[@]}" -eq 1 ]; then
  cp "${libs[0]}" "${STAGED_LIB}"
else
  lipo -create -output "${STAGED_LIB}" "${libs[@]}"
fi
if [ -f "${DEST_LIB}" ] && cmp -s "${STAGED_LIB}" "${DEST_LIB}"; then
  echo "unchanged ${DEST_LIB}"
else
  mv -f "${STAGED_LIB}" "${DEST_LIB}"
  echo "built ${DEST_LIB}"
fi
