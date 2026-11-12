"""Tests for shellx-android/scripts/generate-licences.py (plan 3H Task 7 and the licence-texts follow-up).

Run: python3 -m unittest discover -s shellx-android/scripts/tests -v
"""
from __future__ import annotations

import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "generate-licences.py"
APACHE = ("The Apache Software License, Version 2.0", "https://www.apache.org/licenses/LICENSE-2.0.txt")
APACHE_TEXT = "                                 Apache License\n                           Version 2.0, January 2004\n\n   TERMS AND CONDITIONS\n"
MIT = ("The MIT License", "http://opensource.org/licenses/MIT")
BSD = ("BSD-3-Clause", "https://opensource.org/licenses/BSD-3-Clause")
SDK = ("Android Software Development Kit License", "https://developer.android.com/studio/terms.html")
MIT_TEXT = "Checker Framework qualifiers\nCopyright 2004-present by the Checker Framework developers\n\nMIT License: permission is granted.\n"
LOCK = ("com.squareup.okhttp3:okhttp:5.1.0=debugRuntimeClasspath,releaseRuntimeClasspath\n"
        "androidx.core:core:1.16.0=releaseRuntimeClasspath\n"
        "junit:junit:4.13.2=debugUnitTestRuntimeClasspath\n"
        "com.shellx.link:link-core:1.0=releaseRuntimeClasspath\n"
        "empty=\n")


def make_zip(entries):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as z:
        for name, data in entries.items():
            z.writestr(name, data)
    return buffer.getvalue()


def pom(name=None, licences=(), parent=None, packaging="pom"):
    parts = ['<project xmlns="http://maven.apache.org/POM/4.0.0">', "<packaging>%s</packaging>" % packaging]
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
        self.texts = self.tmp / "texts"
        self.texts.mkdir()
        (self.texts / "Apache-2.0.txt").write_text(APACHE_TEXT, encoding="utf-8")
        self.lock.write_text(LOCK, encoding="utf-8")
        self.put("com.squareup.okhttp3", "okhttp", "5.1.0", pom("okhttp", [APACHE]))
        self.put("androidx.core", "core", "1.16.0", pom("Core", [APACHE]))

    def put(self, g, a, v, text, artifact=None):
        """Writes the POM; artifact is {entry name: text} for a jar, or (suffix, {...}) for another artifact."""
        folder = self.cache / g / a / v / "0123abcd"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / ("%s-%s.pom" % (a, v))).write_text(text, encoding="utf-8")
        if artifact is not None:
            suffix, entries = artifact if isinstance(artifact, tuple) else (".jar", artifact)
            other = self.cache / g / a / v / "4567ef01"
            other.mkdir(parents=True, exist_ok=True)
            (other / ("%s-%s%s" % (a, v, suffix))).write_bytes(make_zip(entries))

    def run_script(self, *extra):
        return subprocess.run([sys.executable, "-I", str(SCRIPT), "--lockfile", str(self.lock), "--gradle-cache",
                               str(self.cache), "--out", str(self.out), "--licence-texts", str(self.texts), *extra],
                              capture_output=True, text=True)

    def generate(self):
        r = self.run_script()
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        return self.out.read_text(encoding="utf-8")

    def lock_only(self, *lines):
        self.lock.write_text("".join(l + "=releaseRuntimeClasspath\n" for l in lines), encoding="utf-8")

    def test_lists_release_dependencies_with_their_pom_licences(self):
        text = self.generate()
        self.assertTrue(text.startswith("Open-source software in ShellX for Android\n\n"))
        self.assertIn("== Libraries ==\n\n"
                      "Core (androidx.core:core:1.16.0)\n"
                      "License: The Apache Software License, Version 2.0 https://www.apache.org/licenses/LICENSE-2.0.txt\n"
                      "Licence text: Apache License, Version 2.0 (full text in the section \"Licence texts\" below)\n\n"
                      "okhttp (com.squareup.okhttp3:okhttp:5.1.0)\n", text)
        self.assertNotIn("junit", text)
        self.assertNotIn("link-core", text)

    def test_the_apache_text_is_included_once_for_all_apache_libraries(self):
        text = self.generate()
        self.assertEqual(1, text.count("Version 2.0, January 2004"))
        self.assertEqual(2, text.count("Licence text: Apache License, Version 2.0 (full text"))
        self.assertIn("== Licence texts ==\n\nLICENCE TEXT: Apache License, Version 2.0\n\n" + APACHE_TEXT.rstrip() + "\n", text)

    def test_a_library_with_its_own_mit_text_carries_it_with_its_copyright_line(self):
        self.lock_only("org.checkerframework:checker-qual:3.43.0")
        self.put("org.checkerframework", "checker-qual", "3.43.0", pom("Checker Qual", [MIT]),
                 {"META-INF/LICENSE.txt": MIT_TEXT, "org/Foo.class": "x"})
        text = self.generate()
        self.assertIn("Checker Qual (org.checkerframework:checker-qual:3.43.0)\n"
                      "License: The MIT License http://opensource.org/licenses/MIT\n"
                      "Licence text of Checker Qual (META-INF/LICENSE.txt in the library):\n\n"
                      + MIT_TEXT.rstrip() + "\n", text)
        self.assertNotIn("== Licence texts ==", text)

    def test_the_text_comes_from_the_classes_jar_inside_an_aar(self):
        self.lock_only("org.example:aarlib:1.0")
        inner = io.BytesIO()
        with zipfile.ZipFile(inner, "w") as z:
            z.writestr("META-INF/LICENSE", MIT_TEXT)
        self.put("org.example", "aarlib", "1.0", pom("Aar lib", [MIT]), (".aar", {"classes.jar": inner.getvalue()}))
        self.assertIn("(META-INF/LICENSE in classes.jar of the library)", self.generate())

    def test_an_artifact_text_without_a_copyright_line_gives_way_to_the_vendored_one(self):
        self.lock_only("org.example:proto:1.0")
        self.put("org.example", "proto", "1.0", pom("Proto", [BSD]),
                 {"META-INF/LICENSE.txt": "Redistribution and use in source and binary forms.\n"})
        r = self.run_script()
        self.assertEqual(1, r.returncode)
        self.assertIn("no licence text with a copyright line for org.example:proto:1.0 (BSD-3-Clause)", r.stderr)
        self.assertIn("org.example_proto.txt", r.stderr)
        (self.texts / "org.example_proto.txt").write_text("Copyright 2008 Example Inc.\n\nRedistribution.\n", encoding="utf-8")
        text = self.generate()
        self.assertIn("Licence text of Proto (vendored shellx-android/scripts/licence-texts/org.example_proto.txt):\n\n"
                      "Copyright 2008 Example Inc.\n", text)
        self.assertNotIn("Redistribution and use in source", text)

    def test_a_missing_text_for_an_mit_library_stops_the_generator_naming_it(self):
        self.lock_only("org.example:nolicence:2.0")
        self.put("org.example", "nolicence", "2.0", pom("No licence", [MIT]), {"org/Foo.class": "x"})
        r = self.run_script()
        self.assertEqual(1, r.returncode)
        self.assertIn("org.example:nolicence:2.0", r.stderr)
        self.assertFalse(self.out.exists())

    def test_apache_text_in_the_artifact_does_not_stand_in_for_the_bsd_part_of_a_dual_licence(self):
        self.lock_only("org.example:dual:1.0")
        self.put("org.example", "dual", "1.0", pom("Dual", [APACHE, BSD]),
                 {"META-INF/LICENSE.txt": "Copyright 2020 X\n" + APACHE_TEXT})
        r = self.run_script()
        self.assertEqual(1, r.returncode)
        self.assertIn("org.example:dual:1.0 (BSD-3-Clause)", r.stderr)

    def test_a_notice_file_is_reproduced(self):
        self.lock_only("jakarta.inject:jakarta.inject-api:2.0.1")
        self.put("jakarta.inject", "jakarta.inject-api", "2.0.1", pom("Jakarta Inject", [APACHE]),
                 {"META-INF/NOTICE.md": "# Notices\n\nThis content is produced by the Eclipse project.\n"})
        self.assertIn("Notice of Jakarta Inject (META-INF/NOTICE.md in the library):\n\n"
                      "# Notices\n\nThis content is produced by the Eclipse project.\n", self.generate())

    def test_terms_licences_keep_name_and_url_and_say_so(self):
        self.lock_only("com.google.android.gms:play-services-tasks:18.4.0")
        self.put("com.google.android.gms", "play-services-tasks", "18.4.0", pom("Tasks", [SDK]))
        text = self.generate()
        self.assertIn("Tasks (com.google.android.gms:play-services-tasks:18.4.0)\n"
                      "License: Android Software Development Kit License https://developer.android.com/studio/terms.html "
                      "(terms of use, not an open-source licence: no licence text is reproduced here)\n", text)
        self.assertNotIn("Version 2.0, January 2004", text)

    def embedded(self, components, form="json"):
        body, index, meta = b"", {}, []
        for name, text in components:
            raw = ("\n\n%s:\n\n%s\n" % (name, text)).encode("utf-8")
            start = len(body) + len(("\n\n%s:\n\n" % name).encode("utf-8"))
            length = len(text.encode("utf-8")) + 1
            index[name] = {"start": start, "length": length}
            meta.append("%d:%d %s\n" % (start, length, name))
            body += raw
        if form == "json":
            return {"third_party_licenses.txt": body, "third_party_licenses.json": json.dumps(index)}
        return {"res/raw/third_party_licenses": body, "res/raw/third_party_license_metadata": "".join(meta)}

    def test_the_notices_embedded_in_an_aar_are_listed_with_their_texts_and_attributed(self):
        self.lock_only("com.google.android.gms:play-services-basement:18.9.0", "com.google.android.gms:play-services-base:18.9.0")
        comps = [("Animal Sniffer", "The MIT License\nCopyright (c) 2008 Kohsuke Kawaguchi"), ("Guava JDK5", "Apache stuff")]
        self.put("com.google.android.gms", "play-services-basement", "18.9.0", pom("Basement", [SDK]), (".aar", self.embedded(comps)))
        self.put("com.google.android.gms", "play-services-base", "18.9.0", pom("Base", [SDK]),
                 (".aar", self.embedded(comps[:1] + [("Kotlin", "Kotlin text")], "metadata")))
        text = self.generate()
        self.assertIn("== Notices embedded in Google libraries ==", text)
        self.assertIn("Embedded in com.google.android.gms:play-services-base:18.9.0\n"
                      "  Animal Sniffer (text E1)\n  Kotlin (text E2)\n\n"
                      "Embedded in com.google.android.gms:play-services-basement:18.9.0\n"
                      "  Animal Sniffer (text E1)\n  Guava JDK5 (text E3)\n", text)
        self.assertEqual(1, text.count("Copyright (c) 2008 Kohsuke Kawaguchi"))
        self.assertIn("EMBEDDED NOTICE TEXT E1: Animal Sniffer\n\nThe MIT License\nCopyright (c) 2008 Kohsuke Kawaguchi\n", text)
        self.assertIn("EMBEDDED NOTICE TEXT E2: Kotlin\n\nKotlin text\n", text)

    def test_without_embedded_notices_there_is_no_such_section(self):
        self.assertNotIn("Notices embedded", self.generate())

    def test_the_output_is_reproducible(self):
        first = self.generate()
        self.out.unlink()
        self.assertEqual(first, self.generate())
        self.assertNotIn(str(self.tmp), first)

    def test_the_header_counts_the_libraries(self):
        self.assertTrue(self.generate().startswith("Open-source software in ShellX for Android\n\nLibraries: 2\n\n"))

    def test_a_template_without_a_holder_is_not_a_licence_text(self):
        self.lock_only("org.example:bare:1.0")
        bare = ("MIT License\n\nCopyright (c) <year> <copyright holders>\n\nPermission is hereby granted. "
                "The above copyright notice and this permission notice shall be included.\n")
        self.put("org.example", "bare", "1.0", pom("Bare", [MIT], packaging="jar"), {"META-INF/LICENSE": bare})
        r = self.run_script()
        self.assertEqual(1, r.returncode)
        self.assertIn("org.example:bare:1.0", r.stderr)
        (self.texts / "org.example_bare.txt").write_text(bare, encoding="utf-8")
        r = self.run_script()
        self.assertEqual(1, r.returncode)
        self.assertIn("names no holder", r.stderr)

    def test_a_copyright_line_with_a_name_but_no_year_counts(self):
        self.lock_only("org.example:named:1.0")
        self.put("org.example", "named", "1.0", pom("Named", [MIT], packaging="jar"),
                 {"META-INF/LICENSE": "Copyright (c) The Example Authors\n\nPermission is hereby granted.\n"})
        self.assertIn("Copyright (c) The Example Authors", self.generate())

    def test_an_artifact_missing_from_the_cache_is_an_error(self):
        self.lock_only("org.example:half:1.0")
        self.put("org.example", "half", "1.0", pom("Half", [APACHE], packaging="jar"))
        r = self.run_script()
        self.assertEqual(1, r.returncode)
        self.assertIn("no jar or aar for org.example:half:1.0", r.stderr)
        self.assertIn("run shellx-android/scripts/dev.sh lock and a build first", r.stderr)
        (self.cache / "org.example" / "half" / "1.0" / "0123abcd" / "half-1.0.module").write_text("{}", encoding="utf-8")
        self.generate()

    def test_a_notice_file_over_the_size_limit_is_an_error(self):
        self.lock_only("org.example:big:1.0")
        self.put("org.example", "big", "1.0", pom("Big", [APACHE], packaging="jar"),
                 {"META-INF/NOTICE.txt": "n" * 400_001})
        r = self.run_script()
        self.assertEqual(1, r.returncode)
        self.assertIn("META-INF/NOTICE.txt", r.stderr)
        self.assertIn("org.example:big:1.0", r.stderr)

    def test_a_big_licence_file_that_equals_the_embedded_notices_is_not_an_error(self):
        self.lock_only("com.google.android.play:core-common:2.0.3")
        files = self.embedded([("Big component", "t" * 450_000)])
        files["LICENSE"] = files["third_party_licenses.txt"]
        self.put("com.google.android.play", "core-common", "2.0.3", pom("Core common", [SDK], packaging="aar"), (".aar", files))
        self.assertEqual(1, self.generate().count("EMBEDDED NOTICE TEXT E1"))

    def bundled(self, entries, **kw):
        self.lock_only("org.example:data:1.0")
        self.put("org.example", "data", "1.0", pom("Data lib", [APACHE], packaging="aar"), (".aar", entries))
        return kw

    def test_bundled_data_in_assets_stops_the_generator_naming_it(self):
        self.bundled({"assets/list.dat": "x", "classes.jar": make_zip({"a/B.class": "c"})})
        r = self.run_script()
        self.assertEqual(1, r.returncode)
        self.assertIn("org.example:data:1.0", r.stderr)
        self.assertIn("assets/list.dat", r.stderr)
        self.assertIn("bundled-files-allowlist.txt", r.stderr)

    def test_native_libraries_raw_resources_and_big_resources_are_flagged_but_metadata_is_not(self):
        self.bundled({"jni/arm64-v8a/libx.so": "s", "res/raw/keep.xml": "k", "libs/inner.jar": "j" * 20_000,
                      "res/values/values.xml": "v" * 30_000, "baseline-prof.txt": "b" * 30_000,
                      "META-INF/proguard/x.pro": "p" * 30_000, "META-INF/MANIFEST.MF": "m" * 30_000,
                      "AndroidManifest.xml": "<m/>", "R.txt": "r" * 30_000, "annotations.zip": "z" * 30_000,
                      "classes.jar": make_zip({"a/B.class": "c" * 30_000, "META-INF/x.kotlin_module": "k" * 30_000,
                                               "data/table.bin": "d" * 20_000})})
        r = self.run_script()
        self.assertEqual(1, r.returncode)
        for flagged in ("jni/arm64-v8a/libx.so", "res/raw/keep.xml", "libs/inner.jar", "classes.jar!/data/table.bin"):
            self.assertIn(flagged, r.stderr)
        for fine in ("values.xml", "baseline-prof", "x.pro", "MANIFEST.MF", "R.txt", "annotations.zip", "B.class", "kotlin_module"):
            self.assertNotIn(fine, r.stderr)

    def test_a_reviewed_allowlist_row_with_a_reason_lets_a_bundled_file_pass(self):
        self.bundled({"assets/list.dat": "x"})
        allow = self.texts / "bundled-files-allowlist.txt"
        allow.write_text("# reviewed\norg.example:data | assets/*.dat | the project's own data, Apache-2.0\n", encoding="utf-8")
        self.generate()
        allow.write_text("org.example:data | assets/*.dat |\n", encoding="utf-8")
        r = self.run_script()
        self.assertEqual(1, r.returncode)
        self.assertIn("needs a reason", r.stderr)

    def test_an_extra_notice_covers_the_bundled_files_and_names_a_shared_text(self):
        self.bundled({"assets/list.dat": "x"})
        (self.texts / "MPL-2.0.txt").write_text("Mozilla Public License Version 2.0\n\nfull terms\n", encoding="utf-8")
        (self.texts / "org.example_data.extra.txt").write_text(
            "@licence-text: MPL-2.0\nThe artifact includes list.dat, subject to the terms of the Mozilla Public License, v. 2.0.\n",
            encoding="utf-8")
        text = self.generate()
        self.assertIn("Additional notice for Data lib (vendored shellx-android/scripts/licence-texts/org.example_data.extra.txt):\n\n"
                      "The artifact includes list.dat, subject to the terms of the Mozilla Public License, v. 2.0.\n", text)
        self.assertNotIn("@licence-text", text)
        self.assertIn("Licence text: Mozilla Public License, Version 2.0 (full text in the section \"Licence texts\" below)", text)
        self.assertEqual(1, text.count("full terms"))
        self.assertIn("LICENCE TEXT: Mozilla Public License, Version 2.0\n\nMozilla Public License Version 2.0\n\nfull terms\n", text)
        self.assertLess(text.index("LICENCE TEXT: Apache"), text.index("LICENCE TEXT: Mozilla"))

    def test_an_extra_notice_naming_an_unknown_shared_text_is_an_error(self):
        self.bundled({"classes.jar": make_zip({"a/B.class": "c"})})
        (self.texts / "org.example_data.extra.txt").write_text("@licence-text: GPL-9\nHello\n", encoding="utf-8")
        r = self.run_script()
        self.assertEqual(1, r.returncode)
        self.assertIn("GPL-9", r.stderr)

    def test_a_licence_from_the_parent_pom(self):
        self.put("androidx", "parent", "1", pom(licences=[("Some Permissive Licence", "https://example.org/l")]))
        self.put("androidx.core", "core", "1.16.0", pom("Core", parent=("androidx", "parent", "1")),
                 {"LICENSE": "Copyright 2020 Core\n"})
        self.assertIn("Core (androidx.core:core:1.16.0)\nLicense: Some Permissive Licence https://example.org/l\n",
                      self.generate())

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
