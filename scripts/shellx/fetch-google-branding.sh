#!/usr/bin/env bash
# Download Google's official "G" mark (and, if its licence allows, Google Sans Medium) for the
# "Continue with Google" button of the Mac and Windows apps.
#
# RUN BY THE USER, after reading https://developers.google.com/identity/branding-guidelines and
# the Google terms it links, and accepting them. The mark is Google's trademark; never copy a Google
# logo from anywhere else and never draw one.
#
# Usage: scripts/shellx/fetch-google-branding.sh
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo"
work="$(mktemp -d "${TMPDIR:-/tmp}/shellx-google-branding.XXXXXX")"
trap 'rm -rf "$work"' EXIT

echo "1/6 downloading signin-assets.zip"
curl -fsSL -o "$work/signin-assets.zip" https://developers.google.com/static/identity/images/signin-assets.zip
unzip -q "$work/signin-assets.zip" -d "$work/assets"

echo "2/6 cropping the official 20x20 G box (80x80 at 4x)"
src="$work/assets/Android + Web/PNG @4x/Light/Theme=Light, Show text=No, Shape=Square, Platform=Android+Web@4x.png"
[[ -f "$src" ]] || { echo "error: expected icon not found in the zip" >&2; exit 1; }
dims="$(sips -g pixelWidth -g pixelHeight "$src")"
grep -q 'pixelWidth: 160' <<<"$dims" && grep -q 'pixelHeight: 160' <<<"$dims" \
  || { echo "error: the icon is not 160x160 px" >&2; exit 1; }
sips -c 80 80 --cropOffset 40 40 "$src" --out "$work/google-g.png" >/dev/null

echo "3/6 writing the Mac image set"
mkdir -p Assets.xcassets/GoogleG.imageset
cp "$work/google-g.png" Assets.xcassets/GoogleG.imageset/google-g.png
cat > Assets.xcassets/GoogleG.imageset/Contents.json <<'JSON'
{
  "images" : [
    {
      "filename" : "google-g.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo "4/6 writing the Windows mark"
mkdir -p windows/shellx-app/assets/google
cp "$work/google-g.png" windows/shellx-app/assets/google/google-g.png

echo "5/6 Google Sans Medium licence gate"
curl -fsSL -o "$work/OFL.txt" https://raw.githubusercontent.com/google/fonts/main/ofl/googlesans/OFL.txt
if grep -q 'SIL Open Font License, Version 1.1' "$work/OFL.txt"; then
  curl -fsSL -o "$work/list.txt" 'https://fonts.google.com/download/list?family=Google%20Sans'
  url="$(tail -n +2 "$work/list.txt" | python3 -c '
import json, sys
for ref in json.load(sys.stdin)["manifest"]["fileRefs"]:
    if ref["filename"] == "static/GoogleSans-Medium.ttf":
        print(ref["url"])
        break')"
  [[ -n "$url" ]] || { echo "error: GoogleSans-Medium.ttf not in the download list" >&2; exit 1; }
  curl -fsSL -o "$work/GoogleSans-Medium.ttf" "$url"
  [[ "$(head -c 4 "$work/GoogleSans-Medium.ttf" | xxd -p)" == "00010000" ]] \
    || { echo "error: the downloaded font is not a TrueType file" >&2; exit 1; }
  for dir in Resources/Fonts windows/shellx-app/assets/fonts; do
    mkdir -p "$dir"
    cp "$work/GoogleSans-Medium.ttf" "$dir/GoogleSans-Medium.ttf"
    cp "$work/OFL.txt" "$dir/GoogleSans-OFL.txt"
  done
else
  echo "font: licence not confirmed; the button keeps the system font"
fi

echo "6/6 checking"
python3 scripts/shellx/check-google-branding.py
