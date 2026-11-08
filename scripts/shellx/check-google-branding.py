#!/usr/bin/env python3
"""Release guard: both desktop apps must ship Google's official "G" mark.

The marks come from Google's signin-assets.zip, downloaded by the user with
scripts/shellx/fetch-google-branding.sh. The Google Sans Medium font is optional, but only ever
together with its SIL OFL 1.1 licence file; without it the button uses the system font.

    check-google-branding.py [--root DIR] [--git-rev REV]

DIR defaults to $SHELLX_GOOGLE_BRANDING_ROOT, else the repository root. With --git-rev every file
is read from that commit (`git -C DIR show REV:<path>`) instead of the working tree.
Exit 0 prints `google branding: OK`; otherwise exit 1 with one stderr line per problem.
"""

from __future__ import annotations

import argparse
import json
import os
import struct
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

MAC_DIR = "Assets.xcassets/GoogleG.imageset"
MARKS = {
    "mac contents": f"{MAC_DIR}/Contents.json",
    "mac png": f"{MAC_DIR}/google-g.png",
    "windows png": "windows/shellx-app/assets/google/google-g.png",
}
FONTS = {
    "mac": ("Resources/Fonts/GoogleSans-Medium.ttf", "Resources/Fonts/GoogleSans-OFL.txt"),
    "windows": ("windows/shellx-app/assets/fonts/GoogleSans-Medium.ttf", "windows/shellx-app/assets/fonts/GoogleSans-OFL.txt"),
}
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
LICENCE = b"SIL Open Font License, Version 1.1"


class Source:
    def __init__(self, root: Path, rev: str | None):
        self.root, self.rev = root, rev

    def read(self, rel: str) -> bytes | None:
        if self.rev is None:
            path = self.root / rel
            return path.read_bytes() if path.is_file() else None
        proc = subprocess.run(["git", "-C", str(self.root), "show", f"{self.rev}:{rel}"], capture_output=True)
        return proc.stdout if proc.returncode == 0 else None


def png_size(data: bytes) -> tuple[int, int] | None:
    if not data.startswith(PNG_SIGNATURE) or data[12:16] != b"IHDR" or len(data) < 24:
        return None
    return struct.unpack(">II", data[16:24])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root")
    ap.add_argument("--git-rev")
    args = ap.parse_args()
    root = Path(args.root or os.environ.get("SHELLX_GOOGLE_BRANDING_ROOT") or REPO)
    src = Source(root, args.git_rev)
    problems: list[str] = []
    notes: list[str] = []

    data = {name: src.read(rel) for name, rel in MARKS.items()}
    for name, rel in MARKS.items():
        if data[name] is None:
            problems.append(f"missing: {rel}")
    if data["mac contents"] is not None:
        try:
            names = [i.get("filename") for i in json.loads(data["mac contents"]).get("images", [])]
            if "google-g.png" not in names:
                problems.append(f"bad: {MARKS['mac contents']} (does not name google-g.png)")
        except (ValueError, AttributeError):
            problems.append(f"bad: {MARKS['mac contents']} (not valid JSON)")
    for name in ("mac png", "windows png"):
        if data[name] is not None and png_size(data[name]) != (80, 80):
            problems.append(f"bad: {MARKS[name]} (not an 80x80 PNG)")

    for platform, (font, ofl) in FONTS.items():
        ttf, licence = src.read(font), src.read(ofl)
        if ttf is None and licence is None:
            notes.append(f"font: {platform} uses the system font")
        elif ttf is None:
            problems.append(f"missing: {font}")
        elif not ttf.startswith(b"\x00\x01\x00\x00"):
            problems.append(f"bad: {font} (not a TrueType font)")
        elif licence is None or LICENCE not in licence:
            problems.append(f"bad: {font} (no SIL OFL 1.1 licence beside it)")

    for line in notes:
        print(line)
    if problems:
        for line in problems:
            print(line, file=sys.stderr)
        return 1
    print("google branding: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
