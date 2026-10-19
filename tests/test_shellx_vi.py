#!/usr/bin/env python3
"""Guard: ShellX ships a complete Vietnamese (vi) localization on macOS.

Covers every catalog that `scripts/localization_catalog.py check` validates
(Resources/, TunnelExtension/ and the Packages/macOS catalogs), the Xcode
project region list, the Settings language picker and the l10n tooling under
scripts/shellx/l10n.

Usage (from the repo root):
    python3 tests/test_shellx_vi.py
"""
from __future__ import annotations

import importlib.util
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from shellx_look_guard import read  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
MAIN_CATALOG = "Resources/Localizable.xcstrings"
FORMAT = re.compile(
    r"%%|%(?:\d+\$)?#@[^@]+@|%(?:\d+\$)?[-+ #0']*(?:\d+|\*(?:\d+\$)?)?"
    r"(?:\.(?:\d+|\*(?:\d+\$)?))?(?:hh|ll|[hlLqjzt])?[diouxXfFeEgGaAcCsSp@]"
)


def load_module(name: str, relative: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[name] = module  # dataclasses look the module up while loading
    spec.loader.exec_module(module)
    return module


CATALOG_TOOL = load_module("shellx_vi_localization_catalog", "scripts/localization_catalog.py")


def placeholders(text: str) -> list[str]:
    return FORMAT.findall(text)


def covered_catalogs() -> list[str]:
    return [p.relative_to(ROOT).as_posix() for p in CATALOG_TOOL.discover(ROOT)]


def leaf(node: dict) -> str | None:
    value = node.get("stringUnit", {}).get("value")
    return value if isinstance(value, str) else None


def plural_other(node: dict) -> str | None:
    plural = node.get("variations", {}).get("plural", {})
    return leaf(plural.get("other", {})) if plural else None


def problems(english: dict, vi: dict | None) -> list[str]:
    """Missing or placeholder-mismatched Vietnamese units for one entry."""
    if vi is None:
        return ["missing vi"]
    found = []
    units = list(CATALOG_TOOL.units(vi))
    if not units:
        found.append("no vi string unit")
    for location, unit in units:
        if unit.get("state") != "translated" or not str(unit.get("value", "")).strip():
            found.append(f"vi{location} not translated")
    if "stringUnit" in english:
        source, target = leaf(english), leaf(vi)
        if target is None:
            found.append("vi lacks stringUnit")
        elif placeholders(target) != placeholders(source):
            found.append(f"placeholders {placeholders(target)} != {placeholders(source)}")
    if "plural" in english.get("variations", {}):
        source, target = plural_other(english), plural_other(vi)
        if target is None:
            found.append("vi lacks plural.other")
        elif placeholders(target) != placeholders(source):
            found.append(f"plural placeholders {placeholders(target)} != {placeholders(source)}")
    for name, substitution in english.get("substitutions", {}).items():
        mine = vi.get("substitutions", {}).get(name)
        if mine is None:
            found.append(f"vi lacks substitution {name}")
            continue
        if (mine.get("argNum"), mine.get("formatSpecifier")) != (substitution.get("argNum"), substitution.get("formatSpecifier")):
            found.append(f"substitution {name} argNum/formatSpecifier differ")
        source, target = plural_other(substitution), plural_other(mine)
        if target is None:
            found.append(f"substitution {name} lacks plural.other")
        elif placeholders(target) != placeholders(source):
            found.append(f"substitution {name} placeholders differ")
    return found


class VietnameseCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalogs = {path: json.loads(read(path))["strings"] for path in covered_catalogs()}
        cls.main = cls.catalogs[MAIN_CATALOG]

    def vi(self, key: str, catalog: str = MAIN_CATALOG) -> str | None:
        localization = self.catalogs[catalog].get(key, {}).get("localizations", {}).get("vi", {})
        return leaf(localization) or plural_other(localization)

    def test_every_covered_catalog_is_checked(self):
        self.assertIn(MAIN_CATALOG, self.catalogs)
        self.assertIn("Resources/InfoPlist.xcstrings", self.catalogs)
        self.assertGreaterEqual(len(self.catalogs), 10)

    def test_vi_is_complete_and_placeholders_match(self):
        hits = []
        for path, strings in self.catalogs.items():
            for key, entry in strings.items():
                if entry.get("shouldTranslate") is False:
                    continue
                localizations = entry.get("localizations", {})
                for problem in problems(localizations.get("en", {}), localizations.get("vi")):
                    hits.append(f"{path}:{key}: {problem}")
        self.assertEqual(hits, [], f"{len(hits)} vi problems, e.g. {hits[:10]}")

    def test_key_menus_read_naturally(self):
        expected = {
            "menu.app.about": "Giới thiệu về ShellX",
            "menu.quitCmux": "Thoát ShellX",
            "menu.app.settings": "Cài đặt…",
            "menu.file.newWorkspace": "Phiên mới",
            "menu.file.commandPalette": "Bảng lệnh…",
            "menu.view.toggleLeftSidebar": "Bật/tắt thanh bên trái",
            "menu.view.splitRight": "Chia sang phải",
        }
        for key, value in expected.items():
            self.assertEqual(self.vi(key), value, key)

    @unittest.skipUnless(
        "sidebar.pill.waiting" in json.loads(read(MAIN_CATALOG))["strings"],
        "sidebar.pill.waiting is added by lane L3 (Task 10); not on this branch yet",
    )
    def test_sidebar_waiting_pill_reads_naturally(self):
        self.assertEqual(self.vi("sidebar.pill.waiting"), "chờ bạn")

    @unittest.skipUnless(
        "sidebar.machine.thisMac" in json.loads(read(MAIN_CATALOG))["strings"],
        "sidebar.machine.thisMac is added by lane L3 (Task 10); not on this branch yet",
    )
    def test_sidebar_this_mac_reads_naturally(self):
        self.assertEqual(self.vi("sidebar.machine.thisMac"), "máy này")

    def test_glossary_words_are_used(self):
        # workspace is "phiên", pane is "khung", command palette is "bảng lệnh".
        banned = re.compile(r"không gian làm việc|bảng điều khiển lệnh|bảng màu lệnh", re.I)
        hits = []
        for path, strings in self.catalogs.items():
            for key, entry in strings.items():
                for _, unit in CATALOG_TOOL.units(entry.get("localizations", {}).get("vi", {})):
                    if banned.search(str(unit.get("value", ""))):
                        hits.append(f"{path}:{key}")
        self.assertEqual(hits, [], f"glossary violations: {hits[:10]}")


class VietnameseProjectWiringTests(unittest.TestCase):
    def test_catalog_tool_requires_vi(self):
        self.assertIn("vi", CATALOG_TOOL.LOCALES)

    def test_xcode_project_knows_the_vi_region(self):
        regions = re.search(r"knownRegions = \((.*?)\);", read("cmux.xcodeproj/project.pbxproj"), re.S)
        self.assertIsNotNone(regions)
        self.assertIn("vi", re.findall(r'"?([A-Za-z-]+)"?,', regions.group(1)))

    def test_settings_language_picker_offers_vietnamese(self):
        section = read("Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/AppSection.swift")
        cases = re.search(r"legacyLanguageCases: \[AppLanguage\] = \[(.*?)\]", section, re.S)
        self.assertIsNotNone(cases)
        self.assertIn(".vi", cases.group(1))
        self.assertIn('case .vi: return "Tiếng Việt (Vietnamese)"', read(
            "Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/AppSection+DisplayText.swift"))

    def test_config_schema_accepts_vi(self):
        schema = read("Packages/macOS/CmuxFoundation/Sources/CmuxFoundation/ConfigValidation/CmuxConfigSchema.generated.swift")
        language = re.search(r'"language": \{\s*"type": "string",\s*"enum": \[(.*?)\]', schema, re.S)
        self.assertIsNotNone(language)
        self.assertIn('"vi"', language.group(1))

    def test_glossary_is_committed(self):
        glossary = read("scripts/shellx/l10n/vi-glossary.md")
        for pair in ("workspace", "phiên", "pane", "khung", "command palette", "bảng lệnh", "sidebar", "thanh bên"):
            self.assertIn(pair, glossary)


TINY_CATALOG = """{
  "sourceLanguage": "en",
  "strings": {
    "greeting": {
      "extractionState": "manual",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Open %@ in %@"
          }
        },
        "ja": {
          "stringUnit": {
            "state": "translated",
            "value": "%@ を %@ で開く"
          }
        }
      }
    },
    "files": {
      "localizations": {
        "en": {
          "variations": {
            "plural": {
              "one": {
                "stringUnit": {
                  "state": "translated",
                  "value": "%lld file"
                }
              },
              "other": {
                "stringUnit": {
                  "state": "translated",
                  "value": "%lld files"
                }
              }
            }
          }
        }
      }
    },
    "detected": {
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Detected: %@, %#@count@."
          },
          "substitutions": {
            "count": {
              "argNum": 2,
              "formatSpecifier": "ld",
              "variations": {
                "plural": {
                  "one": {
                    "stringUnit": {
                      "state": "translated",
                      "value": "+%ld more"
                    }
                  },
                  "other": {
                    "stringUnit": {
                      "state": "translated",
                      "value": "+%ld more"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  },
  "version": "1.0"
}
"""


class VietnameseToolingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.importer = load_module("shellx_vi_import", "scripts/shellx/l10n/import_translations.py")
        cls.exporter = load_module("shellx_vi_export", "scripts/shellx/l10n/export_missing.py")

    def translations(self, **overrides):
        base = {
            "Tiny.xcstrings::greeting::value": "Mở %@ trong %@",
            "Tiny.xcstrings::files::plural.other": "%lld tệp",
            "Tiny.xcstrings::detected::value": "Đã phát hiện: %@, %#@count@.",
            "Tiny.xcstrings::detected::sub.count.other": "+%ld nữa",
        }
        base.update(overrides)
        return base

    def test_export_lists_missing_units_with_english_and_comment(self):
        rows = self.exporter.missing_units(TINY_CATALOG, "Tiny.xcstrings", "vi")
        self.assertEqual([row["id"] for row in rows], list(self.translations()))
        self.assertEqual(rows[0]["en"], "Open %@ in %@")
        batches = self.exporter.batched(rows * 200, 300)
        self.assertTrue(all(len(batch) <= 300 for batch in batches))

    def test_import_only_adds_vi_blocks_and_is_idempotent(self):
        text, stats = self.importer.import_text(TINY_CATALOG, "Tiny.xcstrings", self.translations(), "vi", validate=False)
        self.assertEqual(stats["added"], 3)
        self.assertEqual(stats["refused"], [])
        removed = [line for line in TINY_CATALOG.splitlines() if line not in text.splitlines()]
        self.assertEqual([line for line in removed if line.strip() not in {"}", "},"}], [])
        localizations = json.loads(text)["strings"]
        self.assertEqual(localizations["greeting"]["localizations"]["vi"]["stringUnit"]["value"], "Mở %@ trong %@")
        self.assertEqual(localizations["files"]["localizations"]["vi"]["variations"]["plural"],
                         {"other": {"stringUnit": {"state": "translated", "value": "%lld tệp"}}})
        substitution = localizations["detected"]["localizations"]["vi"]["substitutions"]["count"]
        self.assertEqual((substitution["argNum"], substitution["formatSpecifier"]), (2, "ld"))
        self.assertEqual(list(substitution["variations"]["plural"]), ["other"])
        again, stats = self.importer.import_text(text, "Tiny.xcstrings", self.translations(), "vi", validate=False)
        self.assertEqual(again, text)
        self.assertEqual(stats["added"] + stats["replaced"], 0)

    def test_import_refuses_placeholder_mismatch(self):
        bad = self.translations(**{"Tiny.xcstrings::greeting::value": "Mở %@"})
        text, stats = self.importer.import_text(TINY_CATALOG, "Tiny.xcstrings", bad, "vi", validate=False)
        self.assertEqual([row["key"] for row in stats["refused"]], ["greeting"])
        self.assertNotIn('"vi"', text.split('"files"')[0])

    def test_staged_batches_map_to_unit_ids(self):
        with tempfile.TemporaryDirectory() as folder:
            staged = Path(folder)
            (staged / "en-to-ids.json").write_text(json.dumps({"Open %@ in %@": ["Tiny.xcstrings::greeting::value"]}))
            (staged / "batch-00.en.json").write_text(json.dumps([{"i": 0, "en": "Open %@ in %@", "comment": ""}]))
            (staged / "batch-00.vi.json").write_text(json.dumps({"0": "Mở %@ trong %@"}))
            self.assertEqual(self.importer.load_staged(staged),
                             {"Tiny.xcstrings::greeting::value": {"vi": "Mở %@ trong %@", "en": "Open %@ in %@"}})


if __name__ == "__main__":
    unittest.main()
