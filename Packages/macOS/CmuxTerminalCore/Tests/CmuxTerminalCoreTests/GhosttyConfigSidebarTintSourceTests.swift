import Foundation
import ShellXBrand
import Testing
@testable import CmuxTerminalCore

/// A `sidebar-background` in the Ghostty config is the user's own sidebar
/// color, so it keeps applying after Settings › Sidebar was set to follow
/// the terminal theme.
@Suite(.serialized) struct GhosttyConfigSidebarTintSourceTests {
    private let keys = ["sidebarTintHex", "sidebarTintHexLight", "sidebarTintHexDark", "sidebarTintSource"]

    @Test func sidebarBackgroundMakesTheTintTheUsersOwn() {
        withPreservedDefaults {
            let defaults = UserDefaults.standard
            defaults.set(ShellXSidebarTintSource.theme.rawValue, forKey: "sidebarTintSource")

            var config = GhosttyConfig()
            config.rawSidebarBackground = "#336699"
            config.resolveSidebarBackground(preferredColorScheme: .dark)
            config.applySidebarAppearanceToUserDefaults()

            #expect(defaults.string(forKey: "sidebarTintHex") == "#336699")
            #expect(defaults.string(forKey: "sidebarTintSource") == ShellXSidebarTintSource.custom.rawValue)
        }
    }

    @Test func noSidebarBackgroundLeavesTheChoiceAlone() {
        withPreservedDefaults {
            let defaults = UserDefaults.standard
            defaults.set(ShellXSidebarTintSource.theme.rawValue, forKey: "sidebarTintSource")

            GhosttyConfig().applySidebarAppearanceToUserDefaults()

            #expect(defaults.string(forKey: "sidebarTintSource") == ShellXSidebarTintSource.theme.rawValue)
        }
    }

    private func withPreservedDefaults(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let originals = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, original) in zip(keys, originals) {
                if let original {
                    defaults.set(original, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        body()
    }
}
