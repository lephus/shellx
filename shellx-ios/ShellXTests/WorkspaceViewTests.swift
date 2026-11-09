import ShellXAppCore
import ShellXAppTestSupport
import ShellXLinkCore
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

    // MARK: - Closing a tab

    private func terminalCloses(_ rig: WorkspaceRig) async -> [String] {
        await rig.mac.terminalCloses.map { "\($0.workspaceId)/\($0.terminalId)" }
    }

    /// Follows the hub as the screen does while it is shown.
    private func follow(_ rig: WorkspaceRig) {
        let run = Task { await rig.model.run() }
        addTeardownBlock { run.cancel() }
    }

    func testTheMenuListsCloseTabOnlyWhenItCan() {
        XCTAssertEqual(WorkspaceMenuItem.items(canCloseTab: true), [.rename, .closeTab, .closeWorkspace])
        XCTAssertEqual(WorkspaceMenuItem.items(canCloseTab: false), [.rename, .closeWorkspace])
    }

    func testCloseTabClosesTheShellShownAndTheNextChipShowsWithoutAWord() async throws {
        let rig = try await makeRig()
        follow(rig)
        XCTAssertTrue(WorkspaceListActions.canCloseTab(machineID: rig.model.ref.machineID, hub: rig.hub))
        XCTAssertEqual(rig.model.selectedTerminalId, "t-zsh", "a shell: any tab closes, not only an agent's")

        rig.actions.closeTab("t-zsh")
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .nothing, "the tab leaves by the Mac's push")
        let calls = await terminalCloses(rig)
        XCTAssertEqual(calls, ["ws-shellx/t-zsh"])
        let moved = await eventually { rig.model.panes.map(\.id) == ["t-claude"] }
        XCTAssertTrue(moved)
        XCTAssertEqual(rig.model.selectedTerminalId, "t-claude", "the chip left, the only one there")
        XCTAssertEqual(rig.model.shownPaneClosed, 0, "closed from this iPhone: no 'closed on the Mac'")
        XCTAssertEqual(rig.model.phase, .showing)
        XCTAssertTrue(rig.screen.alerts.isEmpty)
        XCTAssertEqual(rig.screen.closings, 0, "closing a tab is not closing the workspace")
    }

    func testClosingTheLastTabLeavesWithoutSayingTheMacClosedIt() async throws {
        let rig = try await makeRig()
        follow(rig)
        rig.actions.select("t-claude")

        // A long-press on the shell's chip, which is not the one shown: the agent stays on screen.
        rig.actions.closeTab("t-zsh")
        _ = await rig.lastFeedback()
        let shellGone = await eventually { rig.model.panes.map(\.id) == ["t-claude"] }
        XCTAssertTrue(shellGone)
        XCTAssertEqual(rig.model.selectedTerminalId, "t-claude")

        // The agent's tab, now the workspace's last: the Mac closes the workspace with it.
        rig.actions.closeTab("t-claude")
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .nothing)
        let calls = await terminalCloses(rig)
        XCTAssertEqual(calls, ["ws-shellx/t-zsh", "ws-shellx/t-claude"])
        let agentCloses = await rig.mac.agentCloses
        XCTAssertEqual(agentCloses, [], "an agent's tab closes as a tab: the Mac checks for no live agent")
        let gone = await eventually { rig.model.phase == .dismissed }
        XCTAssertTrue(gone, "\(rig.model.phase)")
        XCTAssertTrue(rig.model.lastTabClosedHere, "the screen leaves without 'Workspace closed on the Mac'")
        XCTAssertEqual(rig.model.shownPaneClosed, 0)
        XCTAssertTrue(rig.screen.alerts.isEmpty)
    }

    func testARefusedCloseTabIsAnAlertAndTheTabStays() async throws {
        let rig = try await makeRig()
        follow(rig)
        await rig.mac.setNextTerminalCloseOutcome(.refused)

        rig.actions.closeTab("t-zsh")
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .alert(.refusedCloseTab))
        XCTAssertEqual(rig.screen.alerts, [.refusedCloseTab])
        XCTAssertEqual(rig.model.panes.map(\.id), ["t-claude", "t-zsh"])
        XCTAssertEqual(rig.model.selectedTerminalId, "t-zsh")

        // Closed later on the Mac itself: that one the screen does explain.
        await rig.mac.upsertWorkspace(
            LinkWorkspace(
                workspaceId: "ws-shellx", title: "shellx-ios", order: 0, directory: "~/shellx/shellx-ios",
                branch: "feat/workspaces",
                terminals: [LinkTerminal(terminalId: "t-claude", title: "claude", order: 0, selected: true, sessionId: "s1")]))
        let moved = await eventually { rig.model.selectedTerminalId == "t-claude" }
        XCTAssertTrue(moved)
        XCTAssertEqual(rig.model.shownPaneClosed, 1)
    }

    func testCloseTabWhileTheSameTabsCloseWaitsSendsNothing() async throws {
        let rig = try await makeRig()
        await rig.mac.holdWorkspaceControl()

        // The menu's Close Tab… and a long-press on the same chip, both confirmed.
        rig.actions.closeTab("t-zsh")
        rig.actions.closeTab("t-zsh")

        XCTAssertEqual(rig.screen.tasks.count, 1, "the second close waits for the first")
        let held = await eventually { await self.terminalCloses(rig) == ["ws-shellx/t-zsh"] }
        XCTAssertTrue(held)
        await rig.mac.releaseWorkspaceControl()
        _ = await rig.lastFeedback()
        let calls = await terminalCloses(rig)
        XCTAssertEqual(calls, ["ws-shellx/t-zsh"])
    }

    func testAMacWithoutTerminalCloseOffersNoCloseTab() async throws {
        let rig = try await WorkspaceRig.make(acceptsTerminalClose: false, in: self)

        XCTAssertFalse(WorkspaceListActions.canCloseTab(machineID: rig.model.ref.machineID, hub: rig.hub))
    }

    func testCommandsToAMacThatIsAwayAreAnAlert() async throws {
        let rig = try await makeRig()
        await rig.hub.stopAll()

        rig.actions.rename("x")
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .alert(.offline))
        XCTAssertEqual(rig.screen.alerts, [.offline])
    }

    // MARK: - Terminals

    func testNewTerminalReachesTheMacAndItsChipShows() async throws {
        let rig = try await makeRig()
        follow(rig)
        XCTAssertTrue(rig.hub.supportsTerminalCreate(rig.model.ref.machineID))

        rig.actions.createTerminal()
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .nothing)
        let creates = await rig.mac.terminalCreates
        XCTAssertEqual(creates, ["ws-shellx"])
        let shown = await eventually { rig.model.selectedTerminalId?.hasPrefix("ws-shellx-new-") == true }
        XCTAssertTrue(shown, "\(String(describing: rig.model.selectedTerminalId))")
        XCTAssertTrue(rig.screen.alerts.isEmpty)
    }

    func testARefusedNewTerminalIsAnAlert() async throws {
        let rig = try await makeRig()
        follow(rig)
        await rig.mac.setNextTerminalCreateOutcome(.refused)

        rig.actions.createTerminal()
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .alert(.refusedControl))
        XCTAssertEqual(rig.screen.alerts, [.refusedControl])
        XCTAssertEqual(rig.model.selectedTerminalId, "t-zsh")
    }

    func testViewAsTerminalSwitchesTheAgentChipsPage() async throws {
        let rig = try await makeRig()
        follow(rig)

        rig.actions.select("t-claude")
        XCTAssertNil(rig.model.terminalShown, "an agent chip shows its chat")
        rig.actions.showAsTerminal("t-claude", true)
        XCTAssertEqual(rig.model.terminalShown, "t-claude")
        rig.actions.showAsTerminal("t-claude", false)
        XCTAssertNil(rig.model.terminalShown)
        XCTAssertTrue(rig.screen.tasks.isEmpty, "switching the page asks the Mac for nothing")
    }

    func testANewTerminalsAnswers() {
        let m = "m1"
        XCTAssertEqual(WorkspaceFeedback.of(.ok(workspaceId: nil), for: .createTerminal, machineID: m), .nothing)
        XCTAssertEqual(WorkspaceFeedback.of(.ok(workspaceId: "ws"), for: .createTerminal, machineID: m), .nothing)
        XCTAssertEqual(WorkspaceFeedback.of(.notFound, for: .createTerminal, machineID: m), .refresh)
        XCTAssertEqual(WorkspaceFeedback.of(.refused, for: .createTerminal, machineID: m), .alert(.refusedControl))
        XCTAssertEqual(WorkspaceFeedback.of(.failed, for: .createTerminal, machineID: m), .alert(.failed))
        XCTAssertEqual(WorkspaceFeedback.of(.offline, for: .createTerminal, machineID: m), .alert(.offline))
        XCTAssertEqual(WorkspaceFeedback.of(.unknown, for: .createTerminal, machineID: m), .alert(.unknown))
    }

    /// ＋ again while a new terminal is on its way does nothing, and a chip the user picks before the Mac answers stays
    /// shown when the new tab arrives (final review, app M6).
    func testAPickWhileANewTerminalIsOnItsWayWins() async throws {
        let rig = try await makeRig()
        follow(rig)

        rig.actions.createTerminal()
        rig.actions.createTerminal()
        rig.actions.select("t-claude")
        for task in rig.screen.tasks { _ = await task.value }

        let creates = await rig.mac.terminalCreates
        XCTAssertEqual(creates, ["ws-shellx"], "one create while one is on its way")
        let listed = await eventually { rig.model.panes.contains { $0.id.hasPrefix("ws-shellx-new-") } }
        XCTAssertTrue(listed)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(rig.model.selectedTerminalId, "t-claude", "the user's pick wins over the new tab")
    }

    /// ＋ is dimmed from the tap until the Mac answers (final review, app M6).
    func testPlusIsDimmedWhileANewTerminalIsOnItsWay() async throws {
        let rig = try await makeRig()
        follow(rig)

        rig.actions.createTerminal()
        XCTAssertTrue(rig.model.creatingTerminal)
        _ = await rig.lastFeedback()

        XCTAssertFalse(rig.model.creatingTerminal)
        rig.actions.createTerminal()
        _ = await rig.lastFeedback()
        let creates = await rig.mac.terminalCreates
        XCTAssertEqual(creates, ["ws-shellx", "ws-shellx"], "once answered, ＋ works again")
    }
}
