"""Tests for the install guard of scripts/dev.sh (`dev.sh check-apk <phone|emulator> <apk>`) and the release APK's
permission check (`dev.sh check-release-permissions <apk>`, run by `dev.sh build-release`).

Run: python3 -m unittest discover -s shellx-android/scripts/tests -v
"""
from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

DEV_SH = Path(__file__).resolve().parents[1] / "dev.sh"

PROD = "package: name='com.shellx.prod' versionCode='1' versionName='0.1.0'\napplication-label:'ShellX Dev'\n"
DEBUGGABLE = "application-debuggable\n"


class FakeSdkTest(unittest.TestCase):
    """An SDK whose aapt2 prints the "APK" as its badging."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        tools = root / "sdk" / "build-tools" / "36.0.0"
        tools.mkdir(parents=True)
        aapt2 = tools / "aapt2"
        # Fake aapt2: `aapt2 dump badging <file>` prints the file, so each test writes its own "badging".
        aapt2.write_text('#!/bin/sh\n[ "$1 $2" = "dump badging" ] && cat "$3"\n')
        aapt2.chmod(0o755)
        self.sdk = root / "sdk"
        self.apk = root / "app.apk"


class CheckApkTest(FakeSdkTest):
    def check(self, target: str, badging: str) -> subprocess.CompletedProcess:
        self.apk.write_text(badging)
        env = dict(os.environ, ANDROID_HOME=str(self.sdk))
        return subprocess.run(["bash", str(DEV_SH), "check-apk", target, str(self.apk)],
                              env=env, capture_output=True, text=True)

    def test_phone_accepts_debuggable_prod(self) -> None:
        self.assertEqual(self.check("phone", PROD + DEBUGGABLE).returncode, 0)

    def test_phone_refuses_release_prod(self) -> None:
        r = self.check("phone", PROD)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("not debuggable", r.stderr)

    def test_phone_refuses_other_package(self) -> None:
        r = self.check("phone", PROD.replace("com.shellx.prod", "com.shellx.dev") + DEBUGGABLE)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("com.shellx.prod", r.stderr)

    def test_emulator_accepts_debug_signed_release(self) -> None:
        self.assertEqual(self.check("emulator", PROD).returncode, 0)

    def test_emulator_refuses_other_package(self) -> None:
        r = self.check("emulator", PROD.replace("com.shellx.prod", "com.example.app"))
        self.assertNotEqual(r.returncode, 0)

    def test_unknown_target_is_a_usage_error(self) -> None:
        self.assertEqual(self.check("tablet", PROD).returncode, 2)


RELEASE_PERMISSIONS = (
    "uses-permission: name='android.permission.INTERNET'\n"
    "uses-permission: name='android.permission.ACCESS_NETWORK_STATE'\n"
    "uses-permission: name='android.permission.CAMERA'\n"
    "uses-feature-not-required: name='android.hardware.camera'\n"
)


class CheckReleasePermissionsTest(FakeSdkTest):
    """The release APK requests exactly the shell's permissions (3D Task 1; review A I-3)."""

    def release(self, badging: str) -> subprocess.CompletedProcess:
        self.apk.write_text(badging)
        env = dict(os.environ, ANDROID_HOME=str(self.sdk))
        return subprocess.run(["bash", str(DEV_SH), "check-release-permissions", str(self.apk)],
                              env=env, capture_output=True, text=True)

    def assertRefused(self, badging: str, named: str) -> None:
        r = self.release(badging)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn(named, r.stderr)

    def test_accepts_the_shells_permissions(self) -> None:
        r = self.release(PROD + RELEASE_PERMISSIONS)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_refuses_biometric_and_fingerprint(self) -> None:
        # androidx.credentials pulls androidx.biometric, whose manifest asks for both.
        for name in ("USE_BIOMETRIC", "USE_FINGERPRINT"):
            self.assertRefused(PROD + RELEASE_PERMISSIONS + f"uses-permission: name='android.permission.{name}'\n", name)

    def test_refuses_storage_and_media(self) -> None:
        self.assertRefused(PROD + RELEASE_PERMISSIONS + "uses-permission: name='android.permission.READ_MEDIA_IMAGES'\n",
                           "READ_MEDIA")

    def test_refuses_a_missing_permission(self) -> None:
        self.assertRefused(PROD + RELEASE_PERMISSIONS.replace("android.permission.CAMERA'", "android.permission.X'"),
                           "android.permission.CAMERA")

    def test_refuses_a_required_camera(self) -> None:
        self.assertRefused(PROD + RELEASE_PERMISSIONS.replace("uses-feature-not-required", "uses-feature"),
                           "uses-feature-not-required")


if __name__ == "__main__":
    unittest.main()
