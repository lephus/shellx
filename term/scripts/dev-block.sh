#!/bin/bash
# Development only: adds or removes the ShellX block at the top of a shell
# startup file, keeping a one-time backup. The ShellX app does this for real
# (plan P4). Writes through symlinks so dotfile managers keep working.
# Usage: dev-block.sh on|off|status [file]   (default file: ~/.zshrc)
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
file="${2:-$HOME/.zshrc}"
case "$(basename "$file")" in
  *bash*) block="$here/shell/block.bash" ;;
  *) block="$here/shell/block.zsh" ;;
esac
begin='# >>> ShellX >>>'
end='# <<< ShellX <<<'

has_block() {
  [ -f "$file" ] && grep -qxF "$begin" "$file"
}

case "${1:-}" in
  on)
    if has_block; then echo "already on: $file"; exit 0; fi
    tmp="$(mktemp)"
    cat "$block" > "$tmp"
    if [ -f "$file" ]; then
      if [ ! -e "$file.shellx-backup" ]; then cp -p "$file" "$file.shellx-backup"; fi
      cat "$file" >> "$tmp"
    fi
    cat "$tmp" > "$file"
    rm -f "$tmp"
    echo "on: $file"
    ;;
  off)
    if ! has_block; then echo "already off: $file"; exit 0; fi
    tmp="$(mktemp)"
    awk -v b="$begin" -v e="$end" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' "$file" > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
    echo "off: $file"
    ;;
  status)
    if has_block; then echo on; else echo off; fi
    ;;
  *)
    echo "usage: $0 on|off|status [file]" >&2
    exit 2
    ;;
esac
