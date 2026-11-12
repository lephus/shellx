"""Tests for shellx-android/scripts/generate-licences.py (plan 3H Task 7, fallback path only).

Run: python3 -m unittest discover -s shellx-android/scripts/tests -v
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "generate-licences.py"
APACHE = ("The Apache Software License, Version 2.0", "https://www.apache.org/licenses/LICENSE-2.0.txt")
LOCK = ("com.squareup.okhttp3:okhttp:5.1.0=debugRuntimeClasspath,releaseRuntimeClasspath\n"
        "androidx.core:core:1.16.0=releaseRuntimeClasspath\n"
        "junit:junit:4.13.2=debugUnitTestRuntimeClasspath\n"
        "com.shellx.link:link-core:1.0=releaseRuntimeClasspath\n"
        "empty=\n")


def pom(name=None, licences=(), parent=None):
    parts = ['<project xmlns="http://maven.apache.org/POM/4.0.0">']
    if parent:
        parts.append("<parent><groupId>%s</groupId><artifactId>%s</artifactId><version>%s</version></parent>" % parent)
    if name:
        parts.append("<name>%s</name>" % name)
    if licences:
        parts.append("<licenses>%s</licenses>" % "".join(
            "<license><name>%s</name><url>%s</url></license>" % l for l in licences))
    return "".join(parts) + "</project>\n"


class GenerateLicencesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.cache = self.tmp / "cache"
        self.lock = self.tmp / "gradle.lockfile"
        self.out = self.tmp / "assets" / "licenses" / "third_party_licenses.txt"
        self.lock.write_text(LOCK, encoding="utf-8")
        self.put("com.squareup.okhttp3", "okhttp", "5.1.0", pom("okhttp", [APACHE]))
        self.put("androidx.core", "core", "1.16.0", pom("Core", [APACHE]))

    def put(self, g, a, v, text):
        folder = self.cache / g / a / v / "0123abcd"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / ("%s-%s.pom" % (a, v))).write_text(text, encoding="utf-8")

    def run_script(self, *extra):
        return subprocess.run([sys.executable, "-I", str(SCRIPT), "--lockfile", str(self.lock), "--gradle-cache",
                               str(self.cache), "--out", str(self.out), *extra], capture_output=True, text=True)

    def test_lists_release_dependencies_with_their_pom_licences(self):
        r = self.run_script()
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertEqual("generate-licences: wrote 2 libraries to %s\n" % self.out, r.stdout)
        self.assertEqual("Open-source software in ShellX for Android\n\n"
                         "Core (androidx.core:core:1.16.0)\n"
                         "License: The Apache Software License, Version 2.0 https://www.apache.org/licenses/LICENSE-2.0.txt\n\n"
                         "okhttp (com.squareup.okhttp3:okhttp:5.1.0)\n"
                         "License: The Apache Software License, Version 2.0 https://www.apache.org/licenses/LICENSE-2.0.txt\n\n",
                         self.out.read_text(encoding="utf-8"))

    def test_a_licence_from_the_parent_pom(self):
        self.put("androidx.core", "core", "1.16.0", pom("Core", parent=("androidx", "parent", "1")))
        self.put("androidx", "parent", "1", pom(licences=[("MIT", "https://opensource.org/licenses/MIT")]))
        self.assertEqual(0, self.run_script().returncode)
        self.assertIn("Core (androidx.core:core:1.16.0)\nLicense: MIT https://opensource.org/licenses/MIT\n",
                      self.out.read_text(encoding="utf-8"))

    def test_check_reports_a_stale_file(self):
        self.assertEqual(1, self.run_script("--check").returncode)
        self.assertEqual(0, self.run_script().returncode)
        r = self.run_script("--check")
        self.assertEqual((0, "generate-licences: ok (2 libraries)\n"), (r.returncode, r.stdout))
        self.lock.write_text(LOCK.replace("1.16.0", "1.17.0"), encoding="utf-8")
        self.put("androidx.core", "core", "1.17.0", pom("Core", [APACHE]))
        r = self.run_script("--check")
        self.assertEqual((1, "generate-licences: stale; run python3 shellx-android/scripts/generate-licences.py\n"),
                         (r.returncode, r.stdout))

    def test_a_missing_pom_or_licence_is_an_error(self):
        self.lock.write_text("org.example:gone:1.0=releaseRuntimeClasspath\n", encoding="utf-8")
        r = self.run_script()
        self.assertEqual(1, r.returncode)
        self.assertIn("no POM for org.example:gone:1.0", r.stderr)
        self.put("org.example", "gone", "1.0", pom("Gone"))
        r = self.run_script()
        self.assertEqual(1, r.returncode)
        self.assertIn("no licence in the POM of org.example:gone:1.0 or its parents", r.stderr)


if __name__ == "__main__":
    unittest.main()
