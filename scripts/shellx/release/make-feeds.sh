#!/usr/bin/env bash
# Write the update feeds of one ShellX desktop release next to its installers:
#   appcast.xml         Sparkle feed (https://download.shellx.pro/desktop/appcast.xml), EdDSA-signed
#   latest-macos.json   read by the relay for GET /v1/version (K6 shape)
#   latest-windows.json
#   SHA256SUMS          checked by .github/workflows/shellx-publish.yml before upload
#
# Usage: scripts/shellx/release/make-feeds.sh <ShellX.app> <version> <dir> <sparkle-bin-dir>
#   <dir> holds ShellX-<version>.dmg and ShellX-Setup-<version>.exe. <sparkle-bin-dir> is the bin/
#   folder of the Sparkle 2.8.1 release tarball (sign_update). The private key never leaves the
#   login keychain: sign_update reads it from the account in SHELLX_SPARKLE_ACCOUNT (default shellx).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ $# -eq 4 ]] || { echo "usage: $0 <ShellX.app> <version> <dir> <sparkle-bin-dir>" >&2; exit 2; }
app="$1" version="$2" dir="$3" sparkle_bin="$4"
account="${SHELLX_SPARKLE_ACCOUNT:-shellx}"
dmg="$dir/ShellX-$version.dmg"
exe="$dir/ShellX-Setup-$version.exe"
for f in "$dmg" "$exe"; do [[ -f "$f" ]] || { echo "error: $f not found" >&2; exit 1; }; done

plist="$app/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" == "$version" ]] \
  || { echo "error: $app is not version $version" >&2; exit 1; }
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
min_os="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")"

# The key in the keychain must be the one the app verifies updates with.
app_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")"
keychain_key="$("$sparkle_bin/generate_keys" --account "$account" -p)"
[[ "$app_key" == "$keychain_key" && "$app_key" == "$(tr -d '[:space:]' < "$SCRIPT_DIR/sparkle-ed25519.pub")" ]] \
  || { echo "error: SUPublicEDKey of $app, the keychain key ($account) and sparkle-ed25519.pub differ" >&2; exit 1; }

# Prints: sparkle:edSignature="..." length="..."
signature="$("$sparkle_bin/sign_update" --account "$account" "$dmg")"
"$sparkle_bin/sign_update" --account "$account" --verify "$dmg" "$(sed -E 's/.*edSignature="([^"]+)".*/\1/' <<<"$signature")" >/dev/null

DIR="$dir" VERSION="$version" BUILD="$build" MIN_OS="$min_os" SIGNATURE="$signature" python3 - <<'EOF'
import email.utils, hashlib, json, os, time
d, v = os.environ["DIR"], os.environ["VERSION"]
base = f"https://download.shellx.pro/desktop/{v}/"
now = int(time.time())

def sha(name):
    return hashlib.sha256(open(os.path.join(d, name), "rb").read()).hexdigest()

appcast = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>ShellX</title>
    <link>https://download.shellx.pro/desktop/appcast.xml</link>
    <language>vi</language>
    <item>
      <title>ShellX {v}</title>
      <pubDate>{email.utils.formatdate(now, usegmt=True)}</pubDate>
      <sparkle:version>{os.environ["BUILD"]}</sparkle:version>
      <sparkle:shortVersionString>{v}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{os.environ["MIN_OS"]}</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/lephus/shellx/releases/tag/shellx-v{v}</sparkle:releaseNotesLink>
      <enclosure url="{base}ShellX-{v}.dmg" {os.environ["SIGNATURE"].strip()} type="application/octet-stream"/>
    </item>
  </channel>
</rss>
"""
open(os.path.join(d, "appcast.xml"), "w").write(appcast)

for platform, name, min_os in (("macos", f"ShellX-{v}.dmg", os.environ["MIN_OS"]),
                               ("windows", f"ShellX-Setup-{v}.exe", "10.0.17763")):
    manifest = {"version": v, "url": base + name, "sha256": sha(name), "min_os": min_os,
                "published_at_unix": now}
    with open(os.path.join(d, f"latest-{platform}.json"), "w") as f:
        json.dump(manifest, f, separators=(",", ":"))
        f.write("\n")

names = [f"ShellX-{v}.dmg", f"ShellX-Setup-{v}.exe", "appcast.xml", "latest-macos.json", "latest-windows.json"]
with open(os.path.join(d, "SHA256SUMS"), "w") as f:
    for name in names:
        f.write(f"{sha(name)}  {name}\n")
print("\n".join(os.path.join(d, n) for n in names + ["SHA256SUMS"]))
EOF
