"""Tests for release/mobile/android.sh (plan 3H): gating, signature, outputs, --check-aab and --mark-uploaded.

Each test clones a throwaway repository from a bare origin. Gradle, bundletool, keytool, jarsigner and java are
fakes; curl and wget are fakes that record any call. The real bundle checker runs.
Run: python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests -v
"""
from __future__ import annotations

import datetime
import json
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
MOBILE = REPO / "release" / "mobile"
STORE_PW = 'st$re pw"=1'
KEY_PW = "k3y pw 'x'"
UPLOAD_SHA256 = ":".join(["15", "1C", "F3", "98"] + ["AB"] * 26 + ["5A", "06"])
UPLOAD_SHA1 = ":".join(["CD"] * 20)
OTHER_SHA256 = ":".join(["EE"] * 32)
APP_ID = "1:111111111111:android:2222222222222222"
WEB_ID = "123456789012-abcdefghij0123456789abcdefghij01.apps.googleusercontent.com"
MAPPING = (b"# compiler: R8\ncom.shellx.app.MainActivity -> com.shellx.app.MainActivity:\n"
           b"com.shellx.core.demo.DemoScript -> a.a:\n")
NAME = "ShellX-1.2.3-105"

FAKE_GRADLEW = """#!/usr/bin/env bash
# Fake Gradle wrapper: records its arguments and the key file, then writes the bundle and the R8 mapping.
set -eu
dir="$(cd "$(dirname "$0")" && pwd)"
{ printf 'args=%s\\n' "$*"; printf 'key=%s\\n' "${SHELLX_ANDROID_KEY_PROPERTIES:-}"; } >>"$FIXTURE_GRADLE_LOG"
mkdir -p "$dir/app/build/outputs/bundle/release" "$dir/app/build/outputs/mapping/release"
cp "$FIXTURE_AAB" "$dir/app/build/outputs/bundle/release/app-release.aab"
cp "$FIXTURE_MAPPING" "$dir/app/build/outputs/mapping/release/mapping.txt"
echo "BUILD SUCCESSFUL in 1s"
"""
FAKE_BUNDLETOOL = """#!/usr/bin/env bash
case "$1 ${2:-}" in
  "version "*) echo "${FAKE_BUNDLETOOL_VERSION:-1.18.3}" ;;
  "dump manifest") cat "$FIXTURE_MANIFEST" ;;
  "dump config") cat "$FIXTURE_CONFIG" ;;
  *) echo "fake bundletool: unexpected $*" >&2; exit 2 ;;
esac
"""
FAKE_KEYTOOL = """#!/usr/bin/env bash
# Fake keytool: -list needs the store password in SHELLX_STOREPASS; -printcert shows the signer of the bundle.
printf '%s\\n' "$*" >>"$FIXTURE_KEYTOOL_LOG"
case " $* " in
  *" -printcert "*)
    printf 'Signer #1:\\n\\nCertificate #1:\\nOwner: %s\\nCertificate fingerprints:\\n\\t SHA1: %s\\n\\t SHA256: %s\\n' \\
      "${FAKE_SIGNER_OWNER:-CN=ShellX Upload}" "$FIXTURE_UPLOAD_SHA1" "${FAKE_SIGNER_SHA256:-$FIXTURE_UPLOAD_SHA256}" ;;
  *" -list "*)
    if [ "${SHELLX_STOREPASS:-}" != "$FIXTURE_STORE_PW" ]; then
      echo "keytool error: java.io.IOException: keystore password was incorrect" >&2; exit 1
    fi
    printf 'Alias name: upload\\nCertificate fingerprints:\\n\\t SHA1: %s\\n\\t SHA256: %s\\n' \\
      "$FIXTURE_UPLOAD_SHA1" "$FIXTURE_UPLOAD_SHA256" ;;
  *) echo "fake keytool: unexpected $*" >&2; exit 2 ;;
esac
"""
FAKE_JARSIGNER = "#!/usr/bin/env bash\necho\necho 'jar verified.'\n"  # the JDK 17 tool prints a blank line first
FAKE_JAVA = "#!/usr/bin/env bash\necho 'openjdk version \"17.0.9\" 2023-10-17' >&2\n"
FAKE_NETWORK = "#!/usr/bin/env bash\necho \"$(basename \"$0\") $*\" >>\"$FIXTURE_NETWORK_LOG\"\nexit 1\n"
FAKE_LICENCE = ("#!/usr/bin/env bash\nif [ -n \"${FAKE_LICENCE_FAIL:-}\" ]; then echo 'violation: x: y'; exit 1; fi\n"
                "echo 'check-android-license: ok'\n")


def write(path: Path, text: str, mode: int = 0o644) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    path.chmod(mode)
    return path


def permissions():
    lines = (MOBILE / "android-permissions.txt").read_text(encoding="utf-8").splitlines()
    return [line.split("#", 1)[0].strip() for line in lines if line.split("#", 1)[0].strip()]


def manifest_xml(debuggable=False):
    perms = "".join('<uses-permission android:name="%s"/>' % p for p in permissions())
    extra = ' android:debuggable="true"' if debuggable else ""
    return ('<manifest xmlns:android="http://schemas.android.com/apk/res/android" android:versionCode="105" '
            'android:versionName="1.2.3" package="com.shellx.prod"><uses-sdk android:minSdkVersion="26" '
            'android:targetSdkVersion="36"/>%s<application android:allowBackup="false"%s>'
            '<activity android:name="com.shellx.app.MainActivity" android:exported="true"/></application>'
            '</manifest>' % (perms, extra))


def oauth_xml(value):
    return ('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <string name="google_web_client_id" '
            'translatable="false">%s</string>\n</resources>\n' % value)


class Fixture:
    def __init__(self, test: unittest.TestCase):
        self.tmp = Path(tempfile.mkdtemp(prefix="android-sh-"))
        test.addCleanup(shutil.rmtree, self.tmp, True)
        t = self.tmp
        self.home, self.tools, self.jdk, self.keys = t / "home", t / "tools", t / "jdk", t / "keys"
        self.home.mkdir()
        for name, text in (("bundletool", FAKE_BUNDLETOOL), ("curl", FAKE_NETWORK), ("wget", FAKE_NETWORK)):
            write(self.tools / name, text, 0o755)
        for name, text in (("java", FAKE_JAVA), ("keytool", FAKE_KEYTOOL), ("jarsigner", FAKE_JARSIGNER)):
            write(self.jdk / "bin" / name, text, 0o755)
        write(self.keys / "upload.jks", "not a real keystore\n")
        self.key_properties = write(self.keys / "key.properties", "storeFile=upload.jks\nstorePassword=%s\n"
                                    "keyAlias=upload\nkeyPassword=%s\n" % (STORE_PW, KEY_PW), 0o600)
        write(t / "manifest.xml", manifest_xml())
        write(t / "config.json", '{"optimizations": {"uncompressNativeLibraries": {"enabled": true}}}')
        (t / "mapping.txt").write_bytes(MAPPING)
        self.aab = t / "fixture.aab"
        with zipfile.ZipFile(self.aab, "w") as z:
            z.writestr("base/manifest/AndroidManifest.xml", b"proto")
            z.writestr("base/dex/classes.dex", b"dex\n035\x00Lcom/shellx/app/MainActivity;")
            z.writestr("base/resources.pb", b"\x0a\x20" + APP_ID.encode() + b"\x12" + WEB_ID.encode() + b"\x1a\x0bic_google_g"
                       + b"\x22\x14third_party_licenses\x2a\x1cthird_party_license_metadata")
            z.writestr("BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map", MAPPING)
        self.repo = t / "repo"
        self.git_env = {"PATH": os.environ["PATH"], "HOME": str(self.home), "GIT_CONFIG_NOSYSTEM": "1",
                        "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
                        "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com"}
        self.git("init", "-q", "--bare", str(t / "origin.git"), cwd=t)
        self.git("clone", "-q", str(t / "origin.git"), str(self.repo), cwd=t)
        self.git("checkout", "-q", "-b", "develop")
        self.populate()
        self.commit_and_push("fixture")

    def git(self, *args, cwd=None):
        return subprocess.run(["git", *args], cwd=cwd or self.repo, env=self.git_env, check=True,
                              capture_output=True, text=True).stdout

    def populate(self):
        r = self.repo
        for name in ("android.sh", "check_android_bundle.py", "android-play-target-sdk.txt", "android-permissions.txt"):
            write(r / "release" / "mobile" / name, (MOBILE / name).read_text(encoding="utf-8"), 0o755)
        rules = r / "release" / "mobile" / "android-play-target-sdk.txt"   # a rule dated today: never stale (365 days)
        rules.write_text(rules.read_text(encoding="utf-8") + "%s 36\n" % datetime.date.today().isoformat(), encoding="utf-8")
        write(r / ".gitignore", "build/\n")
        write(r / "shellx-android/version.properties", "VERSION_NAME=1.2.3\nVERSION_CODE=105\n")
        write(r / "shellx-android/gradle/libs.versions.toml", '[versions]\nandroidTargetSdk = "36"\n')
        write(r / "shellx-android/gradlew", FAKE_GRADLEW, 0o755)
        write(r / "shellx-android/app/gradle.lockfile",
              "com.google.firebase:firebase-messaging:24.1.0=releaseRuntimeClasspath\nempty=\n")
        write(r / "shellx-android/app/google-services.json", json.dumps(
            {"project_info": {"project_id": "shellxpro"}, "client": [{"client_info": {
                "mobilesdk_app_id": APP_ID, "android_client_info": {"package_name": "com.shellx.prod"}}}]}))
        write(r / "shellx-android/app/src/main/res/values/google_oauth.xml", oauth_xml(WEB_ID))
        write(r / "shellx-android/app/src/main/AndroidManifest.xml", "<manifest/>\n")
        write(r / "shellx-ios/Config/Version.xcconfig", "MARKETING_VERSION = 1.2.3\nCURRENT_PROJECT_VERSION = 7\n")
        write(r / "scripts/shellx/check-android-license.sh", FAKE_LICENCE, 0o755)
        for name in ("check_android_license.py", "android-license-allowlist.txt", "check-link-license.sh"):
            write(r / "scripts/shellx" / name, "# placeholder\n")
        write(r / "shellx-link/README.md", "placeholder\n")
        write(r / "docs/README.md", "placeholder\n")

    def commit_and_push(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)
        self.git("push", "-q", "origin", "HEAD:develop")

    def env(self, **extra):
        t = self.tmp
        env = {"PATH": "%s:/usr/bin:/bin:/usr/sbin:/sbin" % self.tools, "HOME": str(self.home), "LANG": "C",
               "GIT_CONFIG_NOSYSTEM": "1", "JAVA_HOME": str(self.jdk),
               "SHELLX_ANDROID_KEY_PROPERTIES": str(self.key_properties),
               "FIXTURE_AAB": str(self.aab), "FIXTURE_MAPPING": str(t / "mapping.txt"),
               "FIXTURE_MANIFEST": str(t / "manifest.xml"), "FIXTURE_CONFIG": str(t / "config.json"),
               "FIXTURE_GRADLE_LOG": str(t / "gradle.log"), "FIXTURE_KEYTOOL_LOG": str(t / "keytool.log"),
               "FIXTURE_NETWORK_LOG": str(t / "network.log"), "FIXTURE_STORE_PW": STORE_PW,
               "FIXTURE_UPLOAD_SHA256": UPLOAD_SHA256, "FIXTURE_UPLOAD_SHA1": UPLOAD_SHA1}
        env.update(extra)
        return env

    def run(self, *args, cwd=None, env=None, **extra):
        return subprocess.run(["bash", str(self.repo / "release/mobile/android.sh"), *args], cwd=cwd or self.repo,
                              env=env or self.env(**extra), capture_output=True, text=True)


class AndroidShTest(unittest.TestCase):
    def setUp(self):
        self.f = Fixture(self)
        self.out = self.f.repo / "build" / "release" / "android"

    def assertRefused(self, result, text):
        self.assertEqual(1, result.returncode, result.stdout + result.stderr)
        self.assertIn(text, result.stderr)
        self.assertFalse((self.out / (NAME + ".aab")).exists())

    def test_build_writes_the_checked_bundle_its_mapping_and_its_source(self):
        r = self.f.run()
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertEqual(self.f.aab.read_bytes(), (self.out / (NAME + ".aab")).read_bytes())
        self.assertEqual(MAPPING, (self.out / (NAME + ".mapping.txt")).read_bytes())
        head = self.f.git("rev-parse", "HEAD").strip()
        self.assertEqual(head + " clean\n", (self.out / (NAME + ".source")).read_text())
        self.assertIn("bundle checks passed: com.shellx.prod 1.2.3 (105)", r.stdout)
        self.assertIn("==> upload key: SHA-256 %s (SHA-1 %s)" % (UPLOAD_SHA256, UPLOAD_SHA1), r.stdout)
        self.assertIn("Not uploaded.", r.stdout)
        gradle = (self.f.tmp / "gradle.log").read_text()
        self.assertIn("--no-configuration-cache", gradle)
        self.assertIn(":app:bundleRelease", gradle)
        self.assertIn("key=" + str(self.f.key_properties), gradle)
        keytool = (self.f.tmp / "keytool.log").read_text()
        self.assertIn("-storepass:env SHELLX_STOREPASS", keytool)
        self.assertIn("-keystore " + str(self.f.keys / "upload.jks"), keytool)
        for secret in (STORE_PW, KEY_PW):
            self.assertNotIn(secret, r.stdout + r.stderr + keytool + gradle)
        self.assertFalse((self.f.tmp / "network.log").exists())

    def test_refuses_uncommitted_and_untracked_changes_in_the_sources(self):
        write(self.f.repo / "shellx-android/version.properties", "VERSION_NAME=1.2.3\nVERSION_CODE=106\n")
        self.assertRefused(self.f.run(), "uncommitted changes in shellx-android/, shellx-link/, release/mobile/ "
                                         "or the licence check")
        self.f.git("checkout", "--", "shellx-android/version.properties")
        write(self.f.repo / "release/mobile/notes.txt", "draft\n")
        self.assertRefused(self.f.run(), "?? release/mobile/notes.txt")
        self.assertFalse((self.f.tmp / "gradle.log").exists())

    def test_changes_outside_the_sources_do_not_matter(self):
        write(self.f.repo / "docs/README.md", "changed\n")
        write(self.f.repo / "docs/new.md", "new\n")
        r = self.f.run()
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)

    def test_refuses_a_commit_that_is_not_on_origin(self):
        write(self.f.repo / "shellx-android/app/src/main/AndroidManifest.xml", "<manifest> </manifest>\n")
        self.f.git("commit", "-q", "-am", "local only")
        head = self.f.git("rev-parse", "HEAD").strip()
        self.assertRefused(self.f.run(), "HEAD %s is not on origin/develop or origin/main" % head)

    def test_accepts_a_detached_pushed_head_run_from_a_subdirectory(self):
        self.f.git("checkout", "-q", "--detach", "HEAD")
        r = self.f.run(cwd=self.f.repo / "shellx-android")
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertTrue((self.out / (NAME + ".aab")).is_file())

    def test_refuses_when_origin_cannot_be_fetched(self):
        self.f.git("remote", "set-url", "origin", str(self.f.tmp / "missing.git"))
        self.assertRefused(self.f.run(), "could not fetch origin")

    def test_refuses_a_missing_shared_or_incomplete_key_file(self):
        missing = self.f.tmp / "nope.properties"
        self.assertRefused(self.f.run(SHELLX_ANDROID_KEY_PROPERTIES=str(missing)),
                           "no upload key properties at %s" % missing)
        self.f.key_properties.chmod(0o644)
        self.assertRefused(self.f.run(), "is readable by other users; run: chmod 600 %s" % self.f.key_properties)
        write(self.f.key_properties, "storeFile=upload.jks\nkeyAlias=upload\n", 0o600)
        self.assertRefused(self.f.run(), "lacks storePassword")

    def test_store_file_may_be_relative_under_home_or_absolute(self):
        release_dir = self.f.home / ".shellx-release"
        write(release_dir / "shellx-upload.jks", "not a real keystore\n")
        write(release_dir / "key.properties", "storeFile=~/.shellx-release/shellx-upload.jks\nstorePassword=%s\n"
              "keyAlias=upload\nkeyPassword=%s\n" % (STORE_PW, KEY_PW), 0o600)
        env = self.f.env()
        del env["SHELLX_ANDROID_KEY_PROPERTIES"]  # the default: ~/.shellx-release/key.properties
        r = self.f.run(env=env)
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertIn("-keystore %s" % (release_dir / "shellx-upload.jks"), (self.f.tmp / "keytool.log").read_text())
        self.assertIn("key=%s" % (release_dir / "key.properties"), (self.f.tmp / "gradle.log").read_text())
        write(self.f.key_properties, "storeFile=%s\nstorePassword=%s\nkeyAlias=upload\nkeyPassword=%s\n"
              % (self.f.keys / "upload.jks", STORE_PW, KEY_PW), 0o600)
        r = self.f.run()
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        write(self.f.key_properties, "storeFile=gone.jks\nstorePassword=x\nkeyAlias=upload\nkeyPassword=y\n", 0o600)
        r = self.f.run()  # refused before building: the bundle checked by the run above stays
        self.assertEqual(1, r.returncode)
        self.assertIn("the keystore %s named by storeFile does not exist" % (self.f.keys / "gone.jks"), r.stderr)

    def test_refuses_a_bundle_signed_by_another_key_or_a_debug_key(self):
        self.assertRefused(self.f.run(FAKE_SIGNER_SHA256=OTHER_SHA256),
                           "is signed by SHA-256 %s, expected the upload key %s" % (OTHER_SHA256, UPLOAD_SHA256))
        self.assertRefused(self.f.run(FAKE_SIGNER_OWNER="CN=Android Debug, O=Android, C=US"),
                           "is signed with an Android debug key")

    def test_refuses_a_bundle_that_fails_the_bundle_checks(self):
        write(self.f.tmp / "manifest.xml", manifest_xml(debuggable=True))
        r = self.f.run()
        self.assertRefused(r, "nothing was written to build/release/android/")
        self.assertIn("violation: android:debuggable is true", r.stdout)

    def test_refuses_source_problems_before_building(self):
        self.assertRefused(self.f.run(FAKE_LICENCE_FAIL="1"), "the licence check failed")
        write(self.f.repo / "shellx-android/app/src/main/res/values/google_oauth.xml",
              oauth_xml("0-shellx-placeholder.apps.googleusercontent.com"))
        (self.f.repo / "shellx-android/app/google-services.json").unlink()
        self.f.commit_and_push("placeholder and no Firebase file")
        r = self.f.run()
        self.assertRefused(r, "the source checks failed")
        self.assertIn("violation: missing shellx-android/app/google-services.json", r.stdout)
        self.assertIn('violation: google_web_client_id is "0-shellx-placeholder.apps.googleusercontent.com", '
                      'not a Google OAuth client id', r.stdout)
        write(self.f.repo / "shellx-android/app/src/main/res/xml/network_security_config.xml",
              '<network-security-config><base-config cleartextTrafficPermitted="true"/></network-security-config>\n')
        self.f.git("checkout", "HEAD~1", "--", "shellx-android/app")
        self.f.commit_and_push("cleartext")
        self.assertRefused(self.f.run(), "a release source set permits cleartext traffic: "
                                         "shellx-android/app/src/main/res/xml/network_security_config.xml")
        self.assertFalse((self.f.tmp / "gradle.log").exists())

    def test_refuses_a_missing_or_old_bundletool(self):
        self.assertRefused(self.f.run(FAKE_BUNDLETOOL_VERSION="1.15.6"), "bundletool 1.15.6 is too old")
        (self.f.tools / "bundletool").unlink()
        self.assertRefused(self.f.run(), "bundletool not found; install it with: brew install bundletool")

    def test_refuses_bad_version_properties(self):
        for text, message in (("VERSION_NAME=1.2\nVERSION_CODE=105\n", "VERSION_NAME '1.2'"),
                              ("VERSION_NAME=1.2.3\nVERSION_CODE=0\n", "VERSION_CODE '0'"),
                              ("VERSION_NAME=1.2.3\nVERSION_CODE=2100000001\n", "VERSION_CODE '2100000001'")):
            write(self.f.repo / "shellx-android/version.properties", text)
            self.f.commit_and_push(message)
            self.assertRefused(self.f.run(), message)

    def test_mark_uploaded_needs_a_checked_bundle_then_blocks_its_version_code(self):
        self.assertRefused(self.f.run("--mark-uploaded"), "no checked bundle of ShellX 1.2.3 (105)")
        self.assertEqual(0, self.f.run().returncode)
        r = self.f.run("--mark-uploaded")
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertIn("The next upload needs VERSION_CODE 106 or higher", r.stdout)
        self.assertRegex((self.out / (NAME + ".uploaded")).read_text(),
                         r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ from [0-9a-f]{40}\n$")
        again = self.f.run("--mark-uploaded")
        self.assertEqual(1, again.returncode)
        self.assertIn("is already marked uploaded", again.stderr)
        build = self.f.run()
        self.assertEqual(1, build.returncode)
        self.assertIn("Google Play refuses a versionCode it has seen", build.stderr)

    def test_check_aab_checks_a_given_bundle_without_git_or_outputs(self):
        write(self.f.repo / "shellx-android/version.properties", "VERSION_NAME=1.2.3\nVERSION_CODE=105\n# dirty\n")
        r = self.f.run("--check-aab", str(self.f.aab), str(self.f.tmp / "mapping.txt"))
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertIn("bundle checks passed: com.shellx.prod 1.2.3 (105)", r.stdout)
        self.assertIn("==> upload key: SHA-256 " + UPLOAD_SHA256, r.stdout)
        self.assertFalse(self.out.exists())
        self.assertFalse((self.f.tmp / "gradle.log").exists())
        missing = self.f.run("--check-aab", str(self.f.tmp / "none.aab"))
        self.assertEqual(1, missing.returncode)
        self.assertIn("is not a file", missing.stderr)

    def test_notes_a_version_name_unlike_the_iphone(self):
        write(self.f.repo / "shellx-ios/Config/Version.xcconfig", "MARKETING_VERSION = 1.3.0\n")
        self.f.commit_and_push("iPhone 1.3.0")
        r = self.f.run()
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertIn("note: VERSION_NAME 1.2.3 is not the iPhone's MARKETING_VERSION 1.3.0", r.stdout)

    def test_refuses_stale_fallback_licence_notices(self):
        write(self.f.repo / "shellx-android/app/src/main/assets/licenses/third_party_licenses.txt", "old\n")
        write(self.f.repo / "shellx-android/scripts/generate-licences.py",
              "import sys\nprint('generate-licences: stale; run python3 shellx-android/scripts/generate-licences.py')\n"
              "sys.exit(1)\n")
        self.f.commit_and_push("stale licence notices")
        self.assertRefused(self.f.run(), "the licence notices are stale")
        self.assertFalse((self.f.tmp / "gradle.log").exists())

    def test_never_traces_the_keystore_passwords(self):
        """bash -x, SHELLOPTS=xtrace and set -x around source must not put a password in any output, even shell-quoted."""
        import shlex
        script = str(self.f.repo / "release/mobile/android.sh")
        modes = {"build": [], "check-aab": ["--check-aab", str(self.f.aab), str(self.f.tmp / "mapping.txt")]}
        routes = {
            "bash -x": (lambda a: ["bash", "-x", script, *a], {}),
            "SHELLOPTS=xtrace": (lambda a: ["bash", script, *a], {"SHELLOPTS": "xtrace"}),
            "set -x; source": (lambda a: ["bash", "-c", 'set -x; source "$0" "$@"', script, *a], {}),
        }
        secrets = []
        for pw in (STORE_PW, KEY_PW):
            secrets += [pw, shlex.quote(pw), "'%s'" % pw, pw.replace("'", "'\\''")]
        for route, (argv, extra) in routes.items():
            for mode, args in modes.items():
                with self.subTest(route=route, mode=mode):
                    r = subprocess.run(argv(args), cwd=self.f.repo, env=self.f.env(**extra),
                                       capture_output=True, text=True)
                    for secret in secrets:
                        self.assertNotIn(secret, r.stdout + r.stderr)
                    self.assertNotEqual(0, r.returncode, "tracing must be refused, not tolerated")
                    self.assertIn("xtrace", r.stderr)

    def test_usage_and_no_upload_path(self):
        r = self.f.run("--help")
        self.assertEqual(0, r.returncode)
        for text in ("--check-aab", "--mark-uploaded", "never uploads"):
            self.assertIn(text, r.stdout)
        bad = self.f.run("--upload")
        self.assertEqual(2, bad.returncode)
        self.assertIn("unknown option --upload", bad.stderr)
        script = (MOBILE / "android.sh").read_text(encoding="utf-8")
        for word in ("androidpublisher", "googleapis", "fastlane", "gcloud", "curl", "wget"):
            self.assertNotIn(word, script)


if __name__ == "__main__":
    unittest.main()
