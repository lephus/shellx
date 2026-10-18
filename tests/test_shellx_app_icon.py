"""Guard: ShellX app icons match their declared sizes and the logo source stays in sync."""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from shellx_look_guard import png_size, read, sha256  # noqa: E402

# sha256 of web/public/favicon.svg (= design/shellx-logo.svg) at copy time.
EXPECTED_SHA256 = "b160556d68f67ad29abb66be8d61eaf709f30b485448826a8725a038e25518d8"
APPICONSETS = ["AppIcon", "AppIcon-Debug", "AppIcon-RC", "AppIcon-Nightly"]
XC = "Assets.xcassets"


@pytest.mark.parametrize("name", APPICONSETS)
def test_app_icon_sizes(name):
    contents = json.loads(read(f"{XC}/{name}.appiconset/Contents.json"))
    checked = 0
    for img in contents["images"]:
        filename = img.get("filename")
        if not filename:  # slot declared without a file: nothing to measure
            continue
        w, h = png_size(f"{XC}/{name}.appiconset/{filename}")
        side = int(float(img["size"].split("x")[0]) * int(img["scale"][0]))
        assert (w, h) == (side, side), f"{name}/{filename}"
        checked += 1
    assert checked > 0, f"{name} has no icon files"


def test_logo_source_matches_web():
    assert sha256("design/shellx-logo.svg") == EXPECTED_SHA256
    assert sha256("design/shellx-logo.svg") == sha256("web/public/favicon.svg")


def test_shellx_logo_imageset_present():
    contents = json.loads(read(f"{XC}/ShellXLogo.imageset/Contents.json"))
    files = [i["filename"] for i in contents["images"] if "filename" in i]
    assert files, "ShellXLogo.imageset lists no files"
    for f in files:
        assert (Path(__file__).resolve().parent.parent / XC / "ShellXLogo.imageset" / f).is_file(), f
