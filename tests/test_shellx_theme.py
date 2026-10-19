#!/usr/bin/env python3
"""Guard: ShellX look wiring that Swift unit tests cannot reach (spec §7.4).

- Space Grotesk ships in the app bundle (Resources/Fonts folder reference in
  the app's Resources phase), with its OFL license, and Info.plist registers
  it through ATSApplicationFontsPath.
- The app is dark-only: the Light/Dark/System picker is hidden and live
  appearance applies land on the forced ShellX appearance.
- The sidebar defaults to the opaque panel tint (match terminal background off).
- Buttons, inputs and popovers carry no gradients outside the allowlist (content fades,
  debug-only styles, decorative art).

Usage (from the repo root):
    python3 tests/test_shellx_theme.py
"""
import plistlib
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from shellx_look_guard import offenders, read, sha256  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PBXPROJ = "cmux.xcodeproj/project.pbxproj"
FONT = "Resources/Fonts/SpaceGrotesk[wght].ttf"
# sha256 of google/fonts ofl/spacegrotesk/SpaceGrotesk[wght].ttf at copy time.
FONT_SHA256 = "acad6de1fc93436f5c0f1f4137751ef04f1aea3063e7036535970ffcfbd79f72"
APP_RESOURCES_PHASE = "A5001102 /* Resources */"

# Gradients that stay: content fades/masks, debug-only style variants,
# decorative art and user-authored render trees. Everything else is flat.
GRADIENT_ALLOW = [
    ("Sources/ModeBarLabelEdgeFade.swift", "text overflow fade mask"),
    ("Sources/SidebarScrim.swift", "scroll edge scrim mask"),
    ("Sources/TerminalSizeBoundsOverlayView.swift", "terminal grid edge fade"),
    ("Sources/Feed/FeedPanelView.swift", "DEBUG-only feed button style variants"),
    ("Sources/SleepyFaceView.swift", "decorative idle mascot art"),
    ("Sources/ProBadgeStyle.swift", "logo gradient (logo is the spec's one exception)"),
    ("Sources/Cloud/CloudWelcomeMedia.swift", "cloud welcome artwork (cloud UI hidden in ShellX)"),
    ("Sources/App/ComputerUseCursorOverlayController.swift", "agent cursor overlay art"),
    ("Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Rows/ThemeWindowThumbnail.swift", "wallpaper art in the hidden appearance picker"),
    ("Packages/macOS/CmuxComputerUse/Sources/CmuxComputerUse/AgentCursorPointerView.swift", "agent cursor art"),
    ("Packages/macOS/CmuxSwiftRender/Sources/CmuxSwiftRender/SwiftViewInterpreter.swift", "user-authored view interpreter"),
    ("Packages/macOS/CmuxSwiftRender/Sources/CmuxSwiftRender/RenderNode.swift", "user-authored view model"),
    ("Packages/macOS/CmuxSwiftRenderUI/Sources/CmuxSwiftRenderUI/Rendering/RenderNodeView.swift", "user-authored view renderer"),
    ("Packages/macOS/CmuxSwiftRenderUI/Sources/CmuxSwiftRenderUI/Runtime/SceneNodeView.swift", "user-authored view renderer"),
]
GRADIENT_PATTERN = r"\b(LinearGradient|RadialGradient|AngularGradient|EllipticalGradient|CAGradientLayer|NSGradient)\b"


class ShellXThemeGuardTests(unittest.TestCase):
    def test_space_grotesk_and_license_ship(self):
        self.assertTrue((ROOT / FONT).is_file())
        self.assertEqual(sha256(FONT), FONT_SHA256)
        license_text = read("Resources/Fonts/OFL.txt")
        self.assertIn("SIL OPEN FONT LICENSE Version 1.1", license_text)
        self.assertIn("Space Grotesk Project Authors", license_text)

    def test_info_plist_registers_bundled_fonts(self):
        with open(ROOT / "Resources/Info.plist", "rb") as fh:
            info = plistlib.load(fh)
        self.assertEqual(info.get("ATSApplicationFontsPath"), "Fonts")

    def test_fonts_folder_is_copied_into_app_resources(self):
        project = read(PBXPROJ)
        ref = re.search(
            r"(\w+) /\* Fonts \*/ = \{isa = PBXFileReference; lastKnownFileType = folder; path = Fonts; sourceTree = \"<group>\"; \};",
            project,
        )
        self.assertIsNotNone(ref, "Resources/Fonts folder reference missing")
        build = re.search(
            r"(\w+) /\* Fonts in Resources \*/ = \{isa = PBXBuildFile; fileRef = " + ref.group(1),
            project,
        )
        self.assertIsNotNone(build, "Fonts PBXBuildFile missing")
        phase = project.split(APP_RESOURCES_PHASE + " = {", 1)[1].split("};", 1)[0]
        self.assertIn(f"{build.group(1)} /* Fonts in Resources */", phase)
        # The folder sits in the Resources group (path = Resources).
        group = re.search(r"children = \((?:(?!\);).)*?" + ref.group(1) + r" /\* Fonts \*/.*?\);\s*path = Resources;", project, re.S)
        self.assertIsNotNone(group, "Fonts folder is not in the Resources group")

    def test_display_font_names_the_bundled_family(self):
        source = read("Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXFonts.swift")
        self.assertIn('familyName = "Space Grotesk"', source)

    def test_appearance_picker_is_hidden(self):
        themes = read("Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/ThemesSection.swift")
        self.assertNotIn("ThemePickerRow(", themes)
        self.assertNotIn("setting:themes:appearance", themes)
        curated = read("Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Navigation/CuratedSettingEntry+Default.swift")
        self.assertNotIn('id: "appearance"', curated)
        index = read("Sources/SettingsSearchIndex.swift")
        self.assertNotIn('setting(.themes, "appearance"', index)

    def test_live_appearance_is_forced_dark(self):
        settings = read("Sources/AppearanceSettings.swift")
        self.assertIn("NSApplication.shared.appearance = ShellXAppearance.forcedAppearance", settings)
        self.assertNotIn("NSApplication.shared.appearance = appearance", settings)
        app = read("Sources/cmuxApp.swift")
        self.assertIn("AppearanceSettings.enforceShellXDarkOnly()", app)
        launch = app.index("AppearanceSettings.enforceShellXDarkOnly()")
        self.assertLess(launch, app.index("let startupAppearance = AppearanceSettings.resolvedMode()"))

    def test_sidebar_defaults_to_the_panel_tint(self):
        catalog = read("Packages/macOS/CmuxSettings/Sources/CmuxSettings/Keys/SidebarAppearanceCatalogSection.swift")
        match = re.search(r'id: "sidebarAppearance\.matchTerminalBackground",\s*defaultValue: (\w+)', catalog)
        self.assertIsNotNone(match)
        self.assertEqual(match.group(1), "false")
        tint = read("Packages/macOS/CmuxAppKitSupportUI/Sources/CmuxAppKitSupportUI/WindowChrome/Sidebar/WindowChromeSidebarTintDefaults.swift")
        self.assertIn("public static let matchesTerminalBackground = false", tint)
        self.assertIn("ShellXPalette.panel.hexString.uppercased()", tint)
        self.assertIn("opacity: Double = 1.0", tint)
        schema = read("Packages/macOS/CmuxFoundation/Sources/CmuxFoundation/ConfigValidation/CmuxConfigSchema.generated.swift")
        self.assertRegex(schema, r'"matchTerminalBackground": \{\s*"type": "boolean",\s*"default": false')
        self.assertRegex(schema, r'"tintColor": \{\s*"\$ref": "#/\$defs/colorHex",\s*"default": "#100B1D"')

    def test_omnibar_popover_is_flat(self):
        browser = read("Sources/Panels/BrowserPanelView.swift")
        self.assertNotRegex(browser, GRADIENT_PATTERN)
        self.assertIn(".fill(ShellXPalette.raise.color)", browser)
        self.assertIn(".stroke(ShellXPalette.border.color, lineWidth: 1)", browser)

    def test_no_gradients_on_buttons_or_rows(self):
        hits = offenders(GRADIENT_PATTERN, ["Sources", "Packages/macOS"], GRADIENT_ALLOW)
        hits = [h for h in hits if "/.build/" not in h and "/Tests/" not in h]
        self.assertEqual(hits, [], "new gradient outside the allowlist; use a flat ShellXPalette token")


if __name__ == "__main__":
    unittest.main()
