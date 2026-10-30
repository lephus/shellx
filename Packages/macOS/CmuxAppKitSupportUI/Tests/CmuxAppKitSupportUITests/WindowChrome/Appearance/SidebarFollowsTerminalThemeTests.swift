import AppKit
import CmuxFoundation
import CmuxWorkspaces
import SwiftUI
import Testing

@testable import CmuxAppKitSupportUI

/// A sidebar left on the default `panel` tint follows the terminal theme: it
/// draws a color one small step off the terminal background, so picking a
/// theme recolors it while the sidebar still reads as its own surface.
@Suite struct SidebarFollowsTerminalThemeTests {
    @Test func shellXThemeKeepsThePanelColor() throws {
        let snapshot = snapshot(terminalHex: "#0B0716")

        #expect(try leftSidebarTintHex(snapshot) == "#100B1DFF")
        #expect(snapshot.sidebarContentColorScheme == .dark)
    }

    /// The ShellX theme is recognized by its own background, not by the
    /// color a translucent terminal composites to.
    @Test func translucentShellXThemeKeepsThePanelColor() throws {
        let snapshot = snapshot(terminalHex: "#0B0716", terminalOpacity: 0.8)

        #expect(try leftSidebarTintHex(snapshot) == "#100B1DFF")
    }

    @Test func darkThemeDrawsTheSidebarSlightlyLighterThanTheTerminal() throws {
        let terminal = try #require(NSColor(hex: "#282A36"))
        let snapshot = snapshot(terminalHex: "#282A36")
        let tint = try leftSidebarTint(snapshot)
        let resolver = WindowChromeColorResolver()

        #expect(tint.hexString() != WindowChromeSidebarTintDefaults.shellXPanelHex)
        #expect(resolver.readableColorScheme(for: tint) == .dark)
        #expect(relativeLuminance(tint) > relativeLuminance(terminal))
        #expect(resolver.contrastRatio(tint, terminal) < 1.15)
        #expect(snapshot.sidebarContentColorScheme == .dark)
    }

    @Test func lightThemeDrawsTheSidebarSlightlyDarkerWithDarkText() throws {
        let terminal = try #require(NSColor(hex: "#FDF6E3"))
        // ShellX is dark-only, so the ambient scheme is dark.
        let snapshot = snapshot(terminalHex: "#FDF6E3", ambientScheme: .dark)
        let tint = try leftSidebarTint(snapshot)
        let resolver = WindowChromeColorResolver()

        #expect(resolver.readableColorScheme(for: tint) == .light)
        #expect(relativeLuminance(tint) < relativeLuminance(terminal))
        #expect(resolver.contrastRatio(tint, terminal) < 1.15)
        #expect(snapshot.sidebarContentColorScheme == .light)
        #expect(snapshot.sidebarSettings.colorScheme == .light)
    }

    @Test func rightSidebarFollowsTheSameTheme() throws {
        let snapshot = snapshot(terminalHex: "#282A36")
        guard case let .sidebarMaterial(right) = snapshot.policy(for: .rightSidebar) else {
            Issue.record("Expected a right sidebar material policy")
            return
        }
        #expect(right.tintColor.hexString(includeAlpha: true) == (try leftSidebarTintHex(snapshot)))
    }

    /// The default hex may be stored in either case (cmux.json, older builds).
    @Test func lowercaseDefaultHexStillFollowsTheTheme() throws {
        let snapshot = snapshot(terminalHex: "#282A36", tintHex: "#100b1d")

        #expect(try leftSidebarTintHex(snapshot) != "#100B1DFF")
    }

    /// Any tint the user chose wins over the theme.
    @Test(arguments: [
        TintChoice(hex: "#FF0000", light: nil, dark: nil, opacity: 1),
        TintChoice(hex: WindowChromeSidebarTintDefaults.shellXPanelHex, light: nil, dark: "#00FF00", opacity: 1),
        TintChoice(hex: WindowChromeSidebarTintDefaults.shellXPanelHex, light: "#0000FF", dark: nil, opacity: 1),
        TintChoice(hex: WindowChromeSidebarTintDefaults.shellXPanelHex, light: nil, dark: nil, opacity: 0.6),
    ])
    func chosenTintIsKept(_ choice: TintChoice) throws {
        let snapshot = snapshot(
            terminalHex: "#282A36",
            tintHex: choice.hex,
            tintHexLight: choice.light,
            tintHexDark: choice.dark,
            tintOpacity: choice.opacity
        )
        let expected = try #require(NSColor(hex: choice.dark ?? choice.hex))
            .withAlphaComponent(choice.opacity)
            .hexString(includeAlpha: true)

        #expect(try leftSidebarTintHex(snapshot) == expected)
        #expect(snapshot.sidebarContentColorScheme == .dark)
    }

    /// Matching the terminal background shares the terminal backdrop as
    /// before; there is no separate tint to derive.
    @Test func matchingTheTerminalBackgroundStillClearsTheSidebar() {
        let snapshot = snapshot(terminalHex: "#282A36", unifySurfaceBackdrops: true)

        guard case .clear = snapshot.policy(for: .leftSidebar) else {
            Issue.record("A matched sidebar shares the terminal backdrop")
            return
        }
    }

    struct TintChoice: Sendable, CustomTestStringConvertible {
        let hex: String
        let light: String?
        let dark: String?
        let opacity: Double

        var testDescription: String {
            "\(hex) light:\(light ?? "-") dark:\(dark ?? "-") opacity:\(opacity)"
        }
    }

    private func snapshot(
        terminalHex: String,
        terminalOpacity: Double = 1,
        ambientScheme: ColorScheme = .dark,
        unifySurfaceBackdrops: Bool = false,
        tintHex: String = WindowChromeSidebarTintDefaults.shellXPanelHex,
        tintHexLight: String? = nil,
        tintHexDark: String? = nil,
        tintOpacity: Double = WindowChromeSidebarTintDefaults().opacity
    ) -> WindowAppearanceSnapshot {
        let resolver = WindowAppearanceResolver(
            terminalAppearance: WindowTerminalAppearanceSnapshot(
                backgroundColor: NSColor(hex: terminalHex) ?? .black,
                backgroundOpacity: terminalOpacity,
                backgroundBlur: .disabled,
                usesHostLayerBackground: true
            )
        )
        return resolver.current(settings: WindowAppearanceUserSettingsSnapshot(
            unifySurfaceBackdrops: unifySurfaceBackdrops,
            colorScheme: ambientScheme,
            sidebarMaterial: WindowChromeSidebarMaterialOption.sidebar.rawValue,
            sidebarBlendMode: WindowChromeSidebarBlendModeOption.withinWindow.rawValue,
            sidebarState: WindowChromeSidebarStateOption.followWindow.rawValue,
            sidebarTintHex: tintHex,
            sidebarTintHexLight: tintHexLight,
            sidebarTintHexDark: tintHexDark,
            sidebarTintOpacity: tintOpacity,
            sidebarCornerRadius: 0,
            sidebarBlurOpacity: 1,
            bgGlassEnabled: false,
            bgGlassTintHex: "#000000",
            bgGlassTintOpacity: 0.03
        ))
    }

    private func leftSidebarTint(_ snapshot: WindowAppearanceSnapshot) throws -> NSColor {
        guard case let .sidebarMaterial(policy) = snapshot.policy(for: .leftSidebar) else {
            Issue.record("Expected a left sidebar material policy")
            throw SnapshotError.noSidebarMaterial
        }
        return policy.tintColor
    }

    private func leftSidebarTintHex(_ snapshot: WindowAppearanceSnapshot) throws -> String {
        try leftSidebarTint(snapshot).hexString(includeAlpha: true)
    }

    private func relativeLuminance(_ color: NSColor) -> CGFloat {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        func linear(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(srgb.redComponent)
            + 0.7152 * linear(srgb.greenComponent)
            + 0.0722 * linear(srgb.blueComponent)
    }

    private enum SnapshotError: Error {
        case noSidebarMaterial
    }
}
