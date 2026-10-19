#!/usr/bin/env bash
# Renders design/shellx-logo.svg into Assets.xcassets.
#
#   scripts/shellx/gen_app_icons.sh             -> ShellXLogo.imageset (vector PDF), used by About and the sidebar header
#   scripts/shellx/gen_app_icons.sh --app-icons -> also regenerate the AppIcon / AppIcon-RC / AppIcon-Nightly
#                                                 appiconsets from the SVG (opt-in; overwrites the committed PNGs,
#                                                 does NOT add the DEV band to AppIcon-Debug)
#
# Requires: rsvg-convert (brew install librsvg).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SVG="$ROOT/design/shellx-logo.svg"
XC="$ROOT/Assets.xcassets"

command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found (brew install librsvg)" >&2; exit 1; }
[ -f "$SVG" ] || { echo "missing $SVG" >&2; exit 1; }

# ShellXLogo.imageset: single vector PDF, preserved as vector.
set_dir="$XC/ShellXLogo.imageset"
mkdir -p "$set_dir"
rsvg-convert -f pdf -o "$set_dir/ShellXLogo.pdf" "$SVG"
cat > "$set_dir/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "ShellXLogo.pdf",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true
  }
}
JSON
echo "wrote $set_dir"

if [ "${1:-}" = "--app-icons" ]; then
  for name in AppIcon AppIcon-RC AppIcon-Nightly; do
    dir="$XC/$name.appiconset"
    for f in "$dir"/*.png; do
      px="$(sips -g pixelWidth "$f" | awk '/pixelWidth/ {print $2}')"
      rsvg-convert -w "$px" -h "$px" -o "$f" "$SVG"
    done
    echo "regenerated $dir"
  done
fi
