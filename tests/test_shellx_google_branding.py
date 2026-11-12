#!/usr/bin/env python3
"""The desktop releases refuse a Google button without Google's official mark
(scripts/shellx/check-google-branding.py and the hooks in make-dmg.sh / build-windows-cross.sh).
    python3 tests/test_shellx_google_branding.py
"""

from __future__ import annotations

import os
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHECK = ROOT / "scripts" / "shellx" / "check-google-branding.py"

MAC_DIR = "Assets.xcassets/GoogleG.imageset"
MAC_CONTENTS = f"{MAC_DIR}/Contents.json"
MAC_PNG = f"{MAC_DIR}/google-g.png"
WIN_PNG = "windows/shellx-app/assets/google/google-g.png"
MAC_FONT = "Resources/Fonts/GoogleSans-Medium.ttf"
MAC_OFL = "Resources/Fonts/GoogleSans-OFL.txt"
WIN_FONT = "windows/shellx-app/assets/fonts/GoogleSans-Medium.ttf"
WIN_OFL = "windows/shellx-app/assets/fonts/GoogleSans-OFL.txt"
LICENCE = "SIL Open Font License, Version 1.1"


def png(w: int, h: int) -> bytes:
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    chunk = struct.pack(">I", len(ihdr)) + b"IHDR" + ihdr + struct.pack(">I", zlib.crc32(b"IHDR" + ihdr))
    return b"\x89PNG\r\n\x1a\n" + chunk


def put(root: Path, rel: str, data: bytes | str) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data if isinstance(data, bytes) else data.encode())


def marks(root: Path) -> None:
    put(root, MAC_CONTENTS, '{"images":[{"filename":"google-g.png","idiom":"universal"}],"info":{"author":"xcode","version":1}}')
    put(root, MAC_PNG, png(80, 80))
    put(root, WIN_PNG, png(80, 80))


def complete(root: Path) -> None:
    marks(root)
    for font, ofl in ((MAC_FONT, MAC_OFL), (WIN_FONT, WIN_OFL)):
        put(root, font, b"\x00\x01\x00\x00" + b"\x00" * 16)
        put(root, ofl, f"... {LICENCE} ...")


def run(*args: str, env: dict | None = None) -> subprocess.CompletedProcess:
    full_env = {**os.environ, **(env or {})}
    full_env.pop("SHELLX_GOOGLE_BRANDING_ROOT", None) if env is None else None
    return subprocess.run([sys.executable, "-I", str(CHECK), *args], capture_output=True, text=True, env=full_env)


def git(root: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(root), "-c", "user.name=t", "-c", "user.email=t@t", *args],
                   check=True, capture_output=True)


class GoogleBrandingCheck(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name) / "tree"
        self.root.mkdir()

    def tearDown(self):
        self._tmp.cleanup()

    def test_an_empty_tree_names_every_missing_mark_file(self):
        r = run("--root", str(self.root))
        self.assertEqual(r.returncode, 1)
        for rel in (MAC_CONTENTS, MAC_PNG, WIN_PNG):
            self.assertIn(f"missing: {rel}", r.stderr)

    def test_a_complete_tree_passes(self):
        complete(self.root)
        r = run("--root", str(self.root))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("google branding: OK", r.stdout)

    def test_fonts_are_optional_but_never_without_their_licence(self):
        marks(self.root)
        r = run("--root", str(self.root))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("font: mac uses the system font", r.stdout)
        self.assertIn("font: windows uses the system font", r.stdout)
        put(self.root, MAC_FONT, b"\x00\x01\x00\x00" + b"\x00" * 16)
        r = run("--root", str(self.root))
        self.assertEqual(r.returncode, 1)
        self.assertIn(f"bad: {MAC_FONT} (no SIL OFL 1.1 licence beside it)", r.stderr)

    def test_a_mark_that_is_not_80_px_is_bad(self):
        complete(self.root)
        put(self.root, MAC_PNG, png(40, 40))
        r = run("--root", str(self.root))
        self.assertEqual(r.returncode, 1)
        self.assertIn(f"bad: {MAC_PNG}", r.stderr)

    def test_git_rev_reads_the_commit_not_the_working_tree(self):
        complete(self.root)
        git(self.root, "init", "-q")
        git(self.root, "add", "-A")
        git(self.root, "commit", "-q", "-m", "marks")
        for rel in (MAC_CONTENTS, MAC_PNG, WIN_PNG, MAC_FONT, MAC_OFL, WIN_FONT, WIN_OFL):
            (self.root / rel).unlink()
        r = run("--root", str(self.root), "--git-rev", "HEAD")
        self.assertEqual(r.returncode, 0, r.stderr)
        git(self.root, "add", "-A")
        git(self.root, "commit", "-q", "-m", "remove")
        r = run("--root", str(self.root), "--git-rev", "HEAD")
        self.assertEqual(r.returncode, 1)

    def test_make_dmg_refuses_without_the_mark(self):
        r = subprocess.run(
            [str(ROOT / "scripts/shellx/release/make-dmg.sh"), "/nonexistent/ShellX.app", "1.8.0", self.root.as_posix()],
            capture_output=True, text=True, env={**os.environ, "SHELLX_GOOGLE_BRANDING_ROOT": str(self.root)})
        self.assertEqual(r.returncode, 1)
        self.assertIn(f"missing: {MAC_PNG}", r.stderr)
        self.assertNotIn("app bundle not found", r.stderr)

    def test_windows_cross_build_refuses_without_the_mark(self):
        git(self.root, "init", "-q")
        git(self.root, "commit", "-q", "--allow-empty", "-m", "empty")
        r = subprocess.run(
            [str(ROOT / "scripts/shellx/release/build-windows-cross.sh"), self.root.as_posix() + "/out"],
            capture_output=True, text=True, env={
                **os.environ, "SHELLX_GOOGLE_BRANDING_ROOT": str(self.root),
                # Made-up Desktop OAuth client, so the build reaches the branding check (a build needs one).
                "SHELLX_GOOGLE_DESKTOP_CLIENT_ID": "123456789012-fakefakefake.apps.googleusercontent.com",
                "SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET": "GOCSPX-fake-0123456"})
        self.assertEqual(r.returncode, 1)
        self.assertIn(f"missing: {WIN_PNG}", r.stderr)


if __name__ == "__main__":
    unittest.main()
