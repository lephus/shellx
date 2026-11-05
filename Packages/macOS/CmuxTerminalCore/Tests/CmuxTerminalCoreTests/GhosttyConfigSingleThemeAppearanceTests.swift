import AppKit
import CoreText
import Foundation
import Testing
@testable import CmuxTerminalCore

private struct ConfigFileReader: GhosttyConfigFileReading {
    var contentsByPath: [String: String] = [:]

    func fileSize(atPath path: String) -> Int? {
        contentsByPath[path]?.lengthOfBytes(using: .utf8)
    }

    func contents(atPath path: String) -> String? {
        contentsByPath[path]
    }
}

private struct NoFonts: GhosttyFontProbing {
    func discoveredFont(named _: String, size _: CGFloat, weightTrait _: CGFloat?) -> CTFont? { nil }
    func configuredFont(named _: String, size _: CGFloat) -> CTFont? { nil }
}

/// A config naming one theme for both appearances (a plain `theme = X`, or the
/// `light:X,dark:X` older galleries wrote) only fits one of them. The other
/// appearance shows ShellX's default for it instead, without writing the
/// config: a dark theme gets Catppuccin Latte in Light, a light theme gets
/// ShellX in Dark.
@Suite struct GhosttyConfigSingleThemeAppearanceTests {
    /// The repo's bundled Ghostty resources (real `themes/` files).
    private static let resourcesDirectory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/ghostty", isDirectory: true)

    private static let environment = ["GHOSTTY_RESOURCES_DIR": resourcesDirectory.path]

    private func override(_ themeLine: String, _ scheme: GhosttyConfig.ColorSchemePreference) -> String? {
        // The appearance summary reads config files from disk.
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-single-theme-\(UUID().uuidString).ghostty").path
        try? themeLine.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let reader = ConfigFileReader(contentsByPath: [path: themeLine])
        let discovery = GhosttyConfigDiscovery(fileReader: reader, fontProbe: NoFonts())
        return discovery.conditionalThemeOverrideConfigContents(
            preferredColorScheme: scheme,
            configPaths: [path],
            environment: Self.environment,
            bundleResourceURL: nil
        )
    }

    @Test func darkThemeOnBothSidesShowsTheDefaultLightThemeInLight() {
        #expect(override("theme = light:Abernathy,dark:Abernathy", .light) == "theme = Catppuccin Latte")
        #expect(override("theme = light:Abernathy,dark:Abernathy", .dark) == "theme = Abernathy")
    }

    @Test func plainDarkThemeShowsTheDefaultLightThemeInLight() {
        #expect(override("theme = Abernathy", .light) == "theme = Catppuccin Latte")
        #expect(override("theme = Abernathy", .dark) == nil)
    }

    @Test func lightThemeOnBothSidesShowsShellXInDark() {
        #expect(override("theme = light:Rose Pine Dawn,dark:Rose Pine Dawn", .dark) == "theme = ShellX")
        #expect(override("theme = light:Rose Pine Dawn,dark:Rose Pine Dawn", .light) == "theme = Rose Pine Dawn")
    }

    @Test func aRealPairIsUntouched() {
        #expect(override("theme = light:Rose Pine Dawn,dark:Abernathy", .light) == "theme = Rose Pine Dawn")
        #expect(override("theme = light:Rose Pine Dawn,dark:Abernathy", .dark) == "theme = Abernathy")
    }

    /// The Swift config (the chrome's colors) follows the same rule.
    @Test func loadedThemeColorsFollowTheRule() {
        var light = GhosttyConfig()
        light.loadTheme(
            "light:Abernathy,dark:Abernathy",
            environment: Self.environment,
            bundleResourceURL: nil,
            preferredColorScheme: .light
        )
        // Catppuccin Latte's background.
        #expect(light.backgroundColor.hexString().lowercased() == "#eff1f5")

        var dark = GhosttyConfig()
        dark.loadTheme(
            "light:Abernathy,dark:Abernathy",
            environment: Self.environment,
            bundleResourceURL: nil,
            preferredColorScheme: .dark
        )
        #expect(dark.backgroundColor.hexString().lowercased() == "#111416")
    }
}
