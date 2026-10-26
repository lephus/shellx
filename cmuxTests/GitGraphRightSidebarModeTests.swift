import Foundation
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class GitGraphRightSidebarModeTests: XCTestCase {
    func testGitModeParsesCliAliasesAndOpensAsPane() {
        for alias in ["git", "git-graph", "graph", " GIT "] {
            XCTAssertEqual(RightSidebarMode.from(cliArgument: alias), .git)
        }
        XCTAssertTrue(RightSidebarMode.git.canOpenAsPane)
        XCTAssertTrue(RightSidebarMode.git.isAvailable(feedEnabled: false, machinesEnabled: false))
    }

    func testGitTabIsAppendedSoExistingDigitShortcutsDoNotMove() {
        let defaults = UserDefaults(suiteName: "GitGraphRightSidebarModeTests.\(UUID())")!
        let order = RightSidebarTabPreferences.orderedModes(defaults: defaults)
        XCTAssertEqual(order.last, .git)
        XCTAssertEqual(RightSidebarMode.positionalDigit(for: .files, defaults: defaults), 1)
        XCTAssertEqual(RightSidebarMode.positionalDigit(for: .find, defaults: defaults), 2)
        XCTAssertEqual(RightSidebarMode.positionalDigit(for: .sessions, defaults: defaults), 3)
        if let gitDigit = RightSidebarMode.positionalDigit(for: .git, defaults: defaults) {
            XCTAssertGreaterThan(gitDigit, 3)
        }
    }

    func testPaletteOffersShowAndOpenAsTabForGit() {
        let ids = ContentView.commandPaletteRightSidebarModeCommandContributions().map(\.commandId)
        XCTAssertTrue(ids.contains(ContentView.commandPaletteRightSidebarModeCommandID(.git)))
        XCTAssertTrue(
            ContentView.commandPaletteRightSidebarToolPaneCommandDescriptors()
                .contains { $0.mode == .git && $0.commandId == "palette.openGitGraphPane" }
        )
    }

    func testGitModeDoesNotSyncFileExplorerRoot() {
        XCTAssertFalse(FileExplorerRootSyncPolicy.shouldSyncFileExplorerStore(isRightSidebarVisible: true, mode: .git))
    }
}
