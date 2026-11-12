"""Tests for release/mobile/play/store_assets.py (plan 3H): listing limits, icon, feature graphics, screenshots.

Run: python3 -m unittest discover -s release/mobile/tests -t release/mobile/tests -v
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "release" / "mobile" / "play"))
import store_assets as sa  # noqa: E402

LISTING = REPO / "release/mobile/play/listing"
TOOLS = shutil.which("rsvg-convert") is not None and shutil.which("sips") is not None


def make_listing(root: Path, **overrides) -> Path:
    for locale in ("en-US", "vi"):
        for name in ("title.txt", "short-description.txt", "full-description.txt", "release-notes.txt",
                     "feature-graphic-tagline.txt"):
            path = root / locale / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(overrides.get("%s/%s" % (locale, name), "ShellX") + "\n", encoding="utf-8")
    return root


def svg_png(width: int, height: int, body: str = "") -> bytes:
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d"><rect width="%d" height="%d" '
           'fill="#0B0716" fill-opacity="0.9"/>%s</svg>' % (width, height, width, height, body))
    return subprocess.run(["rsvg-convert"], input=svg.encode(), capture_output=True, check=True).stdout


class ListingTest(unittest.TestCase):
    def test_the_real_listing_fits_google_play(self):
        self.assertEqual([], sa.listing_problems(LISTING))

    def test_limits_are_counted_in_characters(self):
        with tempfile.TemporaryDirectory() as tmp:
            found = sa.listing_problems(make_listing(Path(tmp) / "long", **{
                "en-US/title.txt": "x" * 31, "vi/short-description.txt": "ệ" * 81,
                "en-US/full-description.txt": "y" * 4001, "vi/release-notes.txt": "z" * 501,
                "vi/feature-graphic-tagline.txt": "w" * 41}))
            self.assertIn("en-US/title.txt: 31 characters, Google Play allows 30", found)
            self.assertIn("vi/short-description.txt: 81 characters, Google Play allows 80", found)
            self.assertIn("en-US/full-description.txt: 4001 characters, Google Play allows 4000", found)
            self.assertIn("vi/release-notes.txt: 501 characters, Google Play allows 500", found)
            self.assertIn("vi/feature-graphic-tagline.txt: 41 characters, the feature graphic fits 40", found)
            self.assertEqual([], sa.listing_problems(make_listing(Path(tmp) / "ok", **{"vi/short-description.txt": "ệ" * 80})))

    def test_refuses_decomposed_text_emoji_banned_words_and_missing_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_listing(Path(tmp), **{"vi/title.txt": "Vie\u0323\u0302t",  # decomposed: e + dot below + circumflex,
                                              "en-US/short-description.txt": "The best terminal \U0001F680",
                                              "vi/short-description.txt": "Ứng dụng miễn phí"})
            (root / "en-US" / "release-notes.txt").unlink()
            found = sa.listing_problems(root)
            self.assertIn("vi/title.txt: not in composed form (NFC)", found)
            self.assertIn("en-US/short-description.txt: contains an emoji", found)
            self.assertIn('en-US/short-description.txt: uses "best", which Google Play\'s metadata policy bans in '
                          'titles and short descriptions', found)
            self.assertIn('vi/short-description.txt: uses "miễn phí", which Google Play\'s metadata policy bans in '
                          'titles and short descriptions', found)
            self.assertIn("en-US/release-notes.txt: missing", found)

    def test_every_listing_gets_4_to_8_shots(self):
        for locale in ("en-US", "vi"):
            count = sum(1 for _, _, locales in sa.SHOTS if locale in locales)
            self.assertTrue(4 <= count <= 8, "%s has %d shots" % (locale, count))

    def test_the_listing_quotes_the_apps_own_labels(self):
        res = REPO / "shellx-android/app/src/main/res"
        if not (res / "values" / "strings.xml").is_file():
            self.skipTest("no generated Android strings in this checkout")
        self.assertEqual([], sa.quoted_label_problems(res))


@unittest.skipUnless(TOOLS, "needs rsvg-convert and sips")
class GraphicsTest(unittest.TestCase):
    def test_the_icon_is_a_512_px_32_bit_png_under_1_mib(self):
        with tempfile.TemporaryDirectory() as tmp:
            icon = sa.render_icon(REPO / "design/shellx-logo.svg", Path(tmp))
            self.assertEqual("icon-512.png", icon.name)
            self.assertEqual((512, 512, 6), sa.png_info(icon.read_bytes()))
            self.assertLess(icon.stat().st_size, 1024 * 1024)

    def test_adding_alpha_keeps_every_pixel(self):
        rgb = subprocess.run(["rsvg-convert"], input=(
            b'<svg xmlns="http://www.w3.org/2000/svg" width="9" height="7"><rect width="9" height="7" fill="#1C1438"/>'
            b'<rect x="3" width="3" height="7" fill="#7DF7BE"/></svg>'), capture_output=True, check=True).stdout
        self.assertEqual((9, 7, 2), sa.png_info(rgb))
        rgba = sa.png_add_alpha(rgb)
        self.assertEqual((9, 7, 6), sa.png_info(rgba))
        rows = zlib.decompress(b"".join(body for kind, body in sa.png_chunks(rgba) if kind == b"IDAT"))
        dark, mint = (0x1C, 0x14, 0x38, 255), (0x7D, 0xF7, 0xBE, 255)
        for y in range(7):
            row = rows[y * 37:(y + 1) * 37]  # a filter byte, then 9 RGBA pixels
            self.assertEqual(0, row[0])
            self.assertEqual([dark] * 3 + [mint] * 3 + [dark] * 3,
                             [tuple(row[1 + 4 * x:5 + 4 * x]) for x in range(9)])

    def test_feature_graphics_are_1024_by_500_jpegs_without_alpha(self):
        with tempfile.TemporaryDirectory() as tmp:
            for locale in ("en-US", "vi"):
                tagline = (LISTING / locale / "feature-graphic-tagline.txt").read_text(encoding="utf-8").strip()
                path = sa.render_feature_graphic(REPO / "release/mobile/play/feature-graphic.svg", tagline, locale, Path(tmp))
                self.assertEqual("feature-graphic-%s.jpg" % locale, path.name)
                self.assertEqual((1024, 500, 3), sa.jpeg_info(path.read_bytes()))

    def test_screenshots_become_jpegs_per_theme_and_locale(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, out = Path(tmp) / "src", Path(tmp) / "out"
            src.mkdir()
            png = svg_png(1080, 1920)
            for nn, slug, _locales in sa.SHOTS:
                for theme in ("light", "dark"):
                    for lang in ("en", "vi"):
                        (src / ("store-%s-%s-%s-%s.png" % (nn, slug, theme, lang))).write_bytes(png)
            (src / "launch-dark-en.png").write_bytes(png)  # other render tests are ignored
            written, problems = sa.prepare_screenshots(src, out)
            self.assertEqual([], problems)
            names = {str(p.relative_to(out)) for p in written}
            for nn, slug, locales in sa.SHOTS:
                for theme in ("light", "dark"):
                    for locale in ("en-US", "vi"):
                        path = "screenshots/%s/%s/%s-%s.jpg" % (theme, locale, nn, slug)
                        self.assertEqual(locale in locales, path in names, path)
            self.assertEqual(2 * sum(len(locales) for _, _, locales in sa.SHOTS), len(written))
            self.assertEqual((1080, 1920, 3), sa.jpeg_info((out / "screenshots/light/vi/01-home.jpg").read_bytes()))

    def test_screenshots_refuse_a_wrong_size_and_a_short_set(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "src"
            src.mkdir()
            (src / "store-01-home-dark-en.png").write_bytes(svg_png(1179, 2556))
            _written, problems = sa.prepare_screenshots(src, Path(tmp) / "out")
            self.assertIn("store-01-home-dark-en.png is 1179x2556, expected 1080x1920", problems)
            self.assertIn("missing store-02-permission-dark-en.png", problems)
            self.assertIn("dark/en-US has 0 screenshots, Google Play needs 4 to 8 (store promotion needs 4)", problems)


if __name__ == "__main__":
    unittest.main()
