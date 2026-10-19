#!/usr/bin/env python3
"""Guard: the ShellX title bar (spec 7.1, Task 11).

- ShellXTitlebarModel is pure, public and lives in the ShellXBrand package.
- The accessory uses coolicons through ShellXIcon, ShellXPalette flat colors
  (no gradients/shadows), and reaches the existing actions (command palette,
  settings window).
- The update/titlebar controller installs it and the bell badge draws the model.
- It is registered in the Xcode project; strings have en and vi catalog entries.

Usage (from the repo root):
    python3 tests/test_shellx_titlebar.py
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from shellx_look_guard import read  # noqa: E402

MODEL = "Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXTitlebarModel.swift"
VIEW = "Sources/ShellX/Titlebar/ShellXTitlebarAccessory.swift"
CONTROLLER = "Sources/Update/UpdateTitlebarAccessory.swift"
PBXPROJ = "cmux.xcodeproj/project.pbxproj"
CATALOG = "Resources/Localizable.xcstrings"


class ShellXTitlebarTests(unittest.TestCase):
    def test_model_is_pure_and_public(self) -> None:
        src = read(MODEL)
        self.assertIn("public struct ShellXTitlebarModel: Equatable", src)
        self.assertIn("public var badgeText: String?", src)
        self.assertIn('"Search sessions, machines, commands…"', src)
        self.assertNotRegex(src, r"import (AppKit|SwiftUI|Foundation)")
        self.assertNotIn("String(localized", src)

    def test_view_uses_shellx_look(self) -> None:
        src = read(VIEW)
        # SF names the icon map turns into Search_Magnifying_Glass / Settings.
        icon_map = json.loads(read("Packages/Shared/ShellXBrand/Sources/ShellXIcons/Resources/icon-map.json"))
        for sf, coolicon in (("magnifyingglass", "Search_Magnifying_Glass"), ("gearshape", "Settings")):
            self.assertEqual(icon_map[sf], coolicon)
            self.assertIn(f'ShellXIcon.image("{sf}")', src)
        self.assertIn("ShellXPalette", src)
        self.assertNotRegex(src, r"Gradient|\.shadow\(|Image\(systemName:")
        self.assertNotRegex(src, r"Color\(\.sRGB|Color\(red:|NSColor\(red:")

    def test_view_wires_existing_actions(self) -> None:
        src = read(VIEW)
        self.assertIn("requestCommandPaletteCommands", src)
        self.assertIn("openPreferencesWindow", src)
        self.assertIn("layoutAttribute = .right", src)

    def test_view_strings_are_localized_with_en_and_vi(self) -> None:
        src = read(VIEW)
        catalog = json.loads(read(CATALOG))["strings"]
        keys = re.findall(r'String\(localized: "([^"]+)"', src)
        self.assertEqual(sorted(keys), ["titlebar.search.placeholder", "titlebar.settings.accessibilityLabel"])
        for key in keys:
            locs = catalog[key]["localizations"]
            self.assertIn("en", locs)
            self.assertIn("vi", locs)
        loc = catalog["titlebar.search.placeholder"]["localizations"]
        self.assertEqual(loc["vi"]["stringUnit"]["value"], "Tìm phiên, máy, lệnh…")
        self.assertEqual(catalog["titlebar.settings.accessibilityLabel"]["localizations"]["vi"]["stringUnit"]["value"], "Cài đặt")

    def test_controller_installs_accessory_and_badge_uses_model(self) -> None:
        src = read(CONTROLLER)
        self.assertIn("ShellXTitlebarAccessoryViewController()", src)
        self.assertGreaterEqual(src.count("ShellXTitlebarAccessoryViewController.identifier"), 3)
        self.assertIn("ShellXTitlebarModel(unreadCount: unreadModel.totalUnreadCount).badgeText", src)
        self.assertIn("ShellXPalette.primary.color", src)

    def test_registered_in_project(self) -> None:
        proj = read(PBXPROJ)
        self.assertIn("path = ShellX/Titlebar/ShellXTitlebarAccessory.swift", proj)
        self.assertIn("ShellXTitlebarAccessory.swift in Sources", proj)
        self.assertIn("ShellXTitlebarModelTests.swift in Sources", proj)


if __name__ == "__main__":
    unittest.main()
