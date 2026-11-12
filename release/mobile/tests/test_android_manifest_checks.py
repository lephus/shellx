"""Tests for the manifest and target-SDK checks of release/mobile/check_android_bundle.py (plan 3H).

Run: python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests -v
"""
from __future__ import annotations

import datetime
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "release" / "mobile"))
import check_android_bundle as cab  # noqa: E402

ANDROID = "http://schemas.android.com/apk/res/android"
PERMS = ["android.permission.CAMERA", "android.permission.INTERNET"]
RULES = "# comment\n\n2024-08-31 34\n2025-08-31 35\n2026-08-31 36\n"
SINCE = datetime.date(2026, 8, 31)


def manifest_xml(package="com.shellx.prod", code="105", name="1.2.3", min_sdk="26", target="36",
                 app='android:allowBackup="false"', permissions=PERMS, activities=("com.shellx.app.MainActivity",)):
    perms = "".join('<uses-permission android:name="%s"/>' % p for p in permissions)
    acts = "".join('<activity android:name="%s" android:exported="true"/>' % a for a in activities)
    return ('<manifest xmlns:android="%s" android:versionCode="%s" android:versionName="%s" package="%s">'
            '<uses-sdk android:minSdkVersion="%s" android:targetSdkVersion="%s"/>%s<application %s>%s</application>'
            '</manifest>' % (ANDROID, code, name, package, min_sdk, target, perms, app, acts))


def problems(xml=None, **overrides):
    expected = dict(version_name="1.2.3", version_code="105", catalog_target_sdk="36", required_sdk=36,
                    required_since=SINCE, permissions=PERMS)
    expected.update(overrides)
    return cab.manifest_problems(cab.parse_manifest(xml or manifest_xml()), **expected)


def has(found, text):
    return any(text in p for p in found)


class PlayRuleTableTest(unittest.TestCase):
    def test_rules_pick_the_newest_rule_in_force(self):
        self.assertEqual((36, SINCE), cab.required_target_sdk(RULES, datetime.date(2026, 11, 7)))
        self.assertEqual((36, SINCE), cab.required_target_sdk(RULES, datetime.date(2026, 8, 31)))
        self.assertEqual(35, cab.required_target_sdk(RULES, datetime.date(2026, 8, 30))[0])
        self.assertEqual(36, cab.required_target_sdk(RULES, datetime.date(2027, 8, 31))[0])

    def test_rules_refuse_a_stale_table(self):
        with self.assertRaises(cab.RuleTableError) as caught:
            cab.required_target_sdk(RULES, datetime.date(2027, 9, 1))
        self.assertIn("is from 2026-08-31, more than 365 days ago", str(caught.exception))
        self.assertIn("https://developer.android.com/google/play/requirements/target-sdk", str(caught.exception))

    def test_rules_refuse_a_day_before_every_rule(self):
        with self.assertRaises(cab.RuleTableError) as caught:
            cab.required_target_sdk(RULES, datetime.date(2020, 1, 1))
        self.assertIn("has no rule in force on 2020-01-01", str(caught.exception))

    def test_rules_refuse_a_malformed_line(self):
        for line in ("2026-13-01 36", "2026-08-31", "2026-08-31 thirty-six"):
            with self.assertRaises(cab.RuleTableError) as caught:
                cab.required_target_sdk("2025-08-31 35\n" + line + "\n", datetime.date(2026, 1, 1))
            self.assertIn("android-play-target-sdk.txt line 2", str(caught.exception))

    def test_the_real_table_requires_36_on_2026_11_07(self):
        text = (REPO / "release/mobile/android-play-target-sdk.txt").read_text(encoding="utf-8")
        self.assertEqual((36, SINCE), cab.required_target_sdk(text, datetime.date(2026, 11, 7)))


class ManifestTest(unittest.TestCase):
    def test_parses_the_manifest_bundletool_prints(self):
        m = cab.parse_manifest(manifest_xml(app='android:allowBackup="false" android:label="@string/app_name"'))
        self.assertEqual(("com.shellx.prod", "105", "1.2.3", "26", "36"),
                         (m.package, m.version_code, m.version_name, m.min_sdk, m.target_sdk))
        self.assertEqual("false", m.application["allowBackup"])
        self.assertEqual(tuple(PERMS), m.permissions)
        self.assertEqual(("com.shellx.app.MainActivity",), m.activities)

    def test_the_release_manifest_passes(self):
        self.assertEqual([], problems())

    def test_refuses_another_application_id(self):
        self.assertIn("application id is com.shellx.dev, expected com.shellx.prod",
                      problems(manifest_xml(package="com.shellx.dev")))

    def test_refuses_versions_unlike_version_properties(self):
        found = problems(manifest_xml(code="104", name="1.2.2"))
        self.assertIn("versionCode is 104, shellx-android/version.properties says 105", found)
        self.assertIn("versionName is 1.2.2, shellx-android/version.properties says 1.2.3", found)

    def test_refuses_a_min_sdk_other_than_26(self):
        self.assertIn("minSdkVersion is 24, expected 26", problems(manifest_xml(min_sdk="24")))

    def test_refuses_a_target_sdk_below_play_or_unlike_the_catalog(self):
        found = problems(manifest_xml(target="35"))
        self.assertIn("targetSdkVersion is 35, the version catalog's androidTargetSdk is 36", found)
        self.assertTrue(has(found, "targetSdkVersion 35 is below 36, which Google Play requires since 2026-08-31"))
        self.assertEqual([], problems(manifest_xml(target="37"), catalog_target_sdk="37"))

    def test_refuses_debuggable_test_only_cleartext_and_backup(self):
        app = ('android:debuggable="true" android:testOnly="true" android:usesCleartextTraffic="true" '
               'android:allowBackup="true"')
        found = problems(manifest_xml(app=app))
        for text in ("android:debuggable is true", "android:testOnly is true",
                     "android:usesCleartextTraffic is true", "android:allowBackup is not false"):
            self.assertTrue(has(found, text), text)
        self.assertTrue(has(problems(manifest_xml(app="")), "android:allowBackup is not false"))

    def test_refuses_debug_only_activities(self):
        found = problems(manifest_xml(activities=("com.shellx.app.MainActivity", "androidx.activity.ComponentActivity")))
        self.assertIn("declares the debug-only activity androidx.activity.ComponentActivity", found)

    def test_permissions_must_match_the_list_exactly(self):
        found = problems(manifest_xml(permissions=["android.permission.INTERNET", "android.permission.READ_CONTACTS"]))
        self.assertTrue(has(found, "requests android.permission.READ_CONTACTS, which release/mobile/android-permissions.txt does not list"))
        self.assertTrue(has(found, "release/mobile/android-permissions.txt lists android.permission.CAMERA, which the bundle does not request"))

    def test_never_allowed_permissions_are_refused_even_when_listed(self):
        never = ["android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS", "com.google.android.gms.permission.AD_ID"]
        found = problems(manifest_xml(permissions=PERMS + never), permissions=PERMS + never)
        self.assertTrue(has(found, "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, which ShellX never ships (S3 §7.4c)"))
        self.assertTrue(has(found, "AD_ID, which ShellX never ships (the Advertising ID declaration says no)"))

    def test_the_real_permission_list_is_well_formed(self):
        names = cab.read_permission_list((REPO / "release/mobile/android-permissions.txt").read_text(encoding="utf-8"))
        self.assertIn("android.permission.INTERNET", names)
        self.assertEqual(sorted(set(names)), names)
        for never in cab.NEVER_ALLOWED_PERMISSIONS:
            self.assertNotIn(never, names)


if __name__ == "__main__":
    unittest.main()
