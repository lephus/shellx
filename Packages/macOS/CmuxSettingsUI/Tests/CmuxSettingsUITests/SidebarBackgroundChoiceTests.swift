import CmuxSettings
import Testing
@testable import CmuxSettingsUI

/// Settings → Sidebar offers one choice for the sidebar background: follow
/// the terminal theme, match the terminal, or a color of the user's own.
@Suite struct SidebarBackgroundChoiceTests {
    private let panel = SettingCatalog().sidebarAppearance.tintColorHex.defaultValue

    @Test func untouchedInstallsFollowTheTheme() {
        #expect(choice(source: .automatic, tintHex: panel) == .theme)
    }

    /// A tint changed before the choice existed shows as the user's own color.
    @Test func anEarlierTintShowsAsCustom() {
        #expect(choice(source: .automatic, tintHex: "#FF0000") == .custom)
        #expect(choice(source: .automatic, tintHex: panel, tintHexDark: "#00FF00") == .custom)
        #expect(choice(source: .automatic, tintHex: panel, tintOpacity: 0.6) == .custom)
    }

    @Test func thePickedSourceShowsWhateverTheTint() {
        #expect(choice(source: .theme, tintHex: "#FF0000") == .theme)
        #expect(choice(source: .custom, tintHex: panel) == .custom)
    }

    @Test func matchingTheTerminalWinsOverTheSource() {
        #expect(choice(matchesTerminal: true, source: .custom, tintHex: "#FF0000") == .terminal)
    }

    /// Each choice writes the values that draw it; matching the terminal
    /// leaves the source alone, so turning it off restores the earlier pick.
    @Test func eachChoiceWritesTheValuesThatDrawIt() {
        #expect(SidebarBackgroundChoice.theme.matchesTerminal == false)
        #expect(SidebarBackgroundChoice.theme.tintSource == .theme)
        #expect(SidebarBackgroundChoice.custom.matchesTerminal == false)
        #expect(SidebarBackgroundChoice.custom.tintSource == .custom)
        #expect(SidebarBackgroundChoice.terminal.matchesTerminal == true)
        #expect(SidebarBackgroundChoice.terminal.tintSource == nil)
    }

    private func choice(
        matchesTerminal: Bool = false,
        source: SidebarTintSourceOption,
        tintHex: String,
        tintHexDark: String = "",
        tintOpacity: Double = 1
    ) -> SidebarBackgroundChoice {
        SidebarBackgroundChoice(
            matchesTerminal: matchesTerminal,
            source: source,
            tintHex: tintHex,
            tintHexLight: "",
            tintHexDark: tintHexDark,
            tintOpacity: tintOpacity
        )
    }
}
