"""Tests for scripts/shellx/check-android-license.sh.

Run: python3 -m unittest discover -s shellx-android/scripts/tests -v
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
SCRIPT = REPO / "scripts/shellx/check-android-license.sh"
COMPANY = "Mana" + "flow"  # built from pieces: the check scans this file too

CLEAN = {
    "shellx-android/settings.gradle.kts": (
        "pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }\n"
        "dependencyResolutionManagement { repositories { google(); mavenCentral() } }\n"
        'includeBuild("../shellx-link/kotlin")\n'
        'include(":app")\n'),
    "shellx-android/build.gradle.kts": "plugins { }\n",
    "shellx-android/gradle.properties": "kotlin.code.style=official\nandroid.builder.sdkDownload=false\n",
    "shellx-android/app/build.gradle.kts": (
        '// includeBuild("../../Sources") in a comment does not count\n'
        'description = "see ../../Sources"\n'
        'val firebase = file("src/debug/google-services.json")\n'),
    "shellx-android/app/gradle.lockfile": (
        "# This is a Gradle generated file for dependency locking.\n"
        "androidx.core:core:1.0.0=debugRuntimeClasspath,releaseRuntimeClasspath\n"
        "junit:junit:4.13.2=debugUnitTestRuntimeClasspath,releaseUnitTestRuntimeClasspath\n"
        "empty=debugAndroidTestRuntimeClasspath\n"),
    "shellx-android/gradle/wrapper/gradle-wrapper.jar": "PK not really a jar\n",
    "shellx-link/kotlin/settings.gradle.kts": 'include(":link-core")\n',
    "shellx-link/kotlin/build.gradle.kts": "\n",
    "shellx-link/kotlin/link-core/build.gradle.kts": 'val vectors = layout.projectDirectory.dir("../../vectors")\n',
    "shellx-link/kotlin/link-core/gradle.lockfile": (
        "org.jetbrains.kotlin:kotlin-stdlib:2.0.0=runtimeClasspath,testRuntimeClasspath\nempty=\n"),
    "scripts/shellx/android-license-allowlist.txt": (
        "# group:artifact scope licence\n"
        "androidx.*:*              ship  Apache-2.0\n"
        "org.jetbrains.kotlin:*    ship  Apache-2.0\n"
        "junit:junit               test  EPL-1.0  # JUnit 4\n"),
}
LOCK = "shellx-android/app/gradle.lockfile"
ALLOW = "scripts/shellx/android-license-allowlist.txt"


class CheckAndroidLicenseTests(unittest.TestCase):
    def tree(self, changes=None, remove=()):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root)
        files = dict(CLEAN)
        files.update(changes or {})
        for path, text in files.items():
            if path in remove:
                continue
            (root / path).parent.mkdir(parents=True, exist_ok=True)
            (root / path).write_text(text, encoding="utf-8")
        return root

    def check(self, root=None):
        return subprocess.run(["bash", str(SCRIPT)] + (["--root", str(root)] if root else []),
                              capture_output=True, text=True)

    def assertPasses(self, root=None):
        result = self.check(root)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("check-android-license: ok", result.stdout)

    def assertFails(self, root, *needles):
        result = self.check(root)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        for needle in needles:
            self.assertIn(needle, result.stdout)

    def test_repository_passes(self):
        self.assertPasses()

    def test_clean_tree_passes(self):
        self.assertPasses(self.tree())

    def test_unlisted_dependency_fails(self):
        root = self.tree({LOCK: CLEAN[LOCK] + "com.example:evil:1.0=releaseRuntimeClasspath\n"})
        self.assertFails(root, LOCK, "com.example:evil:1.0")

    def test_test_licence_on_the_shipped_classpath_fails(self):
        self.assertFails(self.tree({LOCK: CLEAN[LOCK] + "junit:junit:4.13.2=releaseRuntimeClasspath\n"}),
                         "junit:junit:4.13.2")

    def test_copyleft_entries_fail(self):
        for licence in ("GPL-2.0", "LGPL-2.1", "AGPL-3.0", "GPL-2.0-with-classpath-exception"):
            with self.subTest(licence=licence):
                root = self.tree({ALLOW: CLEAN[ALLOW] + f"org.example:lib  test  {licence}\n"})
                self.assertFails(root, "android-license-allowlist.txt", "org.example:lib")

    def test_unknown_licence_or_scope_fails(self):
        for line in ("org.example:lib  ship  WTFPL\n", "org.example:lib  shipped  MIT\n",
                     "org.example:lib  ship  EPL-2.0\n"):
            with self.subTest(line=line):
                self.assertFails(self.tree({ALLOW: CLEAN[ALLOW] + line}), "org.example:lib")

    def test_only_three_wildcards_exist(self):
        self.assertFails(self.tree({ALLOW: CLEAN[ALLOW] + "com.example:*  ship  MIT\n"}), "com.example:*")

    def test_google_sdks_are_listed_by_name(self):
        for line in ("com.google.firebase:*  ship  Google-SDK\n", "com.google.ads:ads  ship  Google-SDK\n",
                     "com.google.android.gms:*  ship  Apache-2.0\n"):
            with self.subTest(line=line):
                self.assertFails(self.tree({ALLOW: CLEAN[ALLOW] + line}), "android-license-allowlist.txt")
        self.assertPasses(self.tree({
            ALLOW: CLEAN[ALLOW] + "com.google.firebase:firebase-messaging  ship  Google-SDK\n",
            LOCK: CLEAN[LOCK] + "com.google.firebase:firebase-messaging:25.0.0=releaseRuntimeClasspath\n"}))

    def test_the_most_specific_entry_decides(self):
        self.assertFails(self.tree({
            ALLOW: CLEAN[ALLOW] + "androidx.test:core  test  Apache-2.0\n",
            LOCK: CLEAN[LOCK] + "androidx.test:core:1.6.0=releaseRuntimeClasspath\n"}), "androidx.test:core:1.6.0")

    def test_duplicate_key_is_an_error(self):
        for second in ("org.example:lib  test  MIT\n", "org.example:lib  ship  MIT\n"):
            with self.subTest(second=second):
                root = self.tree({ALLOW: CLEAN[ALLOW] + "org.example:lib  test  MIT\n" + second})
                self.assertFails(root, "android-license-allowlist.txt", "org.example:lib", "listed twice")

    def test_test_scope_dependency_on_ship_classpath_fails_until_moved(self):
        lock = CLEAN[LOCK] + "org.example:lib:1.0=releaseRuntimeClasspath\n"
        self.assertFails(self.tree({LOCK: lock, ALLOW: CLEAN[ALLOW] + "org.example:lib  test  MIT\n"}),
                         "org.example:lib:1.0", "move its allowlist line to ship")
        self.assertPasses(self.tree({LOCK: lock, ALLOW: CLEAN[ALLOW] + "org.example:lib  ship  MIT\n"}))

    def test_every_module_has_a_lockfile_with_its_runtime_classpath(self):
        self.assertFails(self.tree(remove=(LOCK,)), "shellx-android/app", "gradle.lockfile")
        self.assertFails(self.tree({LOCK: "junit:junit:4.13.2=debugUnitTestRuntimeClasspath\nempty=\n"}),
                         "releaseRuntimeClasspath")

    def test_paths_stay_inside_the_android_and_link_trees(self):
        cases = [
            ("shellx-android/settings.gradle.kts", 'includeBuild("../shellx-core")\n', "../shellx-core"),
            ("shellx-android/settings.gradle.kts", 'includeBuild("$rootDir/../shellx-link/kotlin")\n', "includeBuild"),
            ("shellx-android/app/build.gradle.kts",
             'android { sourceSets { getByName("main") { java.srcDir("../../Sources") } } }\n', "../../Sources"),
            ("shellx-link/kotlin/link-core/build.gradle.kts", 'val x = file("/Users/me/lib")\n', "/Users/me/lib"),
            ("shellx-link/kotlin/link-core/build.gradle.kts", 'val x = files("~/lib")\n', "~/lib"),
            ("shellx-android/build.gradle.kts", 'val z = file("${rootDir}/../Packages")\n',
             "shellx-android/build.gradle.kts"),
            ("shellx-link/kotlin/link-core/build.gradle.kts", 'val v = layout.projectDirectory.dir("../../../ios")\n',
             "../../../ios"),
        ]
        for path, text, needle in cases:
            with self.subTest(text=text):
                self.assertFails(self.tree({path: text}), needle)

    def test_only_maven_central_and_google_repositories(self):
        settings = CLEAN["shellx-android/settings.gradle.kts"]
        for text in ('repositories { maven("https://jitpack.io") }\n',
                     'repositories { maven { url = uri("https://jitpack.io") } }\n',
                     "repositories { mavenLocal() }\n", "repositories { jcenter() }\n", "repositories { ivy { } }\n"):
            with self.subTest(text=text):
                self.assertFails(self.tree({"shellx-android/settings.gradle.kts": settings + text}),
                                 "settings.gradle.kts")
        self.assertFails(self.tree({"shellx-android/app/build.gradle.kts": "repositories { gradlePluginPortal() }\n"}),
                         "gradlePluginPortal")

    def test_groovy_scripts_and_vendored_binaries_fail(self):
        self.assertFails(self.tree({"shellx-android/extra.gradle": "apply plugin: 'x'\n"}), "shellx-android/extra.gradle")
        self.assertFails(self.tree({"shellx-android/app/libs/vendor.jar": "PK\n"}), "shellx-android/app/libs/vendor.jar")
        self.assertFails(self.tree({"shellx-link/kotlin/link-core/libs/native.so": "ELF\n"}), "native.so")

    def test_the_upstream_company_name_fails(self):
        self.assertFails(self.tree({"shellx-android/README.md": f"Made by {COMPANY}.\n"}), "shellx-android/README.md")
        self.assertFails(self.tree({"shellx-link/kotlin/README.md": f"see {COMPANY.lower()}-ai\n"}),
                         "shellx-link/kotlin/README.md")
        self.assertPasses(self.tree({"shellx-android/Notes.kt": f"fun test{COMPANY}NameFails() {{}}\n"}))

    def test_agp_never_downloads_sdk_packages(self):
        props = "shellx-android/gradle.properties"
        for text in ("kotlin.code.style=official\n", "android.builder.sdkDownload=true\n",
                     "# android.builder.sdkDownload=false\n"):
            with self.subTest(text=text):
                self.assertFails(self.tree({props: text}), props, "android.builder.sdkDownload=false")
        self.assertFails(self.tree(remove=(props,)), props, "android.builder.sdkDownload=false")

    def test_symlinks_fail(self):
        root = self.tree()
        os.symlink("../../Sources", root / "shellx-android/app/src-link")
        self.assertFails(root, "shellx-android/app/src-link")


if __name__ == "__main__":
    unittest.main()
