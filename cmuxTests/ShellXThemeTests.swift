import AppKit
import CmuxAppKitSupportUI
import CmuxFoundation
import CmuxTerminalCore
import Foundation
import ShellXBrand
import SwiftUI
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// ShellX visual system (spec §7.4) as the app resolves it: accent, status
/// glyphs, sidebar selection, attention ring, dark-only appearance and the
/// managed terminal default.
@Suite(.serialized)
@MainActor
struct ShellXThemeTests {
    @Test func accentDefaultsToShellXPrimary() {
        let accent = CmuxAccentColor()
        #expect(accent.mode == .cmux)
        #expect(accent.nsColor(isDark: true).hexString() == "#60A5FA")
        #expect(accent.nsColor(isDark: false).hexString() == "#60A5FA")
    }

    @Test func statusGlyphColors() {
        typealias Glyph = SidebarCompactStatusGlyph
        func hex(_ kind: Glyph.Kind) -> String {
            Glyph(kind: kind, tooltip: "")
                .color(isActive: false, selected: .white, secondary: .gray)
                .hexString()
        }
        #expect(hex(.needsInput) == "#60A5FA")
        #expect(hex(.running) == "#E8C468")
        #expect(hex(.subagents) == "#E8C468")
        #expect(hex(.pending) == "#E8C468")
        #expect(hex(.unseen) == "#6FD49A")
        #expect(hex(.error) == "#E88A8A")
        for settled in [Glyph.Kind.idle, .branch, .waiting, .pullRequest(.open), .pullRequest(.merged)] {
            #expect(hex(settled) == "#8A83A6")
        }
        // Rows on a non-ShellX selection still flatten to the selected foreground.
        #expect(Glyph(kind: .running, tooltip: "").color(isActive: true, selected: .white, secondary: .gray) == .white)
    }

    @Test func darkSidebarSelectionIsTheRaiseToken() {
        let selected = sidebarSelectedWorkspaceBackgroundNSColor(
            for: .dark,
            sidebarSelectionColorHex: nil,
            activeTabIndicatorStyle: .leftRail,
            subtleSelection: false
        )
        #expect(selected.hexString() == "#171128")
        #expect(sidebarIsShellXSelectionFill(selected))
        let foreground = sidebarSelectedWorkspaceForegroundNSColor(on: selected, opacity: 1)
        #expect(foreground.hexString() == "#E6E2F2")
        // A configured selection color still wins.
        let configured = sidebarSelectedWorkspaceBackgroundNSColor(
            for: .dark,
            sidebarSelectionColorHex: "#123456"
        )
        #expect(configured.hexString() == "#123456")
        #expect(!sidebarIsShellXSelectionFill(configured))
    }

    @Test func attentionRingIsAFlatOnePixelPrimaryLine() throws {
        let ring = WorkspaceAttentionColor(configuredHex: nil).nsColor
        let dark = try #require(NSAppearance(named: .darkAqua))
        var resolved: NSColor?
        dark.performAsCurrentDrawingAppearance {
            resolved = ring.usingColorSpace(.sRGB)
        }
        let srgb = try #require(resolved)
        #expect(srgb.hexString() == "#60A5FA")
        #expect(abs(srgb.alphaComponent - 0.45) < 0.002)
        #expect(PanelOverlayRingMetrics.lineWidth == 1)
        #expect(WorkspaceAttentionCoordinator.notificationRingStyle.glowOpacity == 0)
        #expect(WorkspaceAttentionCoordinator.notificationRingStyle.glowRadius == 0)
        #expect(WorkspaceAttentionCoordinator.flashRingStyle.glowOpacity == 0)
    }

    @Test func sidebarTintDefaultsToPanel() {
        let defaults = WindowChromeSidebarTintDefaults()
        #expect(defaults.hex == "#100B1D")
        #expect(defaults.opacity == 1.0)
        #expect(WindowChromeSidebarPresetOption.nativeSidebar.tintHex == "#100B1D")
        #expect(WindowChromeSidebarPresetOption.nativeSidebar.tintOpacity == 1.0)
    }

    @Test func appIsDarkOnly() throws {
        #expect(ShellXAppearance.forcedAppearanceName == .darkAqua)
        let suite = "ShellXThemeTests.dark.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(AppearanceMode.light.rawValue, forKey: AppearanceSettings.appearanceModeKey)
        #expect(AppearanceSettings.enforceShellXDarkOnly(defaults: defaults))
        #expect(defaults.string(forKey: AppearanceSettings.appearanceModeKey) == "dark")
        #expect(!AppearanceSettings.enforceShellXDarkOnly(defaults: defaults))
        #expect(AppearanceSettings.terminalColorSchemePreference(defaults: defaults) == .dark)
    }

    @Test func defaultTerminalThemeUsesPalette() throws {
        try withConfig("# no Ghostty settings\n") { path in
            #expect(GhosttyConfig.shouldApplyManagedDefaultAppearance(
                configPaths: [path],
                adaptiveDefaultThemeEnabled: true
            ))
        }
        var config = GhosttyConfig()
        config.parse(GhosttyConfig.cmuxDefaultThemeConfigContents(
            preferredColorScheme: .dark,
            environment: [:],
            bundleResourceURL: nil
        ))
        #expect(config.backgroundColor.hexString() == "#0B0716")
        #expect(config.cursorColor.hexString() == "#60A5FA")
        #expect(config.foregroundColor.hexString() == "#CDC7E0")
        #expect(GhosttyConfig.cmuxDefaultDarkThemeName == "ShellX")
        #expect(GhosttyConfig.cmuxDefaultLightThemeName == "ShellX")
    }

    /// Review Focus 2: a user Ghostty theme or color always wins over the
    /// ShellX default; the default applies only to an untouched config.
    @Test func userGhosttyThemeWins() throws {
        for userConfig in ["background = #ffffff\n", "theme = Catppuccin Mocha\n", "palette = 4=#0000ff\n"] {
            try withConfig(userConfig) { path in
                #expect(!GhosttyConfig.shouldApplyManagedDefaultAppearance(
                    configPaths: [path],
                    adaptiveDefaultThemeEnabled: true
                ), "\(userConfig)")
            }
        }
        var config = GhosttyConfig()
        config.parse("background = #ffffff\n")
        #expect(config.backgroundColor.hexString() == "#FFFFFF")
        // Typography alone keeps the ShellX default.
        try withConfig("font-family = JetBrains Mono\n") { path in
            #expect(GhosttyConfig.shouldApplyManagedDefaultAppearance(
                configPaths: [path],
                adaptiveDefaultThemeEnabled: true
            ))
        }
    }

    private func withConfig(_ contents: String, body: (String) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shellx-theme-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config", isDirectory: false)
        try contents.write(to: file, atomically: true, encoding: .utf8)
        try body(file.path)
    }
}
