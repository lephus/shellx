#!/usr/bin/env python3
"""Behavior of tests/shellx_guard.py, the helper every ShellX guard uses."""

import hashlib
import os
import shutil
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import shellx_guard  # noqa: E402
from shellx_guard import ROOT, offenders, png_size, read, sha256  # noqa: E402


class ShellXGuardTests(unittest.TestCase):
    def setUp(self):
        # A scratch tree inside the repository, so repo-relative paths apply.
        self.scratch = Path(tempfile.mkdtemp(prefix=".shellx-guard-test-", dir=ROOT / "tests"))
        self.rel = self.scratch.relative_to(ROOT).as_posix()
        self.addCleanup(shutil.rmtree, self.scratch)
        (self.scratch / "a.txt").write_text("one\nneedle here\nthree\n", encoding="utf-8")
        (self.scratch / "sub").mkdir()
        (self.scratch / "sub" / "b.txt").write_text("needle\n", encoding="utf-8")
        (self.scratch / "bin.dat").write_bytes(b"needle\0binary")
        (self.scratch / ".git").mkdir()
        (self.scratch / ".git" / "c.txt").write_text("needle\n", encoding="utf-8")

    def test_reports_path_and_line_of_each_hit(self):
        self.assertEqual(
            offenders(r"needle", roots=[self.rel], allow=[]),
            [f"{self.rel}/a.txt:2", f"{self.rel}/sub/b.txt:1"],
        )

    def test_allow_entries_skip_a_file_or_a_directory(self):
        self.assertEqual(
            offenders(r"needle", roots=[self.rel], allow=[(f"{self.rel}/a.txt", "fixture")]),
            [f"{self.rel}/sub/b.txt:1"],
        )
        self.assertEqual(
            offenders(r"needle", roots=[self.rel], allow=[(f"{self.rel}/sub/", "fixture dir")]),
            [f"{self.rel}/a.txt:2"],
        )

    def test_allow_entries_need_a_reason(self):
        with self.assertRaises(ValueError):
            offenders(r"needle", roots=[self.rel], allow=[(f"{self.rel}/a.txt", " ")])

    def test_missing_roots_are_ignored_and_paths_do_not_depend_on_cwd(self):
        cwd = os.getcwd()
        os.chdir(tempfile.gettempdir())
        try:
            self.assertEqual(offenders(r"needle", roots=[f"{self.rel}/sub", "no/such/dir"], allow=[]),
                             [f"{self.rel}/sub/b.txt:1"])
            self.assertEqual(read(f"{self.rel}/sub/b.txt"), "needle\n")
        finally:
            os.chdir(cwd)

    def test_png_size_and_sha256(self):
        def chunk(kind, data):
            return len(data).to_bytes(4, "big") + kind + data + zlib.crc32(kind + data).to_bytes(4, "big")

        png = (b"\x89PNG\r\n\x1a\n"
               + chunk(b"IHDR", (3).to_bytes(4, "big") + (2).to_bytes(4, "big") + b"\x08\x02\x00\x00\x00"))
        (self.scratch / "p.png").write_bytes(png)
        self.assertEqual(png_size(f"{self.rel}/p.png"), (3, 2))
        with self.assertRaises(ValueError):
            png_size(f"{self.rel}/a.txt")
        self.assertEqual(sha256(f"{self.rel}/sub/b.txt"), hashlib.sha256(b"needle\n").hexdigest())

    def test_root_is_the_repository(self):
        self.assertTrue((shellx_guard.ROOT / "cmux.xcodeproj").is_dir())


if __name__ == "__main__":
    unittest.main()
