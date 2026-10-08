"""Regenerates every ShellX app icon from the three SVGs in this folder.

    python3 assets/brand/gen_icons.py

Needs macOS (qlmanage rasterises the SVGs at 1024 px, `qlmanage -t -s 1024 -o
<dir> file.svg`) and Pillow. qlmanage always paints a white background, so the
transparent variants (rounded tile, foreground) are rendered twice, on white and
on black, and the alpha is recovered from the difference. Optional argument: the
work directory (default /tmp/shellx-brand).
"""
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/shellx-brand")
BRAND = Path(__file__).resolve().parent
SRC.mkdir(parents=True, exist_ok=True)


def ql(svg: Path) -> Image.Image:
    subprocess.run(["qlmanage", "-t", "-s", "1024", "-o", str(SRC), str(svg)],
                   check=True, capture_output=True)
    return Image.open(SRC / f"{svg.name}.png").convert("RGB")


def load(name):
    """Opaque render for the full-bleed art, matted RGBA for the others."""
    svg = BRAND / f"{name}.svg"
    white = ql(svg)
    if name == "shellx-logo-fullbleed":
        return white.convert("RGBA")
    text = svg.read_text()
    head = text.index(">", text.index("<svg")) + 1
    black_svg = SRC / f"{name}-onblack.svg"
    black_svg.write_text(text[:head] + '<rect width="512" height="512" fill="#000"/>' + text[head:])
    black = ql(black_svg)
    out = []
    for w, b in zip(white.getdata(), black.getdata()):
        a = 1 - (sum(w) - sum(b)) / 765
        a = min(max(a, 0), 1)
        out.append((0, 0, 0, 0) if a < 0.002 else
                   tuple(min(255, round(c / a)) for c in b) + (round(a * 255),))
    im = Image.new("RGBA", white.size)
    im.putdata(out)
    return im


tile = load("shellx-logo")
full = load("shellx-logo-fullbleed")
fg = load("shellx-logo-foreground")


def resize(im, px):
    return im.resize((px, px), Image.LANCZOS)


# ---- desktop -------------------------------------------------------------
D = ROOT / "apps/desktop"
mac = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
t824 = resize(tile, 824)
mac.paste(t824, (100, 100), t824)  # Apple grid: 824 px tile centred in 1024
for s in (16, 32, 64, 128, 256, 512, 1024):
    resize(mac, s).save(D / f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{s}.png")
resize(tile, 256).save(
    D / "windows/runner/resources/app_icon.ico",
    format="ICO",
    sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)],
)

# ---- mobile --------------------------------------------------------------
M = ROOT / "apps/mobile"
ios = M / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
contents = json.loads((ios / "Contents.json").read_text())
sizes = {}
for e in contents["images"]:
    sizes[e["filename"]] = round(float(e["size"].split("x")[0]) * float(e["scale"].rstrip("x")))
flat = Image.new("RGB", full.size, (0x14, 0x0F, 0x2A))
flat.paste(full, (0, 0), full)  # flatten alpha: iOS icons carry none
for name, px in sizes.items():
    resize(flat, px).save(ios / name)

res = M / "android/app/src/main/res"
dens = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}
# Adaptive layers: 108dp canvas; the 512 artwork spans 84dp (content ~54dp,
# inside the 66dp safe zone).
fg_art = resize(fg, round(1024 * 84 / 108))
canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
off = (1024 - fg_art.width) // 2
canvas.paste(fg_art, (off, off), fg_art)
mono = Image.new("RGBA", canvas.size, (255, 255, 255, 0))
mono.putalpha(canvas.getchannel("A"))
# Notification glyph: crop to the glyph, pad to a square.
glyph = mono.crop(mono.getchannel("A").getbbox())
side = max(glyph.size)
note = Image.new("RGBA", (side, side), (255, 255, 255, 0))
note.paste(glyph, ((side - glyph.width) // 2, (side - glyph.height) // 2))
for d, k in dens.items():
    resize(canvas, round(108 * k)).save(res / f"mipmap-{d}/ic_launcher_foreground.png")
    resize(mono, round(108 * k)).save(res / f"mipmap-{d}/ic_launcher_monochrome.png")
    resize(tile, round(48 * k)).save(res / f"mipmap-{d}/ic_launcher.png")
    n = round(24 * k)
    inner = resize(note, round(n * 0.9))
    c = Image.new("RGBA", (n, n), (255, 255, 255, 0))
    c.paste(inner, ((n - inner.width) // 2, (n - inner.height) // 2), inner)
    c.save(res / f"drawable-{d}/ic_notification.png")
(res / "values/ic_launcher_background.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
    '    <color name="ic_launcher_background">#140F2A</color>\n</resources>\n'
)
resize(tile, 512).save(M / "assets/images/logo.png")
print("done")
