import CmuxCommandPalette
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// ShellX: accounts are a Manaflow service (Stack Auth, cmux.com), so the
/// palette offers no Sign In, Sign Out or team command in any auth state.
/// The team picker keeps its shortcut mapping for the code that still exists.
@MainActor
struct CommandPaletteAuthCommandTests {
    @Test(arguments: [false, true], [false, true])
    func noAccountCommandInAnyAuthState(signedIn: Bool, working: Bool) {
        var context = CommandPaletteContextSnapshot()
        context.setBool(CommandPaletteContextKeys.authSignedIn, signedIn)
        context.setBool(CommandPaletteContextKeys.authWorking, working)
        #expect(visibleAuthCommandIDs(context).isEmpty)
        #expect(ContentView.commandPaletteAuthCommandContributions().isEmpty)
    }

    @Test func teamPickerCommandStillMapsToItsShortcut() {
        #expect(
            ContentView.commandPaletteShortcutAction(forCommandID: ContentView.commandPaletteAuthTeamPickerCommandId)
                == .openTeamPicker
        )
    }

    private func visibleAuthCommandIDs(_ context: CommandPaletteContextSnapshot) -> [String] {
        ContentView.commandPaletteAuthCommandContributions()
            .filter { $0.when(context) }
            .map(\.commandId)
    }
}
