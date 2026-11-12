"""Tests for the bundle, source and command-line checks of release/mobile/check_android_bundle.py (plan 3H).

Run: python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests -v
"""
from __future__ import annotations

import json
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "release" / "mobile"))
import check_android_bundle as cab  # noqa: E402

LOAD, RELRO = 1, 0x6474E552
APP_ID = "1:111111111111:android:2222222222222222"
WEB_ID = "123456789012-abcdefghij0123456789abcdefghij01.apps.googleusercontent.com"
PLACEHOLDER = "0-shellx-placeholder.apps.googleusercontent.com"
PERMS = ["android.permission.CAMERA", "android.permission.INTERNET"]
MAPPING = (b"# compiler: R8\ncom.shellx.app.MainActivity -> com.shellx.app.MainActivity:\n"
           b"com.shellx.core.demo.DemoScript -> a.a:\n")
CONFIG_16K = '{"optimizations": {"uncompressNativeLibraries": {"enabled": true, "alignment": "PAGE_ALIGNMENT_16K"}}}'
GOOGLE_SERVICES = json.dumps({"project_info": {"project_id": "shellxpro"}, "client": [
    {"client_info": {"mobilesdk_app_id": "1:111111111111:android:3333333333333333",
                     "android_client_info": {"package_name": "com.shellx.dev"}}},
    {"client_info": {"mobilesdk_app_id": APP_ID, "android_client_info": {"package_name": "com.shellx.prod"}}}]})
LEDGER_ROW = "| 6 | ShellX Web (Android sign-in) | Web application | — | — | %s |\n"
MANIFEST = ('<manifest xmlns:android="http://schemas.android.com/apk/res/android" android:versionCode="105" '
            'android:versionName="1.2.3" package="com.shellx.prod"><uses-sdk android:minSdkVersion="26" '
            'android:targetSdkVersion="36"/><uses-permission android:name="android.permission.CAMERA"/>'
            '<uses-permission android:name="android.permission.INTERNET"/><application android:allowBackup="false">'
            '<activity android:name="com.shellx.app.MainActivity"/></application></manifest>')


def oauth_xml(value):
    return ('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <string name="google_web_client_id" '
            'translatable="false">%s</string>\n</resources>\n' % value)


def elf64(segments):
    """A little-endian ELF64 header and program headers; segments are (p_type, p_vaddr, p_memsz, p_align)."""
    head = bytearray(64)
    head[0:7] = b"\x7fELF\x02\x01\x01"
    struct.pack_into("<HHIQQQIHHHHHH", head, 16, 3, 183, 1, 0, 64, 0, 0, 64, 56, len(segments), 0, 0, 0)
    return bytes(head) + b"".join(struct.pack("<IIQQQQQQ", t, 0, 0, v, v, m, m, a) for t, v, m, a in segments)


def elf32(segments):
    head = bytearray(52)
    head[0:7] = b"\x7fELF\x01\x01\x01"
    struct.pack_into("<HHIIIIIHHHHHH", head, 16, 3, 40, 1, 0, 52, 0, 0, 52, 32, len(segments), 0, 0, 0)
    return bytes(head) + b"".join(struct.pack("<IIIIIIII", t, 0, v, v, m, m, 0, a) for t, v, m, a in segments)


ALIGNED = elf64([(LOAD, 0, 0x680, 0x4000), (LOAD, 0x4680, 0x1D8, 0x4000)])
FOUR_K = elf64([(LOAD, 0, 0x680, 0x1000), (LOAD, 0x1680, 0x1D8, 0x1000)])


def make_aab(folder, extra=None, mapping=MAPPING, dex=b"dex\n035\x00Lcom/shellx/app/MainActivity;",
             resources=b"\x0a\x20" + APP_ID.encode() + b"\x12" + WEB_ID.encode() + b"\x1a\x0bic_google_g"
             + b"\x22\x14third_party_licenses\x2a\x1cthird_party_license_metadata"):
    entries = {"base/manifest/AndroidManifest.xml": b"proto", "base/resources.pb": resources}
    if dex is not None:
        entries["base/dex/classes.dex"] = dex
    if mapping is not None:
        entries[cab.MAPPING_ENTRY] = mapping
    entries.update(extra or {})
    path = Path(folder) / "app-release.aab"
    with zipfile.ZipFile(path, "w") as z:
        for name, data in entries.items():
            z.writestr(name, data)
    return path


class NativeLibraryTest(unittest.TestCase):
    def test_every_library_needs_16_kb_load_alignment(self):
        self.assertEqual([], cab.elf_problems("base/lib/arm64-v8a/libok.so", ALIGNED))
        self.assertEqual([], cab.elf_problems("base/lib/armeabi-v7a/libok.so", elf32([(LOAD, 0, 0x680, 0x4000)])))
        for entry, data in (("base/lib/arm64-v8a/libold.so", FOUR_K), ("base/lib/x86_64/libold.so", FOUR_K),
                            ("base/lib/armeabi-v7a/libold.so", elf32([(LOAD, 0, 0x680, 0x1000)]))):
            self.assertEqual(["%s: a LOAD segment is aligned to 4096 bytes; Google Play needs 16 KB (16384)" % entry],
                             cab.elf_problems(entry, data))

    def test_relro_examples_of_the_android_guide(self):
        entry = "base/lib/arm64-v8a/libx.so"
        example1 = elf64([(LOAD, 0, 0xCFAF0, 0x4000), (LOAD, 0xDFAF0, 0x4510, 0x4000), (RELRO, 0xDFAF0, 0x1510, 1)])
        example2 = elf64([(LOAD, 0, 0xCFAF0, 0x4000), (LOAD, 0xDFAF0, 0x3510, 0x4000), (RELRO, 0xDFAF0, 0x510, 1)])
        example4 = elf64([(LOAD, 0, 0x680, 0x4000), (LOAD, 0x4680, 0x980, 0x4000), (RELRO, 0x4680, 0x980, 1)])
        self.assertEqual(["%s: GNU_RELRO 0xdfaf0-0xe1000 shares its 16 KB pages with other loaded data at 0xe1000-0xe4000" % entry],
                         cab.elf_problems(entry, example1))
        self.assertEqual([], cab.elf_problems(entry, example2))
        self.assertEqual([], cab.elf_problems(entry, ALIGNED))  # example 3: no GNU_RELRO
        self.assertEqual([], cab.elf_problems(entry, example4))

    def test_relro_padded_past_its_load_is_safe_when_nothing_else_shares_the_pages(self):
        entry = "base/lib/arm64-v8a/libpad.so"
        arm64 = elf64([(LOAD, 0, 0x1C40, 0x4000), (LOAD, 0x5C40, 0x390, 0x4000), (LOAD, 0x9FD0, 0x10, 0x4000),
                       (RELRO, 0x5C40, 0x3C0, 1)])
        x86_64 = elf64([(LOAD, 0, 0x1EC0, 0x4000), (LOAD, 0x5EC0, 0x3A8, 0x4000), (LOAD, 0xA268, 0x10, 0x4000),
                        (RELRO, 0x5EC0, 0x1140, 1)])
        self.assertEqual([], cab.elf_problems(entry, arm64))
        self.assertEqual([], cab.elf_problems(entry, x86_64))

    def test_relro_sharing_a_page_with_other_loaded_data_is_refused(self):
        entry = "base/lib/arm64-v8a/libshare.so"
        bss_in_page = elf64([(LOAD, 0, 0x1C40, 0x4000), (LOAD, 0x5C40, 0x390, 0x4000), (LOAD, 0x6100, 0x10, 0x4000),
                             (RELRO, 0x5C40, 0x3C0, 1)])
        self.assertEqual(["%s: GNU_RELRO 0x5c40-0x6000 shares its 16 KB pages with other loaded data at "
                          "0x6100-0x6110" % entry], cab.elf_problems(entry, bss_in_page))
        rw_after = elf64([(LOAD, 0, 0x1C40, 0x4000), (LOAD, 0x5C40, 0x390, 0x4000), (LOAD, 0x7000, 0x100, 0x4000),
                          (RELRO, 0x5C40, 0x390, 1)])
        self.assertEqual(["%s: GNU_RELRO 0x5c40-0x5fd0 shares its 16 KB pages with other loaded data at "
                          "0x7000-0x7100" % entry], cab.elf_problems(entry, rw_after))
        starts_mid_load = elf64([(LOAD, 0, 0x1C40, 0x4000), (LOAD, 0x4100, 0x700, 0x4000), (RELRO, 0x4400, 0x400, 1)])
        self.assertEqual(["%s: GNU_RELRO 0x4400-0x4800 shares its 16 KB pages with other loaded data at "
                          "0x4100-0x4400" % entry], cab.elf_problems(entry, starts_mid_load))

    def test_a_library_that_is_not_elf_is_refused(self):
        self.assertEqual(["base/lib/arm64-v8a/libz.so: not an ELF shared library"],
                         cab.elf_problems("base/lib/arm64-v8a/libz.so", b"not an elf file at all, " * 3))


class DebugOnlyCodeTest(unittest.TestCase):
    def test_debug_only_code_is_found_by_package_and_by_name(self):
        dex = {"base/dex/classes.dex": b"..Lorg/robolectric/RuntimeEnvironment;..",
               "base/dex/classes2.dex": b"..InMemorySecretStore..Landroidx/compose/ui/tooling/PreviewActivity;.."}
        mapping = "org.junit.Assert -> a.b:\n    void fail() -> a\ncom.shellx.core.testing.ManualClock -> c.d:\n"
        hits = cab.debug_only_hits(dex, mapping)
        for hit in ("org.junit.Assert (R8 mapping)", "com.shellx.core.testing.ManualClock (R8 mapping)",
                    "Lorg/robolectric/ (base/dex/classes.dex)", "InMemorySecretStore (base/dex/classes2.dex)",
                    "Landroidx/compose/ui/tooling/ (base/dex/classes2.dex)"):
            self.assertIn(hit, hits)

    def test_the_demo_and_compose_preview_annotations_ship(self):
        dex = {"base/dex/classes.dex": b"..Landroidx/compose/ui/tooling/preview/Preview;..Lcom/shellx/core/demo/FakeMac;.."}
        mapping = ("com.shellx.core.demo.FakeMac -> e.f:\ncom.shellx.core.demo.DemoRelay -> e.g:\n"
                   "com.shellx.core.demo.DemoSecretStore -> e.h:\nandroidx.compose.ui.tooling.preview.Preview -> i.j:\n")
        self.assertEqual([], cab.debug_only_hits(dex, mapping))


class SourceFilesTest(unittest.TestCase):
    def test_release_classpath_has_no_analytics_ads_or_crash_sdk(self):
        text = ("# comment\n"
                "com.google.firebase:firebase-messaging:24.1.0=debugRuntimeClasspath,releaseRuntimeClasspath\n"
                "com.google.firebase:firebase-analytics:22.0.0=releaseRuntimeClasspath\n"
                "com.google.android.gms:play-services-measurement-api:22.0.0=debugRuntimeClasspath,releaseRuntimeClasspath\n"
                "com.google.firebase:firebase-crashlytics:19.0.0=debugUnitTestRuntimeClasspath\n"
                "empty=\n")
        found = cab.lockfile_problems(text)
        self.assertEqual(2, len(found))
        self.assertTrue(found[0].startswith("com.google.firebase:firebase-analytics:22.0.0 is on the release classpath"))
        self.assertTrue(found[1].startswith("com.google.android.gms:play-services-measurement-api:22.0.0 is on the release"))

    def test_firebase_must_be_configured_for_com_shellx_prod_of_shellxpro(self):
        self.assertEqual((APP_ID, []), cab.google_services_app_id(GOOGLE_SERVICES))
        app_id, found = cab.google_services_app_id(json.dumps({"project_info": {"project_id": "elsewhere"}, "client": []}))
        self.assertIsNone(app_id)
        self.assertIn("google-services.json is for project elsewhere, expected shellxpro", found)
        self.assertIn("google-services.json has no client for com.shellx.prod", found)
        self.assertEqual((None, ["google-services.json is not valid JSON"]), cab.google_services_app_id("{"))

    def test_the_web_client_id_must_be_real_and_match_the_rollout_ledger(self):
        self.assertEqual((WEB_ID, []), cab.google_web_client_problems(oauth_xml(WEB_ID), None))
        value, found = cab.google_web_client_problems(oauth_xml(PLACEHOLDER), None)
        self.assertIsNone(value)
        self.assertTrue(found[0].startswith('google_web_client_id is "%s", not a Google OAuth client id' % PLACEHOLDER))
        other = "999999999999-zzzzzzzzzz0123456789abcdefghij01.apps.googleusercontent.com"
        value, found = cab.google_web_client_problems(oauth_xml(WEB_ID), "# Ledger\n" + LEDGER_ROW % other)
        self.assertEqual(["google_web_client_id %s differs from the Web client id %s in "
                          "docs/superpowers/ledgers/shellx-signin-rollout.md (client \"ShellX Web (Android sign-in)\")"
                          % (WEB_ID, other)], found)
        self.assertEqual((WEB_ID, []), cab.google_web_client_problems(oauth_xml(WEB_ID), LEDGER_ROW % WEB_ID))
        self.assertEqual((WEB_ID, []), cab.google_web_client_problems(oauth_xml(WEB_ID), LEDGER_ROW % ("`%s`" % WEB_ID)))
        self.assertEqual((WEB_ID, []), cab.google_web_client_problems(oauth_xml(WEB_ID), LEDGER_ROW % ""))
        self.assertEqual((WEB_ID, []), cab.google_web_client_problems(oauth_xml(WEB_ID), LEDGER_ROW % "pending (1D)"))
        self.assertEqual((None, ["google_oauth.xml has no google_web_client_id string"]),
                         cab.google_web_client_problems("<resources/>", None))


class CommandLineTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(self.dir)]))
        files = {"manifest.xml": MANIFEST, "config.json": CONFIG_16K, "rules.txt": "2026-08-31 36\n",
                 "permissions.txt": "\n".join(PERMS) + "\n", "google-services.json": GOOGLE_SERVICES,
                 "google_oauth.xml": oauth_xml(WEB_ID)}
        for name, text in files.items():
            (self.dir / name).write_text(text, encoding="utf-8")
        (self.dir / "mapping.txt").write_bytes(MAPPING)

    def run_cli(self, command, *extra):
        d = self.dir
        args = [sys.executable, "-I", str(REPO / "release/mobile/check_android_bundle.py"), command,
                "--google-services", str(d / "google-services.json"), "--google-oauth", str(d / "google_oauth.xml")]
        if command == "bundle":
            args += ["--manifest-xml", str(d / "manifest.xml"), "--bundle-config", str(d / "config.json"),
                     "--version-name", "1.2.3", "--version-code", "105", "--catalog-target-sdk", "36",
                     "--play-rules", str(d / "rules.txt"), "--permissions", str(d / "permissions.txt"),
                     "--today", "2026-11-07"]
        return subprocess.run(args + list(extra), capture_output=True, text=True)

    def test_a_good_bundle_passes_with_a_summary(self):
        aab = make_aab(self.dir, {"base/lib/arm64-v8a/libok.so": ALIGNED, "base/lib/armeabi-v7a/libok.so": elf32([(LOAD, 0, 0x680, 0x4000)])})
        r = self.run_cli("bundle", "--aab", str(aab), "--mapping", str(self.dir / "mapping.txt"))
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertEqual("bundle checks passed: com.shellx.prod 1.2.3 (105), target SDK 36 (Google Play needs 36 since "
                         "2026-08-31), 2 permissions, native code: 2 libraries 16 KB aligned, R8 mapping %d bytes\n"
                         % len(MAPPING), r.stdout)

    def test_violations_are_printed_and_exit_1(self):
        aab = make_aab(self.dir, {"base/lib/arm64-v8a/libold.so": FOUR_K})
        (self.dir / "config.json").write_text("{}", encoding="utf-8")
        (self.dir / "mapping.txt").write_bytes(MAPPING + b"extra -> x:\n")
        r = self.run_cli("bundle", "--aab", str(aab), "--mapping", str(self.dir / "mapping.txt"))
        self.assertEqual(1, r.returncode)
        lines = r.stdout.splitlines()
        self.assertTrue(all(line.startswith("violation: ") for line in lines), r.stdout)
        self.assertIn("violation: base/lib/arm64-v8a/libold.so: a LOAD segment is aligned to 4096 bytes; Google Play "
                      "needs 16 KB (16384)", lines)
        self.assertIn("violation: the bundle has native libraries but its config asks for no zip alignment; it must "
                      "ask for PAGE_ALIGNMENT_16K (Android Gradle plugin 8.5.1 or later)", lines)
        self.assertIn("violation: the bundle's R8 mapping differs from %s" % (self.dir / "mapping.txt"), lines)

    def test_without_a_mapping_file_the_embedded_mapping_is_scanned(self):
        aab = make_aab(self.dir, mapping=MAPPING + b"org.junit.Assert -> a:\n")
        r = self.run_cli("bundle", "--aab", str(aab))
        self.assertEqual(1, r.returncode)
        self.assertIn("violation: release contains debug-only code: org.junit.Assert (R8 mapping)", r.stdout)

    def test_a_bundle_without_dex_mapping_or_configured_ids_is_refused(self):
        aab = make_aab(self.dir, mapping=None, dex=None, resources=b"\x0a\x00")
        r = self.run_cli("bundle", "--aab", str(aab))
        self.assertEqual(1, r.returncode)
        for text in ("the bundle has no dex files (base/dex/classes*.dex)",
                     "the bundle has no R8 mapping (%s)" % cab.MAPPING_ENTRY,
                     "the bundle's resources do not hold Google's \"G\" (drawable/ic_google_g)",
                     "the bundle's resources do not hold the Firebase app id %s" % APP_ID,
                     "the bundle's resources do not hold google_web_client_id %s" % WEB_ID):
            self.assertIn(text, r.stdout)

    def test_sources_checks_the_source_files_only(self):
        lockfile = self.dir / "gradle.lockfile"
        lockfile.write_text("com.google.firebase:firebase-messaging:24.1.0=releaseRuntimeClasspath\nempty=\n")
        r = self.run_cli("sources", "--lockfile", str(lockfile))
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertEqual("source checks passed: Firebase app %s, Google web client %s\n" % (APP_ID, WEB_ID), r.stdout)
        (self.dir / "google_oauth.xml").write_text(oauth_xml(PLACEHOLDER), encoding="utf-8")
        (self.dir / "google-services.json").unlink()
        r = self.run_cli("sources")
        self.assertEqual(1, r.returncode)
        self.assertIn("violation: missing %s" % (self.dir / "google-services.json"), r.stdout)
        self.assertIn('violation: google_web_client_id is "%s", not a Google OAuth client id' % PLACEHOLDER, r.stdout)


if __name__ == "__main__":
    unittest.main()
