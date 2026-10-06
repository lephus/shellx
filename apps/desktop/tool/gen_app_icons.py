#!/usr/bin/env python3
"""Generates the ShellX desktop app icons (macOS AppIcon, Windows app_icon.ico).

Re-run after changing the artwork:

    cd apps/desktop
    python3 tool/gen_app_icons.py

Requires Python 3, Pillow and NumPy (like apps/mobile/tool/gen_app_icons.py).
Deterministic: with unchanged sources, a re-run leaves no `git diff`.

Source: the same artwork as the mobile app. The 512x512 tile with transparent
corners is built by the mobile script's `build_logo_512` (imported, not
copied), from `apps/mobile/assets/branding/logo_shellx_rounded.png`.

Outputs:
  - macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{16..1024}.png:
    the tile at 824/1024 of the canvas, centred on a transparent margin (the
    macOS icon grid since Big Sur, so ShellX is not larger than other Dock
    icons). Contents.json is unchanged.
  - windows/runner/resources/app_icon.ico: 16, 24, 32, 48, 64, 128 and 256 px,
    the tile edge to edge (Windows draws no margin of its own).

The tray icons (assets/tray/) are drawn separately and are not touched.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path

from PIL import Image

DESKTOP_ROOT = Path(__file__).resolve().parents[1]
MOBILE_SCRIPT = DESKTOP_ROOT.parent / "mobile" / "tool" / "gen_app_icons.py"

MAC_APPICON_DIR = DESKTOP_ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
MAC_SIZES = [16, 32, 64, 128, 256, 512, 1024]
# Apple's macOS icon template: an 824x824 tile on a 1024x1024 canvas.
MAC_TILE_FRACTION = 824 / 1024

WINDOWS_ICO = DESKTOP_ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
WINDOWS_SIZES = [16, 24, 32, 48, 64, 128, 256]


def load_mobile_script():
    spec = importlib.util.spec_from_file_location("shellx_mobile_icons", MOBILE_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def mac_icon(tile_1024: Image.Image, size: int) -> Image.Image:
    """The tile scaled into Apple's grid, on a transparent `size` canvas."""
    canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    tile_px = round(1024 * MAC_TILE_FRACTION)
    tile = tile_1024.resize((tile_px, tile_px), Image.LANCZOS)
    offset = (1024 - tile_px) // 2
    canvas.paste(tile, (offset, offset), tile)
    return canvas if size == 1024 else canvas.resize((size, size), Image.LANCZOS)


def gen_mac_appicon(tile_1024: Image.Image) -> None:
    for size in MAC_SIZES:
        mac_icon(tile_1024, size).save(MAC_APPICON_DIR / f"app_icon_{size}.png", "PNG")


def gen_windows_ico(tile_1024: Image.Image) -> None:
    largest = tile_1024.resize((256, 256), Image.LANCZOS)
    largest.save(WINDOWS_ICO, format="ICO", sizes=[(s, s) for s in WINDOWS_SIZES])


def main() -> None:
    mobile = load_mobile_script()
    # Upscaled once from the 512 tile so every size comes from the same pixels.
    tile_1024 = mobile.build_logo_512().convert("RGBA").resize((1024, 1024), Image.LANCZOS)
    gen_mac_appicon(tile_1024)
    gen_windows_ico(tile_1024)


if __name__ == "__main__":
    main()
