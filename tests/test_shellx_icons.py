#!/usr/bin/env python3
"""Guard: every icon in the macOS app is a coolicon behind ShellXIcon (spec §7.4).

- No direct SF Symbol call (`Image(systemName:)`, `systemImage:` labels,
  `NSImage(systemSymbolName:)`) outside `ShellXIcon` and the dynamic
  allowlist below, and nothing left for the codemod to rewrite.
- Every literal SF Symbol name the app used before the codemod (frozen in
  scripts/shellx/icon-literal-symbols.txt) has a coolicon in icon-map.json,
  the map matches scripts/shellx/icon-substitutions.md, and every mapped
  coolicon is in the asset catalog.
- Names from user configuration render through ShellXIcon, which falls back
  to the SF Symbol of that name (Review Focus 3).
- The app links the ShellXIcons product and every package that imports it
  declares it; the shellx CLI never links it, directly or through a package.
- The coolicons license notice ships with the assets.

Usage (from the repo root):
    python3 tests/test_shellx_icons.py
"""
import json
import re
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
SUBSTITUTIONS = "scripts/shellx/icon-substitutions.md"
PBXPROJ = "cmux.xcodeproj/project.pbxproj"
SWIFTRENDER_CORPUS = "Packages/macOS/CmuxSwiftRender/Tests/CmuxSwiftRenderTests/Corpus"
SF_PATTERN = r"Image\(systemName:|systemImage:|NSImage\(systemSymbolName:"
GUARDED_ROOTS = ["Sources", "Packages/macOS", "Packages/Shared"]

# coolicons v4.1 has 442 icons; DERIVED in scripts/shellx/import_coolicons.py
# adds symbols built from a coolicon.
COOLICON_COUNT = 442
DERIVED = {"Circle_Fill"}

# Files allowed to spell SF Symbol APIs directly, each with its reason.
DYNAMIC_ALLOWLIST = [
    (f"{ICONS}/ShellXIcon.swift",
     "the one place that falls back to SF Symbols, for names the map does not know (user configuration)"),
    ("Sources/App/TextBoxSubmitAction.swift",
     "user-configured submit actions: `systemImage` is the persisted settings key (Codable) and its init "
     "label; the icon renders through ShellXIcon.image, which falls back to SF for unmapped names"),
    ("Packages/Shared/ShellXBrand/Tests/ShellXBrandTests/ShellXIconTests.swift",
     "measures coolicons against the SF Symbols they replace (size parity) and the SF fallback itself"),
    ("Packages/macOS/CmuxSwiftRender/Tests/CmuxSwiftRenderTests/SwiftViewInterpreterTests.swift",
     "custom sidebar DSL test input: user-written Swift source spells Image(systemName:)/Label(systemImage:)"),
] + [
    (p.relative_to(ROOT).as_posix(),
     "custom sidebar DSL corpus: user-written Swift source, interpreted (not compiled); "
     "its symbols render through ShellXIcon.image")
    for p in sorted((ROOT / SWIFTRENDER_CORPUS).glob("*.swift"))
    if re.search(SF_PATTERN, p.read_text(encoding="utf-8"))
]

# String literals in an icon API's symbol argument that are not symbol names.
NON_SYMBOL_LITERALS = {
    "systemName": "custom sidebar DSL attribute key: node.string(\"systemName\") ?? fallback symbol",
}

# Where a symbol name from user configuration is drawn. Each must resolve it
# through ShellXIcon so a mapped name draws its coolicon and any other name
# draws that SF Symbol (never blank, never a crash).
DYNAMIC_CALL_SITES = [
    ("Sources/RenderableSystemSymbol.swift", "ShellXIcon.nsImage(",
     "workspace group `iconSymbol`, surface tab icons and `sidebar.compactStatusIcons` (via "
     "SidebarCompactStatusGlyphView) are validated and rasterized here"),
    ("Packages/macOS/CmuxAppKitSupportUI/Sources/CmuxAppKitSupportUI/IconRendering/CmuxResolvedIconRenderer.swift",
     "ShellXIcon.nsImage(", "hosted symbol renderer behind CmuxSystemSymbolImage and the Vault icons"),
    ("Sources/CmuxConfigUI.swift", "ShellXIcon.nsImage(",
     "custom command and config context-menu icons (CmuxButtonIcon .systemImage); the surface tab bar itself "
     "is drawn by Bonsplit (see scripts/shellx/icon-substitutions.md, Not covered yet)"),
    ("Packages/macOS/CmuxSwiftRenderUI/Sources/CmuxSwiftRenderUI/Rendering/RenderNodeView.swift",
     "ShellXIcon.image(", "custom sidebar DSL `Image(systemName:)` / `Label(_:systemImage:)` nodes"),
]

# Packages the CLI reaches whose manifest names ShellXIcons only for targets
# the CLI does not link.
CLI_REACHABLE_ICON_PACKAGES = {
    "Packages/Shared/ShellXBrand": "defines the ShellXIcons product next to ShellXBrand; the CLI links ShellXBrand only",
}


def literal_symbols_before_codemod() -> list[str]:
    return [
        line.strip()
        for line in SNAPSHOT.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    ]


def load_map() -> dict:
    with MAP_PATH.open(encoding="utf-8") as fh:
        return json.load(fh)


def guarded_roots() -> list[str]:
    """GUARDED_ROOTS without SwiftPM build directories (never committed, can
    hold thousands of files and third-party checkouts)."""
    roots = ["Sources"]
    for group in GUARDED_ROOTS[1:]:
        for package in sorted((ROOT / group).iterdir()):
            if package.is_dir():
                roots += [
                    child.relative_to(ROOT).as_posix()
                    for child in sorted(package.iterdir())
                    if child.name not in (".build", ".swiftpm")
                ]
    return roots


def substitution_rows() -> list[tuple[str, str, str, str]]:
    rows = []
    for line in read(SUBSTITUTIONS).splitlines():
        m = re.fullmatch(r"\| `([^`]+)` \| `([^`]+)` \| (same|nearest|derived) \|(.*)\|", line.strip())
        if m:
            rows.append((m.group(1), m.group(2), m.group(3), m.group(4).strip()))
    return rows


def pbx_objects() -> str:
    return read(PBXPROJ)


def target_product_dependencies(pbx: str, target: str) -> list[str]:
    for m in re.finditer(r"isa = PBXNativeTarget;(.*?)\n\t\t\};", pbx, re.S):
        body = m.group(1)
        if re.search(rf'\bname = "?{re.escape(target)}"?;', body):
            deps = re.search(r"packageProductDependencies = \((.*?)\);", body, re.S)
            return re.findall(r"/\* (\S+) \*/", deps.group(1)) if deps else []
    raise AssertionError(f"target {target} not in {PBXPROJ}")


def product_package_paths(pbx: str) -> dict[str, str]:
    """{product name: local package path} for XCSwiftPackageProductDependency."""
    packages = dict(re.findall(
        r"(\w+) /\* XCLocalSwiftPackageReference \"[^\"]*\" \*/ = \{isa = XCLocalSwiftPackageReference; "
        r"relativePath = \"?([^\";]+)\"?;", pbx))
    products = {}
    for ref, name in re.findall(
            r"isa = XCSwiftPackageProductDependency; package = (\w+) /\*[^*]*\*/; productName = \"?([^\";]+)\"?;", pbx):
        if ref in packages:
            products[name] = packages[ref]
    return products


def local_package_deps(package: str) -> set[str]:
    manifest = ROOT / package / "Package.swift"
    deps = set()
    for rel in re.findall(r'\.package\(\s*(?:name:\s*"[^"]*",\s*)?path:\s*"([^"]+)"', manifest.read_text(encoding="utf-8")):
        deps.add((ROOT / package / rel).resolve().relative_to(ROOT).as_posix())
    return deps


class ShellXIconsGuard(unittest.TestCase):
    def test_no_direct_sf_symbol_calls_outside_shellxicon(self):
        hits = offenders(SF_PATTERN, roots=guarded_roots(), allow=DYNAMIC_ALLOWLIST)
        self.assertEqual(hits, [])

    def test_allowlist_entries_exist_and_are_needed(self):
        rx = re.compile(SF_PATTERN)
        for path, reason in DYNAMIC_ALLOWLIST:
            self.assertTrue((ROOT / path).is_file(), path)
            self.assertTrue(reason)
            self.assertTrue(rx.search(read(path)), f"{path} no longer spells an SF Symbol API; drop it")

    def test_every_literal_symbol_is_mapped(self):
        used = literal_symbols_before_codemod()
        self.assertGreater(len(used), 200)
        mapping = load_map()
        self.assertEqual(sorted(set(used) - set(mapping)), [])

    def test_map_matches_the_substitution_record(self):
        rows = substitution_rows()
        self.assertEqual({sf: cool for sf, cool, _, _ in rows}, load_map())
        self.assertEqual(len(rows), len({sf for sf, _, _, _ in rows}), "duplicate SF Symbol rows")
        for sf, cool, match, note in rows:
            if match != "same":
                self.assertTrue(note, f"{sf} -> {cool} is a {match} substitution without a reason")
            if match == "derived":
                self.assertIn(cool, DERIVED, sf)

    def test_every_mapped_coolicon_is_in_the_catalog(self):
        mapping = load_map()
        missing = sorted(
            {name for name in mapping.values() if not (CATALOG / f"{name}.symbolset" / f"{name}.svg").is_file()}
        )
        self.assertEqual(missing, [])

    def test_catalog_has_all_coolicons_as_symbols(self):
        symbolsets = sorted(p.name[: -len(".symbolset")] for p in CATALOG.glob("*.symbolset"))
        self.assertEqual(len(symbolsets), COOLICON_COUNT + len(DERIVED))
        self.assertTrue(DERIVED <= set(symbolsets))
        for name in symbolsets:
            svg = (CATALOG / f"{name}.symbolset" / f"{name}.svg").read_text(encoding="utf-8")
            contents = json.loads((CATALOG / f"{name}.symbolset" / "Contents.json").read_text(encoding="utf-8"))
            self.assertEqual(contents["symbols"], [{"filename": f"{name}.svg", "idiom": "universal"}], name)
            for guide in ("Baseline-S", "Capline-M", "Baseline-L", "left-margin-Regular-M", "right-margin-Regular-M"):
                self.assertIn(f'id="{guide}"', svg, name)
            symbols = svg.split('<g id="Symbols">', 1)[1]
            paths = re.findall(r"<path [^>]*>", symbols)
            self.assertEqual(len(paths), 3, f"{name}: one glyph per scale (S, M, L)")
            for scale in ("S", "M", "L"):
                self.assertIn(f'id="Regular-{scale}"', symbols, name)
            self.assertNotIn("stroke", symbols, f"{name}: strokes must be outlined to fills")

    def test_names_later_tasks_use_exist(self):
        for name in ("Laptop", "Desktop", "Data", "Mobile", "Link", "Terminal", "Bell_Ring", "Add_Plus",
                     "Search_Magnifying_Glass", "Settings", "Circle_Check", "Shield_Check", "Users",
                     "Window_Sidebar", "More_Horizontal", "Qr_Code"):
            self.assertTrue((CATALOG / f"{name}.symbolset" / f"{name}.svg").is_file(), name)

    def test_license_notice_ships_with_assets(self):
        notice = NOTICE.read_text(encoding="utf-8")
        for needle in ("coolicons", "Kryston Schwarze", "CC BY 4.0", "Circle_Fill"):
            self.assertIn(needle, notice)
        self.assertIn("coolicons by Kryston Schwarze", read("THIRD_PARTY_LICENSES.md"))
        self.assertIn("coolicons by Kryston Schwarze", read("Sources/AboutLicenseContent.swift"))

    def test_codemod_rewrites_are_idempotent(self):
        sys.path.insert(0, str(ROOT / "scripts/shellx"))
        import icon_codemod  # noqa: E402

        for path in icon_codemod.swift_files():
            text = path.read_text(encoding="utf-8")
            new, counts = icon_codemod.rewrite(text)
            self.assertEqual(new, text, f"{path} still has rewritable SF Symbol calls: {counts}")

    def test_literal_symbols_at_icon_calls_are_mapped(self):
        """A literal passed straight to ShellXIcon / ShellXLabel /
        CmuxSystemSymbolImage after the codemod must be mapped, or it would
        quietly draw an SF Symbol."""
        sys.path.insert(0, str(ROOT / "scripts/shellx"))
        import icon_codemod  # noqa: E402

        mapping = load_map()
        found = icon_codemod.literals_at_icon_calls()
        self.assertGreater(len(found), 300)
        unmapped = sorted(
            f"{path}:{line}: {literal!r}"
            for path, line, literal in found
            if literal not in mapping and literal not in NON_SYMBOL_LITERALS
        )
        self.assertEqual(unmapped, [])

    def test_user_configured_symbols_render_through_shellxicon(self):  # Review Focus 3
        for path, needle, reason in DYNAMIC_CALL_SITES:
            self.assertIn(needle, read(path), f"{path}: {reason}")

    def test_icon_imports_are_wired(self):
        """Every file that imports ShellXIcons belongs to a target that
        depends on the product: the app (cmux.xcodeproj) or a package target
        whose manifest names it."""
        pbx = pbx_objects()
        self.assertIn("ShellXIcons", target_product_dependencies(pbx, "cmux"))
        importers = sorted(
            p.relative_to(ROOT).as_posix()
            for root in guarded_roots()
            for p in ([ROOT / root] if (ROOT / root).is_file() else (ROOT / root).rglob("*.swift"))
            if p.suffix == ".swift" and re.search(r"^\s*(?:@\w+\s+)?(?:\w+\s+)?import ShellXIcons\b",
                                                  p.read_text(encoding="utf-8"), re.M)
        )
        self.assertGreater(len(importers), 50)
        for path in importers:
            parts = path.split("/")
            if parts[0] == "Sources" or path.startswith("Packages/Shared/ShellXBrand/"):
                continue
            package, kind, target = "/".join(parts[:3]), parts[3], parts[4]
            manifest = read(f"{package}/Package.swift")
            self.assertIn('"ShellXIcons"', manifest, f"{path}: {package}/Package.swift lacks the ShellXIcons product")
            block = re.search(
                rf'\.(?:target|testTarget|executableTarget)\(\s*name:\s*"{re.escape(target)}"(.*?)\n\s*\),?\n',
                manifest, re.S)
            self.assertIsNotNone(block, f"{path}: target {target} not found in {package}/Package.swift")
            self.assertIn('"ShellXIcons"', block.group(1), f"{path}: target {target} does not depend on ShellXIcons")

    def test_cli_never_links_shellxicons(self):
        pbx = pbx_objects()
        cli_products = target_product_dependencies(pbx, "cmux-cli")
        self.assertIn("ShellXBrand", cli_products)
        self.assertNotIn("ShellXIcons", cli_products)
        paths = product_package_paths(pbx)
        reachable, todo = set(), [paths[p] for p in cli_products if p in paths]
        while todo:
            package = todo.pop()
            if package in reachable:
                continue
            reachable.add(package)
            todo += sorted(local_package_deps(package))
        offending = sorted(
            p for p in reachable
            if "ShellXIcons" in read(f"{p}/Package.swift") and p not in CLI_REACHABLE_ICON_PACKAGES
        )
        self.assertEqual(offending, [], "packages the CLI links (directly or not) must not use ShellXIcons")


if __name__ == "__main__":
    unittest.main()
