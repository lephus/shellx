#!/usr/bin/env python3
"""Guard: the user-visible name is ShellX (UI strings, menus, CLI help, About).

`scripts/shellx/rebrand_strings.py` rewrites the catalogs and Swift defaults;
these tests check the outcome independently of the script's own rules, and
that rerunning the script is a no-op (Wave 2+ reruns it after upstream merges).

Usage (from the repo root):
    python3 tests/test_shellx_branding.py
"""
import importlib.util
import json
import re
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from shellx_look_guard import read  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts/shellx/rebrand_strings.py"
CATALOG = "Resources/Localizable.xcstrings"
MACOS_CATALOGS = [
    "Resources/Localizable.xcstrings",
    "Resources/InfoPlist.xcstrings",
    "Resources/ConfigPackErrors.xcstrings",
    *sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "Packages/macOS").glob("*/Sources/**/*.xcstrings")),
    *sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "Packages/Shared").glob("*/Sources/**/*.xcstrings")),
]

# A bare product word: "cmux" not glued to letters, digits or "_" (ASCII only, so
# "cmuxを" / "cmux가" count as bare words in CJK text).
BARE = re.compile(r"(?<![A-Za-z0-9_])cmux(?![A-Za-z0-9_])", re.I)
# Spellings that are identifiers, not the product name: URLs/domains (cmux.com,
# github.com/manaflow-ai/cmux), paths (/cmux, bin/cmux is checked below),
# joined identifiers (cmux-tui, cmux.sock, cmux:exec, foo-cmux, $cmux, @cmux), and
# option/setting values that name an identifier (`--agent cmux`, `chat.defaultAgent cmux`).
IDENTIFIER = re.compile(
    r"[A-Za-z0-9_.\-/@$\\=&?#:]cmux(?![A-Za-z0-9_])"
    r"|(?<![A-Za-z0-9_])cmux(?=[.:/][A-Za-z0-9_]|-[a-z0-9]|://)"
    r"|(?:(?<!\S)--[a-z][\w-]*|\b[a-z]\w*\.[A-Za-z]\w*) cmux(?![A-Za-z0-9_])",
    re.I,
)
# Paths and file names the rebrand must rename (they name ShellX's own files).
OLD_PATHS = re.compile(r"~/\.config/cmux|(?<![A-Za-z0-9])\.cmux/|(?<![A-Za-z0-9_\-.])cmux\.json|\.local/state/cmux", re.I)


def load_script():
    spec = importlib.util.spec_from_file_location("shellx_rebrand_strings", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def en_value(entry):
    unit = entry.get("localizations", {}).get("en", {}).get("stringUnit", {})
    return unit.get("value")


def all_values(node):
    if isinstance(node, dict):
        for name, child in node.items():
            if name == "value" and isinstance(child, str):
                yield child
            else:
                yield from all_values(child)


def leftover(text):
    """Bare product words left once identifier spellings are removed."""
    return BARE.findall(IDENTIFIER.sub(" ", text))


class ShellXBrandingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads(read(CATALOG))
        cls.strings = cls.catalog["strings"]

    def en(self, key):
        return en_value(self.strings[key])

    def test_no_cmux_in_english_ui_strings(self):
        preserve = load_script().PRESERVE_KEYS
        hits = [k for k, v in self.strings.items()
                if leftover(en_value(v) or "") and k not in preserve]
        self.assertEqual(hits, [], f"{len(hits)} English values still say cmux, e.g. {hits[:10]}")

    def test_no_cmux_in_any_locale_of_the_macos_catalogs(self):
        preserve = load_script().PRESERVE_KEYS
        hits = []
        for path in MACOS_CATALOGS:
            for key, entry in json.loads(read(path))["strings"].items():
                if key in preserve:
                    continue
                for locale, localization in entry.get("localizations", {}).items():
                    if any(leftover(value) for value in all_values(localization)):
                        hits.append(f"{path}:{key}:{locale}")
        self.assertEqual(hits, [], f"{len(hits)} values still say cmux, e.g. {hits[:10]}")

    def test_old_config_paths_are_renamed_in_english(self):
        preserve = load_script().PRESERVE_KEYS
        hits = [k for k, v in self.strings.items() if OLD_PATHS.search(en_value(v) or "") and k not in preserve]
        self.assertEqual(hits, [])

    def test_rebrand_script_is_idempotent(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "--check"], cwd=ROOT,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_menus_say_shellx(self):
        expected = {
            "menu.app.about": "About ShellX",
            "menu.quitCmux": "Quit ShellX",
            "menu.app.openCmuxSettingsFile": "Open shellx.json",
            "menu.app.makeDefaultTerminal": "Make ShellX the Default Terminal",
            "about.appName": "ShellX",
            "settings.app.accentColor.cmux": "ShellX Blue",
        }
        app = read("Sources/cmuxApp.swift")
        for key, value in expected.items():
            if key in self.strings:
                self.assertEqual(self.en(key), value, key)
        for key in ("menu.app.about", "menu.quitCmux", "menu.app.openCmuxSettingsFile", "menu.app.makeDefaultTerminal"):
            self.assertIn(f'"{key}", defaultValue: "{expected[key]}"', app)
        themes = read("Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/ThemesSection.swift")
        self.assertIn('defaultValue: "ShellX Blue"', themes)

    def test_cli_help_names_the_shellx_command(self):
        self.assertIn("Usage: shellx notify [flags]", self.en("cli.help.notify"))
        self.assertIn("  shellx notify --clear", self.en("cli.help.notify"))
        self.assertEqual(self.en("command.installCLI.title"), "Shell Command: Install 'shellx' in PATH")
        self.assertIn("Run 'shellx restore --surface' again.", self.en("agentRestore.admission.targetChanged"))
        # Prose about the app keeps the product name.
        self.assertIn("ShellX browser profile", self.en("browser.import.error.destinationMissing"))

    def test_identifiers_and_env_names_are_untouched(self):
        texts = "\n".join(en_value(v) or "" for v in self.strings.values())
        self.assertIn("cmux-tui", texts)
        self.assertIn("$CMUX_WORKSPACE_ID", texts)
        self.assertIn("cmux.com/", texts)
        self.assertNotIn("SHELLX_", texts)
        self.assertNotIn("shellx-tui", texts)

    _swift_defaults = None

    def swift_defaults(self):
        """(path, line, key, decoded default) for every localization default literal the script can see."""
        if ShellXBrandingTests._swift_defaults is not None:
            return ShellXBrandingTests._swift_defaults
        module = load_script()
        sites = []
        for path in module.swift_files():
            raw = path.read_text(encoding="utf-8")
            for start, (end, key) in module.default_sites(raw).items():
                decoded = module.decode_literal(raw[start:end])
                if decoded:
                    sites.append((path.relative_to(ROOT).as_posix(), raw.count("\n", 0, start) + 1, key, decoded[0]))
        ShellXBrandingTests._swift_defaults = (module, sites)
        return module, sites

    def test_helper_defaults_are_found(self):
        _, sites = self.swift_defaults()
        found = {(path, key) for path, _line, key, _text in sites}
        for expected in (
            ("CLI/CMUXCLI+Config.swift", "config.validation.cli.errorCount"),  # CmuxConfigValidationLocalization().format
            ("CLI/CMUXCLI+DocsSettings.swift", "cli.workflow.guidance.validate"),  # positional workflowText("k", "d")
            ("CLI/cmux.swift", "cli.coderouter.handoff.notAuthenticated"),  # let defaultValue = "..."
            ("Packages/macOS/CmuxSudoBroker/Sources/CmuxSudoBroker/SudoCLIMessages.swift", "sudo.cli.queued"),
            ("Sources/TerminalController+MobileSurfaces.swift", "mobile.chat.artifact.error.permissionDenied"),
        ):
            self.assertIn(expected, found)

    def test_no_cmux_in_swift_localization_defaults(self):
        module, sites = self.swift_defaults()
        hits = [f"{path}:{line}:{key}" for path, line, key, text in sites
                if module.edits(text, key)[0] and key not in module.PRESERVE_KEYS]
        self.assertEqual(hits, [], f"{len(hits)} Swift defaults still say cmux, e.g. {hits[:10]}")

    def test_swift_defaults_match_catalog_english(self):
        module, sites = self.swift_defaults()
        drift = set(json.loads(read("tests/shellx_default_drift.json"))["keys"])
        english = {}
        for path in MACOS_CATALOGS + ["TunnelExtension/InfoPlist.xcstrings"]:
            for key, entry in json.loads(read(path))["strings"].items():
                unit = entry.get("localizations", {}).get("en", {})
                if "stringUnit" in unit:
                    english.setdefault(key, set()).add(unit["stringUnit"]["value"])
        compared, hits = 0, []
        for path, line, key, text in sites:
            if module.INTERPOLATION in text or key not in english:
                continue
            compared += 1
            if text not in english[key] and key not in drift:
                hits.append(f"{path}:{line}:{key}: {text[:60]!r} != {sorted(english[key])[0][:60]!r}")
        self.assertGreater(compared, 9000)
        self.assertEqual(hits, [], f"{len(hits)} Swift defaults differ from the catalog English, e.g. {hits[:5]}")

    def test_rules(self):
        rebrand = load_script().rebrand
        cases = {
            "Quit cmux": "Quit ShellX",
            "CMUX could not load sidebar extensions.": "ShellX could not load sidebar extensions.",
            "Run `cmux notify --title x` or `cmux`.": "Run `shellx notify --title x` or `shellx`.",
            "Edit ~/.config/cmux/cmux.json or .cmux/cmux.json.": "Edit ~/.config/shellx/shellx.json or .shellx/shellx.json.",
            "See https://cmux.com/docs and github.com/manaflow-ai/cmux.": "See https://cmux.com/docs and github.com/manaflow-ai/cmux.",
            "Set $CMUX_SOCKET_PATH or CMUX_PORT for cmux-tui.": "Set $CMUX_SOCKET_PATH or CMUX_PORT for cmux-tui.",
            "Usage: cmux vault <subcommand> [options]": "Usage: shellx vault <subcommand> [options]",
            "Retry 'cmux restore --surface'.": "Retry 'shellx restore --surface'.",
            "The selected cmux browser profile no longer exists.": "The selected ShellX browser profile no longer exists.",
            "Launch OpenCode in a cmux-aware environment.": "Launch OpenCode in a ShellX-aware environment.",
            "Move cmux.app to /Applications.": "Move ShellX.app to /Applications.",
            "cmux: default socket %@ is unavailable": "shellx: default socket %@ is unavailable",
            "[cmux] SSH reconnected.": "[ShellX] SSH reconnected.",
            "Start Kiro with `kiro-cli chat --agent cmux`.": "Start Kiro with `kiro-cli chat --agent cmux`.",
        }
        for source, expected in cases.items():
            self.assertEqual(rebrand(source, key="test"), expected, source)
        self.assertEqual(rebrand("cmux가 종료되었습니다", key="t", en_context="cmux quit"), "ShellX가 종료되었습니다")
        self.assertEqual(rebrand("Das cmux-Browserprofil", key="t", en_context="The cmux browser profile"),
                         "Das ShellX-Browserprofil")
        self.assertEqual(rebrand("Installez cmux-tui", key="t", en_context="Install cmux-tui"), "Installez cmux-tui")
        for preserved in load_script().PRESERVE_VALUES:
            self.assertEqual(rebrand(preserved, key="test"), preserved)

    def test_about_credits_upstream(self):
        about = read("Sources/AboutLicenseContent.swift")
        for name, license in (("cmux (Manaflow, Inc.)", "GPL-3.0-or-later"), ("Ghostty", "MIT"),
                              ("coolicons by Kryston Schwarze", "CC BY 4.0"), ("Space Grotesk", "OFL-1.1")):
            self.assertRegex(about, re.escape(f'name: "{name}"') + r",\s*license: " + re.escape(f'"{license}"'))
        self.assertIn("ShellXBrand.sourceCodeURL", about)
        panel = read("Sources/App/About/AboutPanelView.swift")
        self.assertIn('"ShellXLogo"', panel)
        self.assertIn("AboutLicenseContent.attributions", panel)
        self.assertIn("GPL-3.0-or-later — source: %@", self.en("about.shellx.licenseLine"))


if __name__ == "__main__":
    unittest.main()
