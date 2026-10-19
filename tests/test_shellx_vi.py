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


def localization_values(localization: dict):
    """Every string value of one locale block: unit, plural variations and substitutions."""
    value = leaf(localization)
    if value is not None:
        yield value
    for variants in localization.get("variations", {}).values():
        for node in variants.values():
            yield from localization_values(node)
    for substitution in localization.get("substitutions", {}).values():
        yield from localization_values(substitution)


# Glossary: workspace -> "phiên", pane -> "khung", command palette -> "bảng lệnh".
PHRASES_NEVER_USED = re.compile(r"không gian làm việc|bảng điều khiển lệnh|bảng màu lệnh", re.I)
# "bề mặt" is the literal rendering of "surface"; the glossary word is "tab". Never right, anywhere.
LITERAL_SURFACE = re.compile(r"bề mặt", re.I)
# Glossary: surface -> "tab", machine -> "máy". The English word must not survive in prose.
ENGLISH_TERM = re.compile(r"\b(?:surfaces?|machines?)\b", re.I)
# Real CLI command names that contain "surface" (CLI/cmux.swift `case "..."`, CLI/CMUXCLI+CommandSuggestions.swift,
# CLI/CMUXCLI+TaskHelp.swift). A user types them, so they are never translated to "tab".
CLI_COMMAND_NAMES = (
    "close-surface",
    "new-surface",
    "move-surface",
    "reorder-surface",
    "drag-surface-to-split",
    "list-pane-surfaces",
    "refresh-surfaces",
    "surface-health",
    "surface-resume",
)
COMMAND_NAME = re.compile(r"(?<![\w-])(?:%s)(?![\w-])" % "|".join(map(re.escape, CLI_COMMAND_NAMES)))
# Flags that carry the word ("--surface", "--machine"): English and Vietnamese must spell them alike.
FLAG_WITH_TERM = re.compile(r"(?<![\w-])--[A-Za-z0-9-]*(?:surface|machine)[A-Za-z0-9-]*")
# Code and identifier tokens that legitimately keep the English word: the CLI/socket surface mirrors
# them, so a user types or reads exactly these characters.
CODE_TOKENS = re.compile(
    "|".join(
        [
            COMMAND_NAME.pattern,  # close-surface, new-surface, list-pane-surfaces, ...
            r"`[^`\n]*`",  # `machine`, `vm open <machine>/<workspace>`
            r"--[A-Za-z0-9-]*(?:surface|machine)[A-Za-z0-9-]*",  # --surface, --machine, --surface=<id>
            r"\bsurface:[^\s,)'\"]+",  # handles: surface:2, surface:<id>
            r"<[^<>\n]*\b(?:surfaces?|machines?)\b[^<>\n]*>",  # usage placeholders: <surface>, <status|machines|claude>
            r"\bshellx surface\b",  # the `shellx surface` command group
            r"\bsurface (?:ls|open|new-terminal|resume|size|participants|size-policy|size-to-me|"
            r"disconnect-others|size-counts|disconnect-participant)\b",  # its sub-commands in diagnostics
            r"\bsurface\.[a-z_]+",  # socket method names: surface.sync_codex_native_title
            r"\bsurface-[a-z-]+",  # ids: surface-needs-input
            r"\bsurface=",  # machine-readable output: session=%@ surface=%@
            r"([\"'])surfaces\1",  # JSON key: "surfaces"
            r"\{[A-Za-z_]+(?:,\s*[A-Za-z_]+)*\}",  # payload shape: {machines, resources, projections}
        ]
    )
)
# Settings search aliases deliberately keep the English keywords next to the Vietnamese ones (see
# vi-glossary.md), and the debug.* strings are the developer-only Debug menu windows.
ENGLISH_TERMS_ALLOWED_KEY_PREFIXES = {
    "settings.search.alias.": "keyword strings keep English words so both languages find the row",
    "debug.": "developer-only Debug menu windows",
}


def glossary_problems(key: str, value: str, english: list[str]) -> list[str]:
    """Glossary violations of one Vietnamese value; `english` are the English values of the same entry."""
    found = []
    if PHRASES_NEVER_USED.search(value):
        found.append("banned phrase")
    if LITERAL_SURFACE.search(value):
        found.append('"bề mặt" (use "tab")')
    if value in english or key.startswith(tuple(ENGLISH_TERMS_ALLOWED_KEY_PREFIXES)):
        return found  # identity strings (a token spelled like the English) and the allowed keys
    leftover = ENGLISH_TERM.findall(CODE_TOKENS.sub(" ", value))
    if leftover:
        found.append(f'English {sorted({word.lower() for word in leftover})} (use "tab" / "máy")')
    return found


def dropped_cli_tokens(key: str, english: list[str], vi: list[str]) -> list[str]:
    """Command names and flags of a cli.*/socket.* English value that the Vietnamese value lost.

    Rewriting `close-surface` as `close-tab` makes the message name a command that does not exist.
    """
    if not key.startswith(("cli.", "socket.")):
        return []
    source, target = " ".join(english), " ".join(vi)
    tokens = COMMAND_NAME.findall(source) + FLAG_WITH_TERM.findall(source)
    return sorted({token for token in tokens if token not in target})


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
        hits = []
        for path, strings in self.catalogs.items():
            for key, entry in strings.items():
                if entry.get("shouldTranslate") is False:
                    continue
                localizations = entry.get("localizations", {})
                english = list(localization_values(localizations.get("en", {})))
                for value in localization_values(localizations.get("vi", {})):
                    for problem in glossary_problems(key, value, english):
                        hits.append(f"{path}:{key}: {problem}: {value[:80]!r}")
        self.assertEqual(hits, [], f"{len(hits)} glossary violations, e.g. {hits[:10]}")

    def test_cli_strings_keep_command_names_and_flags_from_english(self):
        hits = []
        for path, strings in self.catalogs.items():
            for key, entry in strings.items():
                if entry.get("shouldTranslate") is False:
                    continue
                localizations = entry.get("localizations", {})
                english = list(localization_values(localizations.get("en", {})))
                vi = list(localization_values(localizations.get("vi", {})))
                for token in dropped_cli_tokens(key, english, vi):
                    hits.append(f"{path}:{key}: vi lost {token!r}")
        self.assertEqual(hits, [], f"{len(hits)} command names or flags dropped, e.g. {hits[:10]}")

    def test_command_names_are_real(self):
        # Every pinned name is a command or sub-command the CLI source really defines.
        sources = "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted((ROOT / "CLI").glob("*.swift"))
        )
        for name in CLI_COMMAND_NAMES:
            self.assertTrue(f'"{name}"' in sources, f"{name} is not a CLI command or sub-command name")

    def test_dropped_command_name_check(self):
        key = "cli.closeSurface.error.x"
        english = ["close-surface requires --workspace or --window with explicit --surface"]
        self.assertEqual(
            dropped_cli_tokens(key, english, ["close-tab yêu cầu --workspace hoặc --window cùng với --surface"]),
            ["close-surface"],
        )
        self.assertEqual(
            dropped_cli_tokens(key, english, ["close-surface yêu cầu --workspace hoặc --window cùng với --surface"]),
            [],
        )
        self.assertEqual(dropped_cli_tokens(key, english, ["close-surface yêu cầu --workspace, --window và tab"]), ["--surface"])
        self.assertEqual(
            dropped_cli_tokens("cli.vault.usage", ["machine-readable output"], ["đầu ra cho máy đọc"]), []
        )  # prose compounds are not command names
        self.assertEqual(dropped_cli_tokens("menu.x", english, ["Đóng tab"]), [])  # only cli.*/socket.* keys

    def test_glossary_check_flags_wrong_terms_and_spares_code_tokens(self):
        for value in (
            "Surface tiếp theo",
            "Sao chép ID bề mặt",
            "Cloud machine không khả dụng",
            "Không tìm thấy surface: %@",
            "Dùng shellx surface ls để xem machines",
            "Không có surface nào, hãy chạy lại 'shellx restore --surface'",
        ):
            self.assertTrue(glossary_problems("menu.x", value, ["English"]), value)
        for value in (
            "close-surface yêu cầu --workspace hoặc --window cùng với --surface tường minh",
            "Dùng shellx new-surface, move-surface, reorder-surface hoặc drag-surface-to-split",
            "Chạy shellx list-pane-surfaces và shellx refresh-surfaces",
            "Chạy shellx surface-health hoặc surface-resume",
            "Hãy thử lại 'shellx restore --surface'.",
            'Cách dùng: shellx send --surface surface:2 "ls"',
            "Cách dùng: shellx surface ls [<machine>|local] [--refresh]",
            "OK session=%@ surface=%@ mode=local-tmux",
            "Khi `machine` là null, dùng `vm open <machine>/<workspace>`",
            "{\"pane\": {\"surfaces\": []}} và 'surfaces' phải là mảng",
            "In payload danh mục ({machines, resources, projections}).",
            "chạy shellx automation show surface-needs-input",
            "surface.sync_codex_native_title yêu cầu hàng đợi",
            "surface resume set: cờ không xác định",
            "coderouter <status|machines|claude> [--team <id>]",
        ):
            self.assertEqual(glossary_problems("cli.x", value, ["English"]), [], value)
        self.assertEqual(glossary_problems("cli.localTmux.target.surface", "surface", ["surface"]), [])
        self.assertEqual(glossary_problems("settings.search.alias.x", "terminal surface máy", ["terminal surface"]), [])
        self.assertEqual(glossary_problems("debug.x", "Surface opacity", ["Surface opacity"]), [])
        # The allowlists never excuse the literal "bề mặt".
        self.assertTrue(glossary_problems("settings.search.alias.x", "bề mặt", ["x"]))
        self.assertTrue(glossary_problems("debug.x", "Độ mờ bề mặt", ["x"]))
        self.assertTrue(glossary_problems("cli.localTmux.target.surface", "bề mặt", ["surface"]))


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
