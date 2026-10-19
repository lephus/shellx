#!/usr/bin/env python3
"""Guard: ShellX app icons match their declared sizes and the logo source stays in sync.

Usage (from the repo root):
    python3 tests/test_shellx_app_icon.py
"""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from shellx_look_guard import png_size, read, sha256  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
# sha256 of web/public/favicon.svg (= design/shellx-logo.svg) at copy time.
EXPECTED_SHA256 = "b160556d68f67ad29abb66be8d61eaf709f30b485448826a8725a038e25518d8"
APPICONSETS = ["AppIcon", "AppIcon-Debug", "AppIcon-RC", "AppIcon-Nightly"]
XC = "Assets.xcassets"


class ShellXAppIconTests(unittest.TestCase):
    def test_app_icon_sizes(self):
        for name in APPICONSETS:
            with self.subTest(appiconset=name):
                contents = json.loads(read(f"{XC}/{name}.appiconset/Contents.json"))
                checked = 0
                for img in contents["images"]:
                    filename = img.get("filename")
                    if not filename:  # slot declared without a file: nothing to measure
                        continue
                    w, h = png_size(f"{XC}/{name}.appiconset/{filename}")
                    side = int(float(img["size"].split("x")[0]) * int(img["scale"][0]))
                    self.assertEqual((w, h), (side, side), f"{name}/{filename}")
                    checked += 1
                self.assertGreater(checked, 0, f"{name} has no icon files")

    def test_logo_source_matches_web(self):
        self.assertEqual(sha256("design/shellx-logo.svg"), EXPECTED_SHA256)
        self.assertEqual(sha256("design/shellx-logo.svg"), sha256("web/public/favicon.svg"))

    def test_shellx_logo_imageset_present(self):
        contents = json.loads(read(f"{XC}/ShellXLogo.imageset/Contents.json"))
        files = [i["filename"] for i in contents["images"] if "filename" in i]
        self.assertTrue(files, "ShellXLogo.imageset lists no files")
        for f in files:
            self.assertTrue((ROOT / XC / "ShellXLogo.imageset" / f).is_file(), f)


if __name__ == "__main__":
    unittest.main()
