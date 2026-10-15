#!/usr/bin/env bash
# Builds the Play Store app bundle (.aab) of apps/mobile signed with the ShellX upload key, and
# checks that signature. Upload the file in Play Console. See release/mobile/README.md.
# Usage: release/mobile/android.sh
set -euo pipefail

APPLICATION_ID=com.shellx.prod

repo="$(cd "$(dirname "$0")/../.." && pwd)"
app="$repo/apps/mobile"
version="$(sed -n 's/^version:[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$app/pubspec.yaml")"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
  echo "error: apps/mobile/pubspec.yaml version '$version' is not X.Y.Z+N" >&2
  exit 1
fi

# The upload key's properties file (storeFile, storePassword, keyAlias, keyPassword); build.gradle.kts
# reads the same variable. Without it Gradle would debug-sign, which Play refuses.
export SHELLX_ANDROID_KEY_PROPERTIES="${SHELLX_ANDROID_KEY_PROPERTIES:-$HOME/.shellx-release/key.properties}"
if [[ ! -f "$SHELLX_ANDROID_KEY_PROPERTIES" ]]; then
  echo "error: no upload key properties at $SHELLX_ANDROID_KEY_PROPERTIES (release/mobile/README.md)" >&2
  exit 1
fi
prop() { sed -n "s/^$1=//p" "$SHELLX_ANDROID_KEY_PROPERTIES"; }

echo "==> ShellX Android ${version%%+*} (${version#*+})"
cd "$app"
rm -rf build/app/outputs/bundle/release
flutter build appbundle --release
aab="$app/build/app/outputs/bundle/release/app-release.aab"

# The bundle must carry the upload certificate, not the debug one.
sha256() { awk '$1 == "SHA256:" { print $2; exit }'; }
expected="$(SHELLX_STOREPASS="$(prop storePassword)" keytool -list -v -keystore "$(prop storeFile)" \
  -alias "$(prop keyAlias)" -storepass:env SHELLX_STOREPASS | sha256)"
actual="$(keytool -printcert -jarfile "$aab" | sha256)"
if [[ -z "$expected" || "$actual" != "$expected" ]]; then
  echo "error: $aab is signed by ${actual:-nothing}, expected the upload key ${expected:-?}" >&2
  exit 1
fi

out="$repo/build/release/ShellX-$APPLICATION_ID-$version.aab"
mkdir -p "$(dirname "$out")"
cp "$aab" "$out"
echo "==> $out (upload key $expected)"
echo "Play Console → ShellX → Testing → Internal testing → Create new release → upload this file."
