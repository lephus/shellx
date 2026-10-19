#!/usr/bin/env python3
"""Guard: every icon in the macOS app is a coolicon behind ShellXIcon (spec §7.4).

- No direct SF Symbol call (`Image(systemName:)`, `systemImage:` labels,
  `NSImage(systemSymbolName:)`) outside `ShellXIcon` and the dynamic
  allowlist below.
- Every literal SF Symbol name the app used before the codemod (frozen in
  scripts/shellx/icon-literal-symbols.txt) has a coolicon in icon-map.json,
  and every mapped coolicon exists in the asset catalog.
- The coolicons license notice ships next to the assets.

Usage (from the repo root):
    python3 tests/test_shellx_icons.py
"""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from shellx_look_guard import offenders, read  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
ICONS = "Packages/Shared/ShellXBrand/Sources/ShellXIcons"
MAP_PATH = ROOT / ICONS / "Resources/icon-map.json"
CATALOG = ROOT / ICONS / "Resources/Coolicons.xcassets"
NOTICE = ROOT / ICONS / "Resources/NOTICE"
SNAPSHOT = ROOT / "scripts/shellx/icon-literal-symbols.txt"
SWIFTRENDER_CORPUS = "Packages/macOS/CmuxSwiftRender/Tests/CmuxSwiftRenderTests/Corpus"

# Files allowed to spell SF Symbol APIs directly, each with its reason.
DYNAMIC_ALLOWLIST = [
    (f"{ICONS}/ShellXIcon.swift",
     "the one place that falls back to SF Symbols for names coolicons do not map"),
    ("Sources/App/TextBoxSubmitAction.swift",
     "user-configured submit actions: `systemImage` is the persisted settings key and init label; "
     "rendered through ShellXIcon.image"),
    ("Packages/macOS/CmuxSwiftRender/Tests/CmuxSwiftRenderTests/SwiftViewInterpreterTests.swift",
     "custom sidebar DSL test input: user-written Swift source spells Image(systemName:)/Label(systemImage:)"),
] + [
    (p.relative_to(ROOT).as_posix(),
     "custom sidebar DSL corpus: user-written Swift source, interpreted (not compiled); "
     "its symbols render through ShellXIcon.image")
    for p in sorted((ROOT / SWIFTRENDER_CORPUS).glob("*.swift"))
]


def literal_symbols_before_codemod() -> list[str]:
    return [
        line.strip()
        for line in SNAPSHOT.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    ]


def load_map() -> dict:
    with MAP_PATH.open(encoding="utf-8") as fh:
        return json.load(fh)


class ShellXIconsGuard(unittest.TestCase):
    def test_no_direct_sf_symbol_calls_outside_shellxicon(self):
        pat = r"Image\(systemName:|systemImage:|NSImage\(systemSymbolName:"
        hits = offenders(pat, roots=["Sources", "Packages/macOS", "Packages/Shared"], allow=DYNAMIC_ALLOWLIST)
        hits = [h for h in hits if "/.build/" not in h]
        self.assertEqual(hits, [])

    def test_allowlist_entries_exist(self):
        for path, reason in DYNAMIC_ALLOWLIST:
            self.assertTrue((ROOT / path).is_file(), path)
            self.assertTrue(reason)

    def test_every_literal_symbol_is_mapped(self):
        used = literal_symbols_before_codemod()
        self.assertGreater(len(used), 200)
        mapping = load_map()
        self.assertEqual(sorted(set(used) - set(mapping)), [])

    def test_every_mapped_coolicon_is_in_the_catalog(self):
        mapping = load_map()
        missing = sorted(
            {name for name in mapping.values() if not (CATALOG / f"{name}.symbolset" / f"{name}.svg").is_file()}
        )
        self.assertEqual(missing, [])

    def test_catalog_has_all_coolicons_as_symbols(self):
        symbolsets = sorted(CATALOG.glob("*.symbolset"))
        self.assertEqual(len(symbolsets), 442)
        sample = (CATALOG / "Terminal.symbolset/Terminal.svg").read_text(encoding="utf-8")
        for guide in ("Baseline-M", "Capline-M", 'id="Regular-S"', 'id="Regular-M"', 'id="Regular-L"'):
            self.assertIn(guide, sample)
        self.assertNotIn("stroke=", sample.split('<g id="Symbols">', 1)[1])

    def test_names_later_tasks_use_exist(self):
        for name in ("Laptop", "Desktop", "Data", "Mobile", "Link", "Terminal", "Bell_Ring", "Add_Plus",
                     "Search_Magnifying_Glass", "Settings", "Circle_Check", "Shield_Check", "Users",
                     "Window_Sidebar", "More_Horizontal", "Qr_Code"):
            self.assertTrue((CATALOG / f"{name}.symbolset").is_dir(), name)

    def test_license_notice_ships_with_assets(self):
        notice = NOTICE.read_text(encoding="utf-8")
        self.assertIn("coolicons", notice)
        self.assertIn("Kryston Schwarze", notice)
        self.assertIn("CC BY 4.0", notice)

    def test_codemod_rewrites_are_idempotent(self):
        sys.path.insert(0, str(ROOT / "scripts/shellx"))
        import icon_codemod  # noqa: E402

        for path in icon_codemod.swift_files():
            text = path.read_text(encoding="utf-8")
            new, counts = icon_codemod.rewrite(text)
            self.assertEqual(new, text, f"{path} still has rewritable SF Symbol calls: {counts}")

    def test_substitutions_are_recorded(self):
        doc = read("scripts/shellx/icon-substitutions.md")
        self.assertIn("|", doc)


if __name__ == "__main__":
    unittest.main()
