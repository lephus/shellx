#!/usr/bin/env python3
"""Build the ShellX coolicons asset catalog from the coolicons v4.1 release.

Usage:
    python3 scripts/shellx/import_coolicons.py <coolicons.v4.1.zip | svg-dir> [--out DIR]

Each coolicon (24x24, 2 px round strokes) is turned into an SF Symbols
custom-symbol template (``<Name>.symbolset``) so that SwiftUI
``Image(_:bundle:)`` and AppKit ``NSImage(symbolName:bundle:variableValue:)``
treat it like an SF Symbol: it scales with ``.font``/``.imageScale`` and
``NSImage.SymbolConfiguration(pointSize:)`` and renders as a template.

Custom symbols must be filled outlines, so the strokes are expanded to fills
with picosvg (skia-pathops). That is a dev-time dependency only:

    python3 -m venv /tmp/coolicons-venv && /tmp/coolicons-venv/bin/pip install picosvg
    /tmp/coolicons-venv/bin/python scripts/shellx/import_coolicons.py coolicons.v4.1.zip

The output is deterministic for a given input: icons are processed in sorted
order and coordinates are rounded, so re-running the import yields an
identical catalog.

Release: https://github.com/krystonschwarze/coolicons/releases/download/v4.1/coolicons.v4.1.zip
sha256:  5311b1b44e345b19007902db55418c3a0b35fac825a38fbb9038bbf3a077e11c
License: CC BY 4.0, "coolicons by Kryston Schwarze" (see NOTICE next to the catalog).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "Packages/Shared/ShellXBrand/Sources/ShellXIcons/Resources/Coolicons.xcassets"
SVG_DIR = "cooliocns SVG"  # sic: the folder name inside the v4.1 zip
RELEASE_SHA256 = "5311b1b44e345b19007902db55418c3a0b35fac825a38fbb9038bbf3a077e11c"

# Symbol template geometry (SF Symbols template v3, point size 100).
BASELINE = {"S": 696.0, "M": 1126.0, "L": 1556.0}
CAP_HEIGHT = 70.459
# 1 coolicon unit -> 5 symbol units at the M scale. Calibrated against SF
# Symbols at 100 pt Regular: SF `circle` draws a ~100-unit ring, the
# coolicons Circle ring is 20 units (radius 9 + 1 stroke) -> 100. A 2 px
# stroke becomes 10 units (SF Regular is ~8.6, Medium ~10).
SCALE = 5.0
# SF Symbols' small/large image scales relative to medium (measured: SF
# `terminal` at 13 pt is 14/19/24 pt wide for S/M/L).
SCALE_RATIO = {"S": 0.783, "M": 1.0, "L": 1.29}
# Side bearing either side of the glyph's ink, in symbol units at M (SF
# `circle` at 100 pt: 117 wide for a ~100-unit ring).
SIDE_BEARING = 8.5
LEFT_MARGIN_X = 1400.0
def _picosvg():
    try:
        from picosvg.svg import SVG  # type: ignore
        from picosvg.svg_transform import Affine2D  # type: ignore
    except ImportError:  # pragma: no cover - dev-time tool
        sys.exit(
            "picosvg is required: python3 -m venv /tmp/coolicons-venv && "
            "/tmp/coolicons-venv/bin/pip install picosvg"
        )
    return SVG, Affine2D


def load_svgs(source: Path) -> dict[str, bytes]:
    """Return {CooliconName: svg bytes} from the release zip or an SVG dir."""
    out: dict[str, bytes] = {}
    if source.is_file():
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        if digest != RELEASE_SHA256:
            print(f"warning: {source} sha256 {digest} != v4.1 release {RELEASE_SHA256}", file=sys.stderr)
        with zipfile.ZipFile(source) as zf:
            for info in zf.infolist():
                name = info.filename
                # The release ships the same icons three times (SVG folder,
                # IconJar, sprite); only the categorised SVG folder is used.
                parts = name.split("/")
                if len(parts) != 3 or parts[0] != SVG_DIR or not name.endswith(".svg"):
                    continue
                stem = Path(name).stem
                out[stem] = zf.read(info)
    else:
        for path in source.rglob("*.svg"):
            out[path.stem] = path.read_bytes()
    bad = sorted(n for n in out if not re.fullmatch(r"[A-Za-z0-9_]+", n))
    if bad:
        sys.exit(f"unexpected coolicon names: {bad}")
    return dict(sorted(out.items()))


def outline_path(svg_bytes: bytes):
    """Expand strokes to fills; return the outlined paths in coolicon units."""
    SVG, _ = _picosvg()
    pico = SVG.fromstring(svg_bytes.decode("utf-8")).topicosvg()
    paths = [shape.as_path() for shape in pico.shapes()]
    if not paths:
        raise ValueError("icon has no paintable shapes")
    return paths


def _bbox_x(paths) -> tuple[float, float]:
    boxes = [p.bounding_box() for p in paths]
    return min(b.x for b in boxes), max(b.x + b.w for b in boxes)


def glyph(paths, scale: str) -> tuple[str, float]:
    """Return (path data, advance) for one scale, origin at the left margin
    on the baseline (y up is negative), the 24-unit frame centred on the
    middle of the cap height like SF Symbols."""
    _, Affine2D = _picosvg()
    ratio = SCALE_RATIO[scale]
    factor = SCALE * ratio
    xmin, xmax = _bbox_x(paths)
    bearing = SIDE_BEARING * ratio
    transform = Affine2D(factor, 0, 0, factor, bearing - xmin * factor, -CAP_HEIGHT / 2.0 - 12 * factor)
    d = " ".join(p.apply_transform(transform).round_floats(3).d for p in paths)
    advance = round((xmax - xmin) * factor + 2 * bearing, 3)
    return d, advance


def _line(id_: str, x1, x2, y1, y2) -> str:
    return (
        f'  <line id="{id_}" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" '
        f'x1="{x1:g}" x2="{x2:g}" y1="{y1:g}" y2="{y2:g}"/>'
    )


def symbol_template(name: str, paths) -> str:
    guides: list[str] = []
    symbols: list[str] = []
    for scale in ("S", "M", "L"):
        base = BASELINE[scale]
        cap = round(base - CAP_HEIGHT, 3)
        guides.append(_line(f"Baseline-{scale}", 263, 3036, base, base))
        guides.append(_line(f"Capline-{scale}", 263, 3036, cap, cap))
    for scale in ("S", "M", "L"):
        base = BASELINE[scale]
        d, advance = glyph(paths, scale)
        top, bottom = base - 120, base + 40
        guides.append(_line(f"left-margin-Regular-{scale}", LEFT_MARGIN_X, LEFT_MARGIN_X, top, bottom))
        right = round(LEFT_MARGIN_X + advance, 3)
        guides.append(_line(f"right-margin-Regular-{scale}", right, right, top, bottom))
        symbols.append(
            f'  <g id="Regular-{scale}" transform="matrix(1 0 0 1 {LEFT_MARGIN_X:g} {base:g})">\n'
            f'   <path d="{d}"/>\n'
            f"  </g>"
        )
    guides_xml = "\n".join(guides)
    symbols_xml = "\n".join(symbols)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">
 <!--glyph: "{name}", point size: 100.0, coolicons v4.1 by Kryston Schwarze (CC BY 4.0), generated by scripts/shellx/import_coolicons.py-->
 <g id="Notes">
  <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;font-weight:bold;" transform="matrix(1 0 0 1 263 322)">Weight/Scale Variations</text>
  <text id="template-version" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1933)">Template v.3.0</text>
 </g>
 <g id="Guides">
{guides_xml}
 </g>
 <g id="Symbols">
{symbols_xml}
 </g>
</svg>
"""


def write_catalog(icons: dict[str, bytes], out: Path) -> None:
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    (out / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8"
    )
    for name, svg in icons.items():
        folder = out / f"{name}.symbolset"
        folder.mkdir()
        (folder / f"{name}.svg").write_text(symbol_template(name, outline_path(svg)), encoding="utf-8")
        contents = {
            "info": {"author": "xcode", "version": 1},
            "symbols": [{"filename": f"{name}.svg", "idiom": "universal"}],
        }
        (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("source", type=Path, help="coolicons.v4.1.zip or a directory of coolicons SVGs")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="output .xcassets directory")
    args = parser.parse_args(argv)
    icons = load_svgs(args.source)
    if len(icons) != 442:
        print(f"warning: expected 442 coolicons (v4.1), found {len(icons)}", file=sys.stderr)
    write_catalog(icons, args.out)
    print(f"wrote {len(icons)} symbolsets to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
