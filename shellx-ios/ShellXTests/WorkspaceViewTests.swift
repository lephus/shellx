import ShellXAppCore
import ShellXAppTestSupport
import XCTest
@testable import ShellX

/// The workspace screen's controls as `WorkspaceView` wires them to the signed-in scope, against a fake
/// Mac: each reaches the hub call it stands for and does with the answer what `WorkspaceFeedback` says
/// (no UI automation is available, so this is the executed coverage of the screen's wiring).
@MainActor
final class WorkspaceViewTests: XCTestCase {
    private func makeRig() async throws -> WorkspaceRig {
        try await WorkspaceRig.make(in: self)
    }

    private func eventually(_ condition: () async -> Bool) async -> Bool {
        await WorkspaceRig.eventually(condition)
    }

    func testSelectingAChipShowsIt() async throws {
        let rig = try await makeRig()
        XCTAssertEqual(rig.model.selectedTerminalId, "t-zsh", "the Mac's selection")

        rig.actions.select("t-claude")

        XCTAssertEqual(rig.model.selectedTerminalId, "t-claude")
        XCTAssertTrue(rig.screen.tasks.isEmpty, "swiping asks the Mac for nothing")
    }

    func testRenameReachesTheMacAndTheNameArrivesByPush() async throws {
        let rig = try await makeRig()

        rig.actions.rename("Docs")
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .nothing)
        let calls = await rig.mac.workspaceCalls
        XCTAssertEqual(calls, ["rename:ws-shellx:Docs"])
        let retitled = await eventually { rig.model.workspace?.title == "Docs" }
        XCTAssertTrue(retitled)
        XCTAssertTrue(rig.screen.alerts.isEmpty)
    }

    func testCloseReachesTheMacAndTheScreenLeavesByPush() async throws {
        let rig = try await makeRig()
        let run = Task { await rig.model.run() }
        addTeardownBlock { run.cancel() }

        rig.actions.close()
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .nothing)
        XCTAssertEqual(rig.screen.closings, 1, "the screen is told the user closed it")
        let calls = await rig.mac.workspaceCalls
        XCTAssertEqual(calls, ["close:ws-shellx"])
        let gone = await eventually { rig.model.phase == .dismissed }
        XCTAssertTrue(gone, "\(rig.model.phase)")
    }

    func testARefusedCloseIsAnAlertAndTheWorkspaceStays() async throws {
        let rig = try await makeRig()
        await rig.mac.setNextWorkspaceOutcome(.refused)

        rig.actions.close()
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .alert(.refusedClose))
        XCTAssertEqual(rig.screen.alerts, [.refusedClose])
        XCTAssertEqual(rig.model.phase, .showing)
    }

    func testAWorkspaceTheMacDoesNotHaveRefreshesTheList() async throws {
        let rig = try await makeRig()
        await rig.mac.setNextWorkspaceOutcome(.notFound)
        let before = await rig.mac.workspaceListCount

        rig.actions.rename("x")
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .refresh)
        let after = await rig.mac.workspaceListCount
        XCTAssertEqual(after, before + 1, "the list was asked for again, with no word to the user")
        XCTAssertTrue(rig.screen.alerts.isEmpty)
    }

    func testCommandsToAMacThatIsAwayAreAnAlert() async throws {
        let rig = try await makeRig()
        await rig.hub.stopAll()

        rig.actions.rename("x")
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .alert(.offline))
        XCTAssertEqual(rig.screen.alerts, [.offline])
    }
}
