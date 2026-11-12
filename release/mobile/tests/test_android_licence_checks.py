"""Tests for the open-source licence notice check of release/mobile/check_android_bundle.py (plan 3H, Task 7).

Run: python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests -v
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "release" / "mobile"))
import check_android_bundle as cab  # noqa: E402
import test_android_bundle_checks as bt  # noqa: E402  (its bundle and command-line fixtures)

NAMES = b"\x22\x14third_party_licenses\x2a\x1cthird_party_license_metadata"
LICENCES = b"Apache License, Version 2.0 https://www.apache.org/licenses/LICENSE-2.0\n"
METADATA = b"0:71 OkHttp\n"
APACHE_TEXT = (b"LICENCE TEXT: Apache License, Version 2.0\n\n                                 Apache License\n"
               b"                           Version 2.0, January 2004\n")
EMBEDDED = b"== Notices embedded in Google libraries ==\n\nEmbedded in com.google.android.gms:play-services-basement:18.9.0\n"
LIBRARY = b"OkHttp (com.squareup.okhttp3:okhttp:5.1.0)\n"
PLAY_SERVICES = b"Basement (com.google.android.gms:play-services-basement:18.9.0)\n"
NO_APACHE = ("assets/licenses/third_party_licenses.txt lacks the Apache-2.0 licence text (the line \"LICENCE TEXT: "
             "Apache License, Version 2.0\" and its title): regenerate it with generate-licences.py")
NO_EMBEDDED = ("assets/licenses/third_party_licenses.txt lists a Google Play services library but has no section "
               "\"== Notices embedded in Google libraries ==\": regenerate it with generate-licences.py")
MISSING = ("the bundle has no open-source licence notices: neither the resources raw/third_party_licenses and "
           "raw/third_party_license_metadata (Google's OSS licences plugin) nor assets/licenses/third_party_licenses.txt")


class LicenceNoticeTest(unittest.TestCase):
    def test_googles_licence_resources_pass(self):
        files = {"base/res/raw/third_party_licenses": LICENCES, "base/res/raw/third_party_license_metadata": METADATA}
        self.assertEqual([], cab.licence_notice_problems(NAMES, files, None))

    def test_shortened_resource_paths_still_pass(self):
        self.assertEqual([], cab.licence_notice_problems(NAMES, {"base/res/Ab.bin": LICENCES}, None))

    def test_the_debug_placeholder_is_refused(self):
        files = {"base/res/raw/third_party_licenses": b"Licenses are only provided in build variants (e.g. release)",
                 "base/res/raw/third_party_license_metadata": b"0:59 Debug License Info\n"}
        self.assertEqual(["base/res/raw/third_party_license_metadata holds the licences plugin's debug placeholder "
                          "(\"Debug License Info\"): the plugin did not see the release dependencies"],
                         cab.licence_notice_problems(NAMES, files, None))

    def test_the_fallback_asset_with_the_apache_text_passes(self):
        self.assertEqual([], cab.licence_notice_problems(b"", {}, LIBRARY + APACHE_TEXT))

    def test_an_asset_with_only_names_and_urls_is_refused(self):
        self.assertEqual([NO_APACHE], cab.licence_notice_problems(b"", {}, LIBRARY))

    def test_an_asset_whose_marker_has_no_licence_title_is_refused(self):
        self.assertEqual([NO_APACHE], cab.licence_notice_problems(b"", {}, LIBRARY + b"LICENCE TEXT: Apache License, Version 2.0\n"))

    def test_play_services_need_the_section_of_embedded_google_notices(self):
        self.assertEqual([NO_EMBEDDED], cab.licence_notice_problems(b"", {}, PLAY_SERVICES + APACHE_TEXT))
        self.assertEqual([], cab.licence_notice_problems(b"", {}, PLAY_SERVICES + APACHE_TEXT + EMBEDDED))
        self.assertEqual([NO_APACHE, NO_EMBEDDED], cab.licence_notice_problems(b"", {}, PLAY_SERVICES))

    def test_a_bundle_without_notices_is_refused(self):
        self.assertEqual([MISSING], cab.licence_notice_problems(b"\x22\x14third_party_licenses", {}, None))
        self.assertEqual([MISSING], cab.licence_notice_problems(b"", {}, b""))

    def test_the_bundle_command_refuses_a_bundle_without_notices(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            files = {"manifest.xml": bt.MANIFEST, "config.json": bt.CONFIG_16K, "rules.txt": "2026-08-31 36\n",
                     "permissions.txt": "\n".join(bt.PERMS) + "\n", "google-services.json": bt.GOOGLE_SERVICES,
                     "google_oauth.xml": bt.oauth_xml(bt.WEB_ID)}
            for name, text in files.items():
                (d / name).write_text(text, encoding="utf-8")
            aab = bt.make_aab(d, resources=b"\x0a\x20" + bt.APP_ID.encode() + b"\x12" + bt.WEB_ID.encode()
                              + b"\x1a\x0bic_google_g")
            r = subprocess.run([sys.executable, "-I", str(REPO / "release/mobile/check_android_bundle.py"), "bundle",
                                "--google-services", str(d / "google-services.json"),
                                "--google-oauth", str(d / "google_oauth.xml"), "--aab", str(aab),
                                "--manifest-xml", str(d / "manifest.xml"), "--bundle-config", str(d / "config.json"),
                                "--version-name", "1.2.3", "--version-code", "105", "--catalog-target-sdk", "36",
                                "--play-rules", str(d / "rules.txt"), "--permissions", str(d / "permissions.txt"),
                                "--today", "2026-11-07"], capture_output=True, text=True)
            self.assertEqual(1, r.returncode, r.stdout + r.stderr)
            self.assertEqual(["violation: " + MISSING], r.stdout.splitlines())


if __name__ == "__main__":
    unittest.main()
