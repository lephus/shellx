import ShellXAppCore
import ShellXAppTestSupport
import SwiftUI
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

    // MARK: - Closing an agent

    private func agentRef(_ rig: WorkspaceRig) -> SessionRef {
        SessionRef(machineID: rig.mac.machine.machineID, sessionId: "s1", agent: "claude", workspaceTitle: "shellx-ios")
    }

    func testTheMenuListsCloseAgentOnlyWhenItCan() {
        XCTAssertEqual(WorkspaceMenuItem.items(canCloseAgent: true), [.rename, .closeAgent, .closeWorkspace])
        XCTAssertEqual(WorkspaceMenuItem.items(canCloseAgent: false), [.rename, .closeWorkspace])
    }

    func testCloseAgentIsOfferedForTheLiveAgentShownAndReachesTheMac() async throws {
        let rig = try await makeRig()
        XCTAssertNil(WorkspaceView.closableAgent(rig.model, hub: rig.hub), "the shell shown runs no agent")

        rig.actions.select("t-claude")
        let pane = try XCTUnwrap(WorkspaceView.closableAgent(rig.model, hub: rig.hub))
        XCTAssertEqual(pane.id, "t-claude")
        let session = try XCTUnwrap(pane.session)
        XCTAssertTrue(WorkspaceListActions.canClose(session, hub: rig.hub), "its own screen offers it too")

        rig.actions.closeAgent(session.ref)
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .nothing)
        let calls = await rig.mac.agentCloses
        XCTAssertEqual(calls, ["s1"])
        XCTAssertTrue(rig.screen.alerts.isEmpty)
        XCTAssertEqual(rig.screen.closings, 0, "closing an agent is not closing the workspace")
        // Ended: the terminal now runs the user's shell, which Close never offers to shut.
        let ended = await eventually { WorkspaceView.closableAgent(rig.model, hub: rig.hub) == nil }
        XCTAssertTrue(ended)
        let endedSession = try XCTUnwrap(rig.model.panes.first { $0.id == "t-claude" }?.session)
        XCTAssertFalse(WorkspaceListActions.canClose(endedSession, hub: rig.hub))
    }

    func testAMacWithoutAgentCloseOffersNoClose() async throws {
        let rig = try await WorkspaceRig.make(acceptsAgentClose: false, in: self)

        rig.actions.select("t-claude")

        XCTAssertNil(WorkspaceView.closableAgent(rig.model, hub: rig.hub))
        let session = try XCTUnwrap(rig.model.panes.first { $0.id == "t-claude" }?.session)
        XCTAssertFalse(WorkspaceListActions.canClose(session, hub: rig.hub), "nor does the agent's own screen")
    }

    func testCloseAgentFromTheMenuWhileTheListsCloseWaitsSendsNothing() async throws {
        let rig = try await makeRig()
        // The home's swipe on the same agent, through the same signed-in scope.
        let listScreen = WorkspaceRig.Screen()
        let list = WorkspaceListActions.make(
            scope: rig.scope, open: { _ in }, alert: { listScreen.alerts.append($0) }, creating: .constant(false),
            done: { listScreen.tasks.append($0) })
        await rig.mac.holdWorkspaceControl()

        list.closeAgent(agentRef(rig))
        rig.actions.closeAgent(agentRef(rig))

        XCTAssertEqual(listScreen.tasks.count, 1)
        XCTAssertTrue(rig.screen.tasks.isEmpty, "the menu's close waits for the swipe's")
        let held = await eventually { await rig.mac.agentCloses == ["s1"] }
        XCTAssertTrue(held)
        await rig.mac.releaseWorkspaceControl()
        _ = await listScreen.tasks.last?.value
        let calls = await rig.mac.agentCloses
        XCTAssertEqual(calls, ["s1"])
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
