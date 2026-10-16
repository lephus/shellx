#!/bin/bash
# Development only: builds shellx-term and puts it where the ShellX block
# looks for it. The ShellX app does this for real (plan P4).
# Usage: dev-install.sh [install|remove]
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
dest="$HOME/Library/Application Support/ShellX/bin"
case "${1:-install}" in
  install)
    cargo build --release --manifest-path "$here/Cargo.toml"
    mkdir -p "$dest"
    cp "$here/target/release/shellx-term" "$dest/shellx-term.tmp"
    mv -f "$dest/shellx-term.tmp" "$dest/shellx-term"
    echo "installed: $dest/shellx-term"
    ;;
  remove)
    rm -f "$dest/shellx-term"
    rmdir "$dest" 2>/dev/null || true
    echo "removed: $dest/shellx-term"
    ;;
  *)
    echo "usage: $0 [install|remove]" >&2
    exit 2
    ;;
esac
