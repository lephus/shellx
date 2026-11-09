#!/usr/bin/env bash
# License boundary check for the ShellX Android app (shellx-android/) and ShellX Link for Kotlin
# (shellx-link/kotlin/). Prints `violation: <path>[:<line>]: <message>` per problem and exits 1 when:
#   1. a gradle.lockfile entry is not on scripts/shellx/android-license-allowlist.txt, or is a test-only
#      entry used on a shipped classpath
#   2. a Gradle module has no gradle.lockfile with its runtime classpath
#   3. the allowlist is malformed: duplicate keys, GPL/LGPL/AGPL, unknown scope or licence, stray wildcards,
#      Google SDKs not listed by name
#   4. a *.gradle (Groovy) script exists
#   5. a build script adds a repository other than google() and mavenCentral() (gradlePluginPortal() only in
#      settings.gradle.kts)
#   6. a path in includeBuild/file/files/fileTree/File/srcDir/srcDirs/dir/resolve/resolveSibling/uri/from/
#      apply/Paths.get/Path.of is not a plain string literal, is absolute, is built from the environment, is
#      relative to the daemon's working directory (File("…")), or leaves shellx-android/, shellx-link/kotlin/,
#      shellx-link/vectors/ and shellx-link/spec/ from its anchor: the module folder, the build root
#      (rootProject, rootDir, settingsDir) or, when the receiver is unknown, both; a ".." literal outside these
#      calls is checked from both, and parent/parentFile navigation is refused
#   7. a .jar, .aar or .so file is vendored (gradle-wrapper.jar excepted)
#   8. a text file names the upstream company
#   9. a symlink exists in either tree
#  10. shellx-android/gradle.properties does not set android.builder.sdkDownload=false (AGP would download
#      missing SDK packages; the user installs them with sdkmanager)
# It also runs scripts/shellx/check-link-license.sh. Exit 2 on a usage error.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      if [ $# -lt 2 ]; then echo "usage: check-android-license.sh [--root <repo root>]" >&2; exit 2; fi
      ROOT="$(cd "$2" && pwd)" || exit 2
      shift 2
      ;;
    -h|--help)
      sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "usage: check-android-license.sh [--root <repo root>]" >&2
      exit 2
      ;;
  esac
done

fail=0
if ! python3 -I "$SCRIPT_DIR/check_android_license.py" --root "$ROOT"; then
  fail=1
fi

if ! link_out="$(bash "$SCRIPT_DIR/check-link-license.sh" 2>&1)"; then
  echo "$link_out"
  echo "violation: shellx-link: scripts/shellx/check-link-license.sh failed"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "check-android-license: ok"
