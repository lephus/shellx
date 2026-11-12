#!/usr/bin/env python3
"""Google Play store assets (plan 3H): checks the listing text and renders the icon and graphics.

  python3 -I release/mobile/play/store_assets.py listing
  python3 -I release/mobile/play/store_assets.py graphics [--out DIR]
  python3 -I release/mobile/play/store_assets.py screenshots --from DIR [--out DIR]

Standard library plus the rsvg-convert and sips commands.
"""
from __future__ import annotations

import argparse
import re
import struct
import subprocess
import sys
import tempfile
import unicodedata
import zlib
from pathlib import Path
from typing import Iterator, List, Optional, Tuple
from xml.sax.saxutils import escape

REPO = Path(__file__).resolve().parents[3]
LISTING = REPO / "release/mobile/play/listing"
RES = REPO / "shellx-android/app/src/main/res"

LOCALES = ("en-US", "vi")
FILES = ("title.txt", "short-description.txt", "full-description.txt", "release-notes.txt",
         "feature-graphic-tagline.txt")
LIMITS = {
    "title.txt": (30, "Google Play allows 30"),
    "short-description.txt": (80, "Google Play allows 80"),
    "full-description.txt": (4000, "Google Play allows 4000"),
    "release-notes.txt": (500, "Google Play allows 500"),
    "feature-graphic-tagline.txt": (40, "the feature graphic fits 40"),
}
BANNED = {
    "en-US": ("best", "#1", "top", "free", "new", "sale", "discount", "cheap", "million"),
    "vi": ("tốt nhất", "số 1", "hàng đầu", "miễn phí", "mới", "giảm giá", "khuyến mãi"),
}
QUOTED_LABELS = {
    "en-US": ("Try without an account", "Settings", "Account", "Delete Account…"),
    "vi": ("Xem thử không cần tài khoản", "Cài đặt", "Tài khoản", "Xoá tài khoản…"),
}
# (NN, slug, listing locales). Shots 04 and 05 show the demo's Vietnamese chat and plan text.
SHOTS = (
    ("01", "home", ("vi",)),
    ("02", "permission", ("en-US", "vi")),
    ("03", "terminal", ("en-US", "vi")),
    ("04", "agent", ("vi",)),
    ("05", "plan", ("vi",)),
    ("06", "first-mac", ("en-US", "vi")),
    ("07", "settings", ("en-US",)),
)
SHOT_SIZE = (1080, 1920)


def _is_emoji(ch: str) -> bool:
    cp = ord(ch)
    return 0x1F000 <= cp <= 0x1FAFF or 0x2600 <= cp <= 0x27BF or cp == 0xFE0F


def listing_problems(root: Path) -> List[str]:
    found: List[str] = []
    for locale in LOCALES:
        for name in FILES:
            label = "%s/%s" % (locale, name)
            path = Path(root) / locale / name
            if not path.is_file():
                found.append("%s: missing" % label)
                continue
            text = path.read_text(encoding="utf-8")
            if text.endswith("\n"):
                text = text[:-1]
            limit, limit_text = LIMITS[name]
            if len(text) > limit:
                found.append("%s: %d characters, %s" % (label, len(text), limit_text))
            if not unicodedata.is_normalized("NFC", text):
                found.append("%s: not in composed form (NFC)" % label)
            if any(_is_emoji(ch) for ch in text):
                found.append("%s: contains an emoji" % label)
            if name in ("title.txt", "short-description.txt"):
                for word in BANNED[locale]:
                    if re.search(r"(?<![\w#])" + re.escape(word) + r"(?!\w)", text, re.IGNORECASE):
                        found.append('%s: uses "%s", which Google Play\'s metadata policy bans in '
                                     'titles and short descriptions' % (label, word))
    return found


def _app_strings(folder: Path) -> List[str]:
    import xml.etree.ElementTree as ET
    texts: List[str] = []
    for xml in sorted(folder.glob("strings*.xml")):
        for node in ET.parse(str(xml)).getroot().iter("string"):
            texts.append("".join(node.itertext()).replace("\\'", "'").replace('\\"', '"'))
    return texts


def quoted_label_problems(res: Path) -> List[str]:
    found: List[str] = []
    for locale, folder in (("en-US", "values"), ("vi", "values-vi")):
        have = set(_app_strings(Path(res) / folder))
        for label in QUOTED_LABELS[locale]:
            if label not in have:
                found.append('the %s listing quotes "%s", which is not an app string in %s'
                             % (locale, label, folder))
    return found


def png_chunks(data: bytes) -> Iterator[Tuple[bytes, bytes]]:
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos = 8
    while pos + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        yield kind, data[pos + 8:pos + 8 + length]
        pos += 12 + length


def _ihdr(data: bytes) -> Tuple[int, int, int, int, int]:
    for kind, body in png_chunks(data):
        if kind == b"IHDR":
            width, height, depth, colour, _comp, _filt, interlace = struct.unpack(">IIBBBBB", body[:13])
            return width, height, colour, depth, interlace
    raise ValueError("PNG without IHDR")


def png_info(data: bytes) -> Tuple[int, int, int]:
    width, height, colour, _depth, _interlace = _ihdr(data)
    return width, height, colour


def jpeg_info(data: bytes) -> Tuple[int, int, int]:
    if data[:2] != b"\xff\xd8":
        raise ValueError("not a JPEG")
    pos = 2
    while pos + 4 <= len(data):
        if data[pos] != 0xFF:
            raise ValueError("bad JPEG marker")
        marker = data[pos + 1]
        if marker == 0xFF:
            pos += 1
            continue
        if marker == 0x01 or 0xD0 <= marker <= 0xD7:
            pos += 2
            continue
        length = struct.unpack(">H", data[pos + 2:pos + 4])[0]
        if marker in (0xC0, 0xC1, 0xC2):
            _precision, height, width, components = struct.unpack(">BHHB", data[pos + 4:pos + 10])
            return width, height, components
        pos += 2 + length
    raise ValueError("JPEG without a frame header")


def _chunk(kind: bytes, body: bytes) -> bytes:
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)


def png_add_alpha(data: bytes) -> bytes:
    width, height, colour, depth, interlace = _ihdr(data)
    if colour == 6:
        return data
    if colour != 2 or depth != 8 or interlace != 0:
        raise ValueError("only 8-bit RGB PNGs without interlace can get an alpha channel")
    raw = zlib.decompress(b"".join(body for kind, body in png_chunks(data) if kind == b"IDAT"))
    stride = width * 3
    if len(raw) != height * (stride + 1):
        raise ValueError("unexpected PNG data length")
    prev = bytearray(stride)
    out = bytearray()
    for y in range(height):
        base = y * (stride + 1)
        ftype = raw[base]
        row = bytearray(raw[base + 1:base + 1 + stride])
        for i in range(stride):
            a = row[i - 3] if i >= 3 else 0
            b = prev[i]
            c = prev[i - 3] if i >= 3 else 0
            if ftype == 0:
                add = 0
            elif ftype == 1:
                add = a
            elif ftype == 2:
                add = b
            elif ftype == 3:
                add = (a + b) // 2
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                add = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
            else:
                raise ValueError("bad PNG filter")
            row[i] = (row[i] + add) & 0xFF
        out.append(0)
        for x in range(width):
            out += row[3 * x:3 * x + 3]
            out.append(255)
        prev = row
    return (b"\x89PNG\r\n\x1a\n"
            + _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + _chunk(b"IDAT", zlib.compress(bytes(out), 9))
            + _chunk(b"IEND", b""))


def _rsvg(svg: str, width: int, height: int) -> bytes:
    return subprocess.run(["rsvg-convert", "-w", str(width), "-h", str(height), "-f", "png"],
                          input=svg.encode("utf-8"), capture_output=True, check=True).stdout


def _to_jpeg(png: Path, jpg: Path) -> None:
    subprocess.run(["/usr/bin/sips", "-s", "format", "jpeg", "-s", "formatOptions", "95", str(png),
                    "--out", str(jpg)], capture_output=True, check=True)


def render_icon(logo_svg: Path, out_dir: Path) -> Path:
    lines = [ln for ln in Path(logo_svg).read_text(encoding="utf-8").splitlines(True)
             if 'stroke-opacity="0.09"' not in ln]
    svg = "".join(lines).replace(' rx="114"', "")
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / "icon-512.png"
    path.write_bytes(png_add_alpha(_rsvg(svg, 512, 512)))
    return path


def render_feature_graphic(template: Path, tagline: str, locale: str, out_dir: Path) -> Path:
    svg = Path(template).read_text(encoding="utf-8").replace("__TAGLINE__", escape(tagline))
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / ("feature-graphic-%s.jpg" % locale)
    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / "fg.png"
        png.write_bytes(_rsvg(svg, 1024, 500))
        _to_jpeg(png, path)
    return path


def prepare_screenshots(src: Path, out: Path) -> Tuple[List[Path], List[str]]:
    src, out = Path(src), Path(out)
    written: List[Path] = []
    problems: List[str] = []
    counts = {}
    for theme in ("light", "dark"):
        for locale in LOCALES:
            counts[(theme, locale)] = 0
    for nn, slug, locales in SHOTS:
        for theme in ("light", "dark"):
            for lang, locale in (("en", "en-US"), ("vi", "vi")):
                if locale not in locales:
                    continue
                name = "store-%s-%s-%s-%s.png" % (nn, slug, theme, lang)
                path = src / name
                if not path.is_file():
                    problems.append("missing %s" % name)
                    continue
                width, height, _colour = png_info(path.read_bytes())
                if (width, height) != SHOT_SIZE:
                    problems.append("%s is %dx%d, expected %dx%d" % (name, width, height, SHOT_SIZE[0], SHOT_SIZE[1]))
                    continue
                dest = out / "screenshots" / theme / locale / ("%s-%s.jpg" % (nn, slug))
                dest.parent.mkdir(parents=True, exist_ok=True)
                _to_jpeg(path, dest)
                written.append(dest)
                counts[(theme, locale)] += 1
    for (theme, locale), n in counts.items():
        if not 4 <= n <= 8:
            problems.append("%s/%s has %d screenshots, Google Play needs 4 to 8 (store promotion needs 4)"
                            % (theme, locale, n))
    return written, problems


def _violations(problems: List[str]) -> int:
    for problem in problems:
        print("violation: %s" % problem)
    return 1 if problems else 0


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("listing")
    graphics = sub.add_parser("graphics")
    graphics.add_argument("--out", default=str(REPO / "build/release/android/play"))
    shots = sub.add_parser("screenshots")
    shots.add_argument("--from", dest="src", required=True)
    shots.add_argument("--out", default=str(REPO / "build/release/android/play"))
    args = parser.parse_args(argv)

    if args.command == "listing":
        problems = listing_problems(LISTING)
        if (RES / "values" / "strings.xml").is_file():
            problems += quoted_label_problems(RES)
        status = _violations(problems)
        if not status:
            print("listing ok: %s" % ", ".join(LOCALES))
        return status

    if args.command == "graphics":
        out = Path(args.out)
        files = [(render_icon(REPO / "design/shellx-logo.svg", out), "PNG")]
        for locale in LOCALES:
            tagline = (LISTING / locale / "feature-graphic-tagline.txt").read_text(encoding="utf-8").strip()
            files.append((render_feature_graphic(REPO / "release/mobile/play/feature-graphic.svg",
                                                 tagline, locale, out), "JPEG"))
        for path, kind in files:
            data = path.read_bytes()
            if kind == "PNG":
                width, height, colour = png_info(data)
                print("%s %dx%d PNG %s" % (path, width, height, "RGBA" if colour == 6 else "colour type %d" % colour))
            else:
                width, height, _n = jpeg_info(data)
                print("%s %dx%d JPEG" % (path, width, height))
        return 0

    written, problems = prepare_screenshots(Path(args.src), Path(args.out))
    for path in written:
        print(path)
    return _violations(problems)


if __name__ == "__main__":
    sys.exit(main())
