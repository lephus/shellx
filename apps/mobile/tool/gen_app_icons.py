#!/usr/bin/env python3
"""Generates ShellX's app icons and in-app logo asset from the supplied artwork.

Re-run after changing either source file:

    cd apps/mobile
    python3 tool/gen_app_icons.py

Requires Python 3 and Pillow (this repo pins Pillow 12.0.0). The script is
deterministic: with unchanged sources, re-running it produces byte-identical
output files, so a clean re-run should show no `git diff`.

Sources (checked into `assets/branding/`, never edited by this script):
  - logo_shellx_rounded.png: the tile pre-rounded onto a white 512x512 square.
    The white corners are removed (made transparent) for the Android legacy
    launcher icon and for the in-app `assets/images/logo.png`.
  - logo_shellx_square.png: the same artwork, full-bleed, no rounding. Used
    for the iOS AppIcon (iOS applies its own corner mask) and for the Android
    adaptive icon's foreground/monochrome layers.

Outputs written by this script:
  - ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png (sizes read from the
    existing Contents.json; RGB, no alpha channel)
  - android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
  - android/app/src/main/res/values/ic_launcher_background.xml
  - android/app/src/main/res/mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher_foreground.png
  - android/app/src/main/res/mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher_monochrome.png
  - android/app/src/main/res/mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png (legacy)
  - assets/images/logo.png (512x512, used by `ShellxLogo`)
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

MOBILE_ROOT = Path(__file__).resolve().parents[1]
BRANDING_DIR = MOBILE_ROOT / "assets" / "branding"
ROUNDED_SOURCE = BRANDING_DIR / "logo_shellx_rounded.png"
SQUARE_SOURCE = BRANDING_DIR / "logo_shellx_square.png"

IOS_APPICON_DIR = MOBILE_ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
ANDROID_RES_DIR = MOBILE_ROOT / "android" / "app" / "src" / "main" / "res"
IMAGES_ASSET_DIR = MOBILE_ROOT / "assets" / "images"

# The tile's own flat background, verbatim from the brief: #16181D.
BACKGROUND_COLOR = (0x16, 0x18, 0x1D)

# Adaptive icon geometry (brief section 3): a 108dp viewport, artwork scaled
# to 72/108 of it so it (and the dots) sit inside the 66dp safe circle.
ADAPTIVE_VIEWPORT_DP = 108
ADAPTIVE_ARTWORK_DP = 72

# density -> px for a 108dp viewport (mdpi=1x .. xxxhdpi=4x) and for the
# legacy 48dp launcher icon, sharing the same scale factors.
DENSITIES = {
    "mdpi": 1.0,
    "hdpi": 1.5,
    "xhdpi": 2.0,
    "xxhdpi": 3.0,
    "xxxhdpi": 4.0,
}
LEGACY_DP = 48


def measure_corner_radius(im: Image.Image) -> float:
    """Fits a circle to the rounded source's top-left corner arc.

    The source sits on a pure-white (255,255,255) square; the corner is cut
    by a circular arc centred at (r, r). This scans rows and columns near the
    corner for the white -> tile boundary (sub-pixel, via the anti-aliasing
    blend), then fits a circle to those boundary points with linear
    least squares (Kasa's method). Returns the radius in the image's own
    pixel units (e.g. out of 512).
    """
    arr = np.asarray(im.convert("RGB"), dtype=float)
    w, h = im.size
    limit = min(w, h) // 2
    white = np.array([255.0, 255.0, 255.0])

    def boundary(line: np.ndarray) -> float | None:
        segment = line[:limit]
        not_white = np.any(segment != white, axis=1)
        if not not_white.any():
            return None
        idx = int(np.argmax(not_white))
        if idx == 0:
            return None
        prev_lum = 765.0  # 255*3, pure white
        cur_lum = float(segment[idx].sum())
        inner_idx = min(idx + 3, limit - 1)
        inner_lum = float(segment[inner_idx].sum())
        if prev_lum == inner_lum:
            return idx - 0.5
        frac = (prev_lum - cur_lum) / (prev_lum - inner_lum)
        frac = min(max(frac, 0.0), 1.0)
        return idx - 1 + frac

    points: list[tuple[float, float]] = []
    for y in range(limit):
        xb = boundary(arr[y, :, :])
        if xb is not None:
            points.append((xb, float(y)))
    for x in range(limit):
        yb = boundary(arr[:, x, :])
        if yb is not None:
            points.append((float(x), yb))

    pts = np.array(points)
    x, y = pts[:, 0], pts[:, 1]
    a_matrix = np.column_stack([2 * x, 2 * y, np.ones_like(x)])
    b_vector = x**2 + y**2
    (_cx, _cy, c), *_rest = np.linalg.lstsq(a_matrix, b_vector, rcond=None)
    radius = float(np.sqrt(c + _cx**2 + _cy**2))
    return radius


def rounded_mask(size: int, radius: float, supersample: int = 4) -> Image.Image:
    """An anti-aliased rounded-rect alpha mask, `size`x`size`, corner `radius`."""
    big = size * supersample
    big_radius = radius * supersample
    mask = Image.new("L", (big, big), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, big - 1, big - 1], radius=big_radius, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def apply_transparent_corners(source_rgb: Image.Image, mask: Image.Image, fill_color: tuple[int, int, int]) -> Image.Image:
    """Cuts `source_rgb`'s corners to transparent per `mask`.

    Everywhere the mask is not fully opaque (the anti-aliased boundary ring
    and the fully-cut corners), the RGB is replaced with the tile's flat
    `fill_color` instead of keeping the source's own white-blended pixels.
    That avoids a white fringe: a semi-transparent pixel whose colour is
    still "white blended with tile" shows as a light halo once composited
    over a background that isn't white. The boundary ring never touches the
    dots/chevron/bar artwork (they sit well inside the arc), so this is safe.
    """
    arr = np.array(source_rgb.convert("RGB"), dtype=np.uint8)
    m = np.array(mask, dtype=np.uint8)
    out_rgb = arr.copy()
    out_rgb[m < 255] = fill_color
    out = np.dstack([out_rgb, m])
    return Image.fromarray(out, mode="RGBA")


def build_logo_512() -> Image.Image:
    rounded = Image.open(ROUNDED_SOURCE).convert("RGBA")
    radius = measure_corner_radius(rounded)
    mask = rounded_mask(rounded.width, radius)
    return apply_transparent_corners(rounded, mask, BACKGROUND_COLOR)


def load_square_source() -> Image.Image:
    """Loads the square source, patching a measured 1px export artifact.

    The source's last pixel row and column (511 of 512) are a flat (51,53,57)
    instead of the tile's (22,24,29) background: a thin bleed/guide line left
    in on export, confirmed by sampling (every pixel on both edges is exactly
    that colour; row/column 510 has none of it). It's outside the artwork
    (dots/chevron/bar sit well inside), so replacing that single edge with
    its neighbour removes it without touching the artwork.
    """
    square = Image.open(SQUARE_SOURCE).convert("RGB")
    arr = np.array(square)
    arr[-1, :] = arr[-2, :]
    arr[:, -1] = arr[:, -2]
    return Image.fromarray(arr, mode="RGB")


def gen_ios_appicon() -> None:
    square = load_square_source()
    contents_path = IOS_APPICON_DIR / "Contents.json"
    contents = json.loads(contents_path.read_text())

    sizes_by_filename: dict[str, int] = {}
    for entry in contents["images"]:
        points = float(entry["size"].split("x")[0])
        scale = float(entry["scale"].rstrip("x"))
        px = round(points * scale)
        filename = entry["filename"]
        if filename in sizes_by_filename:
            assert sizes_by_filename[filename] == px, f"conflicting sizes for {filename}"
        sizes_by_filename[filename] = px

    for filename, px in sorted(sizes_by_filename.items()):
        resized = square.resize((px, px), Image.LANCZOS)
        assert resized.mode == "RGB"
        resized.save(IOS_APPICON_DIR / filename, "PNG")


def gen_android_adaptive_icon_xml() -> None:
    anydpi_dir = ANDROID_RES_DIR / "mipmap-anydpi-v26"
    anydpi_dir.mkdir(parents=True, exist_ok=True)
    (anydpi_dir / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<adaptive-icon xmlns:android=\"http://schemas.android.com/apk/res/android\">\n"
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        "</adaptive-icon>\n"
    )

    values_dir = ANDROID_RES_DIR / "values"
    values_dir.mkdir(parents=True, exist_ok=True)
    hex_color = "#{:02X}{:02X}{:02X}".format(*BACKGROUND_COLOR)
    (values_dir / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        f'    <color name="ic_launcher_background">{hex_color}</color>\n'
        "</resources>\n"
    )


def gen_android_foreground_and_monochrome() -> None:
    square = load_square_source().convert("RGBA")
    bg = np.array(BACKGROUND_COLOR, dtype=float)

    # Monochrome: white glyph, alpha by each pixel's distance from the flat
    # background colour. Solid glyph tones (dots, chevron, bar) all reach
    # full opacity; only the true anti-aliased transition pixels (the ones
    # actually blended toward the background in the source) get partial
    # alpha, so edges stay smooth. The reference distance is the *smallest*
    # solid glyph tone's distance from the background (measured from the
    # image, not guessed): every solid tone is at least that far from the
    # background, so all of them saturate to full opacity.
    arr = np.asarray(square.convert("RGB"), dtype=float)
    dist = np.sqrt(np.sum((arr - bg) ** 2, axis=-1))
    flat_colors, counts = np.unique(arr.reshape(-1, 3), axis=0, return_counts=True)
    solid = flat_colors[counts >= 200]  # flat fills, not anti-aliasing noise
    solid_dist = np.sqrt(np.sum((solid - bg) ** 2, axis=-1))
    solid_dist = solid_dist[solid_dist > 1.0]  # drop the background colour itself
    reference = float(solid_dist.min())
    alpha = np.clip(np.round(dist / reference * 255.0), 0, 255).astype(np.uint8)
    mono_rgba = np.dstack([np.full_like(alpha, 255), np.full_like(alpha, 255), np.full_like(alpha, 255), alpha])
    monochrome_full = Image.fromarray(mono_rgba, mode="RGBA")

    for density, scale in DENSITIES.items():
        viewport = round(ADAPTIVE_VIEWPORT_DP * scale)
        inner = round(ADAPTIVE_ARTWORK_DP * scale)
        offset = (viewport - inner) // 2

        density_dir = ANDROID_RES_DIR / f"mipmap-{density}"
        density_dir.mkdir(parents=True, exist_ok=True)

        fg_canvas = Image.new("RGBA", (viewport, viewport), (0, 0, 0, 0))
        fg_canvas.paste(square.resize((inner, inner), Image.LANCZOS), (offset, offset))
        fg_canvas.save(density_dir / "ic_launcher_foreground.png", "PNG")

        mono_canvas = Image.new("RGBA", (viewport, viewport), (0, 0, 0, 0))
        mono_canvas.paste(monochrome_full.resize((inner, inner), Image.LANCZOS), (offset, offset))
        mono_canvas.save(density_dir / "ic_launcher_monochrome.png", "PNG")


def gen_android_legacy_icon(logo_512: Image.Image) -> None:
    for density, scale in DENSITIES.items():
        size = round(LEGACY_DP * scale)
        density_dir = ANDROID_RES_DIR / f"mipmap-{density}"
        density_dir.mkdir(parents=True, exist_ok=True)
        resized = logo_512.resize((size, size), Image.LANCZOS)
        resized.save(density_dir / "ic_launcher.png", "PNG")


def gen_in_app_logo(logo_512: Image.Image) -> None:
    IMAGES_ASSET_DIR.mkdir(parents=True, exist_ok=True)
    logo_512.save(IMAGES_ASSET_DIR / "logo.png", "PNG")


def main() -> None:
    logo_512 = build_logo_512()

    gen_ios_appicon()
    gen_android_adaptive_icon_xml()
    gen_android_foreground_and_monochrome()
    gen_android_legacy_icon(logo_512)
    gen_in_app_logo(logo_512)


if __name__ == "__main__":
    main()
