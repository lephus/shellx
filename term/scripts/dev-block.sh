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

# Prints "<state> <begin-offset> <end-offset>": state is on (begin marker line
# followed later by an end marker line), off (neither marker) or broken
# (anything else). Offsets are bytes, so removal can be byte-exact.
scan() {
  if [ ! -f "$file" ]; then echo "off 0 0"; return; fi
  LC_ALL=C awk -v b="$begin" -v e="$end" '
    { len = length($0) + 1 }
    $0 == b { nb++; if (!bs) bs = pos + 1 }
    $0 == e { ne++; if (bs && !ee) ee = pos + len }
    { pos += len }
    END {
      if (nb == 0 && ne == 0) print "off 0 0"
      else if (nb == 1 && ne == 1 && ee) print "on", bs - 1, ee
      else print "broken 0 0"
    }' "$file"
}

read -r state start stop <<EOF_SCAN
$(scan)
EOF_SCAN

refuse_if_broken() {
  if [ "$state" = broken ]; then
    echo "error: $file has a damaged ShellX block (missing, duplicate or out-of-order markers); leaving it untouched" >&2
    exit 1
  fi
}

case "${1:-}" in
  on)
    refuse_if_broken
    if [ "$state" = on ]; then echo "already on: $file"; exit 0; fi
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
    refuse_if_broken
    if [ "$state" = off ]; then echo "already off: $file"; exit 0; fi
    tmp="$(mktemp)"
    { # BSD head rejects -c 0
      if [ "$start" -gt 0 ]; then head -c "$start" "$file"; fi
      tail -c +"$((stop + 1))" "$file"
    } > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
    echo "off: $file"
    ;;
  status)
    echo "$state"
    ;;
  *)
    echo "usage: $0 on|off|status [file]" >&2
    exit 2
    ;;
esac
