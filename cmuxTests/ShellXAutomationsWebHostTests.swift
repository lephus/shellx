import Foundation
import ShellXAutomations
import WebKit
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Switching away from the Automations tab and back must keep the page, so a draft
/// being written in the creator is still there.
@MainActor
final class ShellXAutomationsWebHostTests: XCTestCase {
    private var fixture: ShellXAutomationsFixture!

    override func setUp() async throws {
        fixture = ShellXAutomationsFixture()
    }

    override func tearDown() async throws {
        fixture.remove()
        fixture = nil
    }

    func testTabSwitchKeepsTheSamePage() throws {
        let panel = ShellXAutomationsPanel(controller: makeController())
        let first = panel.webHost.attachWebView()
        let tabView = NSView()
        tabView.addSubview(first)

        // Leaving the tab: SwiftUI dismantles the hosting view.
        ShellXAutomationsWebView.dismantleNSView(first, coordinator: ())
        first.removeFromSuperview()
        let again = panel.webHost.attachWebView()

        XCTAssertTrue(again === first, "the page and its creator chat must survive a tab switch")
        XCTAssertNotNil(panel.controller.emit, "events sent while the tab is hidden must still reach the page")
        panel.close()
    }

    func testAttachingWhileStillInTheOldTreeMovesThePage() {
        let panel = ShellXAutomationsPanel(controller: makeController())
        let first = panel.webHost.attachWebView()
        let oldTree = NSView()
        oldTree.addSubview(first)

        let again = panel.webHost.attachWebView()

        XCTAssertTrue(again === first)
        XCTAssertNil(again.superview, "a view can only have one parent, so the new tree gets it detached")
        panel.close()
    }

    func testClosingThePanelReleasesThePage() {
        let panel = ShellXAutomationsPanel(controller: makeController())
        let first = panel.webHost.attachWebView()

        panel.close()

        XCTAssertNil(panel.controller.emit)
        XCTAssertFalse(panel.webHost.attachWebView() === first)
    }

    private func makeController() -> ShellXAutomationsController {
        let store = fixture.store
        let launcher = ShellXAutomationsFakeCreatorLauncher(log: fixture.log)
        return ShellXAutomationsController(
            library: fixture.library,
            store: store,
            scheduler: fixture.scheduler,
            creatorFactory: { _ in
                ShellXCreatorSession(
                    launcher: launcher,
                    systemPrompt: "Prompt",
                    workingDirectory: URL(filePath: "/tmp"),
                    localeIdentifier: "en_US",
                    cliPath: "/cli"
                )
            },
            runLauncher: { _ in nil },
            terminalOpener: { _ in },
            fileOpener: { _ in },
            makeValidator: { _ in
                ShellXAutomationValidator(existingNames: [], directoryExists: { _ in true }, claudeAvailable: true)
            },
            flowDrawer: { _ in throw ShellXFlowDrawError.invalidFlow }
        )
    }
}
