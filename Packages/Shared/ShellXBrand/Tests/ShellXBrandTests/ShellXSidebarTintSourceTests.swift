import Testing
@testable import ShellXBrand

/// The user picks where the left sidebar's color comes from: the terminal
/// theme or their own tint. Before that choice existed, the sidebar followed
/// the theme only while its tint was untouched, so a tint changed back then
/// stays the user's own.
@Suite struct ShellXSidebarTintSourceTests {
    @Test func themeFollowsTheTerminalThemeWhateverTheStoredTint() {
        #expect(ShellXSidebarTintSource.theme.followsTerminalTheme(
            tintHex: "#FF0000", tintHexLight: "#00FF00", tintHexDark: "#0000FF", tintOpacity: 0.4
        ))
    }

    /// Picking the user's own color keeps it even when it is the default `panel`.
    @Test func customKeepsTheStoredTintEvenAtTheDefault() {
        #expect(!ShellXSidebarTintSource.custom.followsTerminalTheme(
            tintHex: ShellXPalette.panel.hexString, tintHexLight: nil, tintHexDark: nil, tintOpacity: 1
        ))
    }

    @Test(arguments: ["#100B1D", "#100b1d"])
    func automaticFollowsTheThemeWhileTheTintIsUntouched(hex: String) {
        #expect(ShellXSidebarTintSource.automatic.followsTerminalTheme(
            tintHex: hex, tintHexLight: nil, tintHexDark: nil, tintOpacity: 1
        ))
    }

    @Test(arguments: [
        TintChoice(hex: "#FF0000", light: nil, dark: nil, opacity: 1),
        TintChoice(hex: "#100B1D", light: "#FFFFFF", dark: nil, opacity: 1),
        TintChoice(hex: "#100B1D", light: nil, dark: "#000000", opacity: 1),
        TintChoice(hex: "#100B1D", light: nil, dark: nil, opacity: 0.6),
    ])
    func automaticKeepsATintChangedBeforeTheChoiceExisted(_ choice: TintChoice) {
        #expect(!ShellXSidebarTintSource.automatic.followsTerminalTheme(
            tintHex: choice.hex, tintHexLight: choice.light, tintHexDark: choice.dark, tintOpacity: choice.opacity
        ))
    }

    /// The raw values are what `UserDefaults` stores under `sidebarTintSource`.
    @Test func rawValuesAreStable() {
        #expect(ShellXSidebarTintSource.allCases.map(\.rawValue) == ["automatic", "theme", "custom"])
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
}
