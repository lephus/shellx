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
from __future__ import annotations

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
    "Packages/macOS/CmuxSimulator": "ShellXIcons is a dependency of CmuxSimulatorUI only; the CLI links the "
                                    "CmuxSimulator product (targets CmuxSimulator, CmuxSimulatorSystem)",
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


def pbx_object_fields(pbx: str) -> dict[str, dict[str, str]]:
    """{object id: {field: value}} for every pbxproj object, single-line
    (`= {isa = ...; a = b; };`) or multi-line."""
    objects = {}
    for m in re.finditer(r"^\t\t(\w+) /\*[^\n]*?\*/ = \{", pbx, re.M):
        depth, i = 0, m.end() - 1
        while True:
            depth += {"{": 1, "}": -1}.get(pbx[i], 0)
            if depth == 0:
                break
            i += 1
        body = re.sub(r"/\*.*?\*/", "", pbx[m.end():i])
        objects[m.group(1)] = {
            key: value.strip().strip('"') for key, value in re.findall(r"(\w+) = ([^;{}()]*);", body)
        }
    return objects


def product_package_paths(pbx: str) -> dict[str, str]:
    """{product name: local package path} for each XCSwiftPackageProductDependency."""
    objects = pbx_object_fields(pbx)
    products = {}
    for fields in objects.values():
        if fields.get("isa") == "XCSwiftPackageProductDependency":
            package = objects.get(fields.get("package", ""), {})
            if package.get("isa") == "XCLocalSwiftPackageReference":
                products[fields["productName"]] = package["relativePath"]
    return products


class Manifest:
    """The parts of a Package.swift the CLI-linkage check needs: package
    name, local path dependencies, products and each target's dependencies."""

    def __init__(self, package: str):
        sys.path.insert(0, str(ROOT / "scripts/shellx"))
        import icon_codemod  # noqa: E402

        self.package = package
        text = (ROOT / package / "Package.swift").read_text(encoding="utf-8")
        masked = icon_codemod.mask(text)

        def call_args(open_idx: int) -> tuple[int, int, dict]:
            close = icon_codemod.matching_paren(masked, open_idx)
            return open_idx, close, icon_codemod.top_level_label_spans(masked, open_idx, close)

        def label_strings(spans: dict, label: str, close: int) -> list[str]:
            if label not in spans:
                return []
            start = spans[label][1]
            later = sorted(s for s, _ in spans.values() if s > start)
            end = later[0] if later else close
            return [text[start + m.start(1):start + m.end(1)] for m in re.finditer(r'"(_*)"', masked[start:end])]

        name = re.search(r"\bPackage\(", masked)
        _, close, spans = call_args(name.end() - 1)
        self.name = label_strings(spans, "name", close)[0]
        self.path_deps: dict[str, str] = {}
        for m in re.finditer(r"\.package\(", masked):
            _, close, spans = call_args(m.end() - 1)
            for rel in label_strings(spans, "path", close):
                path = (ROOT / package / rel).resolve().relative_to(ROOT).as_posix()
                self.path_deps[Path(rel).name] = path
                for named in label_strings(spans, "name", close):
                    self.path_deps[named] = path
        self.products: dict[str, list[str]] = {}
        for m in re.finditer(r"\.(?:library|executable)\(", masked):
            _, close, spans = call_args(m.end() - 1)
            self.products[label_strings(spans, "name", close)[0]] = label_strings(spans, "targets", close)
        self.targets: dict[str, list[tuple[str, str | None]]] = {}
        for m in re.finditer(r"\.(?:target|executableTarget|testTarget|binaryTarget|systemLibrary)\(", masked):
            _, close, spans = call_args(m.end() - 1)
            target = label_strings(spans, "name", close)[0]
            deps: list[tuple[str, str | None]] = []
            if "dependencies" in spans:
                start = spans["dependencies"][1]
                later = sorted(s for s, _ in spans.values() if s > start)
                block = masked[start:(later[0] if later else close)]
                for d in re.finditer(r'\.product\(\s*name:\s*"(_*)",\s*package:\s*"(_*)"', block):
                    deps.append((text[start + d.start(1):start + d.end(1)], text[start + d.start(2):start + d.end(2)]))
                # Blank the .product(...) calls (same length, so offsets hold).
                plain = re.sub(r"\.product\([^)]*\)", lambda p: " " * len(p.group()), block)
                deps += [(text[start + d.start(1):start + d.end(1)], None)
                         for d in re.finditer(r'"(_*)"', plain)]
            self.targets[target] = deps


def cli_reachable_targets(pbx: str) -> set[tuple[str, str]]:
    """(package, target) pairs the cmux-cli target links: the targets of its
    package products and, recursively, their target and product dependencies."""
    manifests: dict[str, Manifest] = {}

    def manifest(package: str) -> Manifest:
        if package not in manifests:
            manifests[package] = Manifest(package)
        return manifests[package]

    def product_targets(package: str, product: str) -> list[tuple[str, str]]:
        return [(package, target) for target in manifest(package).products.get(product, [])]

    paths = product_package_paths(pbx)
    todo = [pair for product in target_product_dependencies(pbx, "cmux-cli") if product in paths
            for pair in product_targets(paths[product], product)]
    seen: set[tuple[str, str]] = set()
    while todo:
        package, target = todo.pop()
        if (package, target) in seen:
            continue
        seen.add((package, target))
        m = manifest(package)
        for name, owner in m.targets.get(target, []):
            if owner is None and name in m.targets:
                todo.append((package, name))
                continue
            candidates = [m.path_deps[owner]] if owner in m.path_deps else (
                list(m.path_deps.values()) if owner is None else [])
            for dep in candidates:
                todo += product_targets(dep, name)
    return seen


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
            package, target = "/".join(parts[:3]), parts[4]
            manifest = Manifest(package)
            self.assertIn(target, manifest.targets, f"{path}: target {target} not found in {package}/Package.swift")
            self.assertIn(("ShellXIcons", "ShellXBrand"), manifest.targets[target],
                          f"{path}: target {target} does not depend on the ShellXIcons product")
            self.assertEqual(Path(ROOT / manifest.path_deps["ShellXBrand"]), ROOT / "Packages/Shared/ShellXBrand")

    def test_cli_never_links_shellxicons(self):
        """The shellx CLI must not carry the icon resource bundle: no CLI
        product is ShellXIcons, and no target the CLI links (through any
        chain of local package targets and products) depends on it."""
        pbx = pbx_objects()
        cli_products = target_product_dependencies(pbx, "cmux-cli")
        self.assertIn("ShellXBrand", cli_products)
        self.assertNotIn("ShellXIcons", cli_products)
        paths = product_package_paths(pbx)
        unresolved = sorted(p for p in cli_products if p not in paths)
        self.assertEqual(unresolved, [], "every CLI package product must resolve to a local package")
        reachable = cli_reachable_targets(pbx)
        self.assertIn(("Packages/Shared/ShellXBrand", "ShellXBrand"), reachable)
        self.assertIn(("Packages/macOS/CmuxSimulator", "CmuxSimulator"), reachable)
        self.assertNotIn(("Packages/macOS/CmuxSimulator", "CmuxSimulatorUI"), reachable)
        self.assertGreater(len(reachable), 15)
        offending = sorted(
            f"{package}:{target}"
            for package, target in reachable
            if target == "ShellXIcons"
            or any(name == "ShellXIcons" for name, _ in Manifest(package).targets.get(target, []))
        )
        self.assertEqual(offending, [], "targets the CLI links (directly or not) must not use ShellXIcons")
        # The packages the CLI reaches that also hold ShellXIcons users keep
        # them in targets the CLI does not link (e.g. CmuxSimulatorUI).
        packages = {package for package, _ in reachable}
        icon_packages = sorted(p for p in packages if "ShellXIcons" in read(f"{p}/Package.swift"))
        self.assertEqual(icon_packages, sorted(CLI_REACHABLE_ICON_PACKAGES), icon_packages)


if __name__ == "__main__":
    unittest.main()
