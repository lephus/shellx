import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// The workspace screen's model: which chip shows first, what happens when the workspace or the
/// chip being viewed leaves the Mac's list, and the wait for a workspace the Mac has not listed yet.
@MainActor
final class WorkspaceScreenModelTests: XCTestCase {
    private func ref(_ mac: FakeMac, _ workspace: String = "shellx") -> WorkspaceRef {
        WorkspaceRef(machineID: mac.machine.machineID, workspaceId: "ws-\(workspace)")
    }

    /// Whether the hub's list for `mac` has the workspace `ws-<name>`.
    private func listed(_ name: String, by hub: MachineHub, of mac: FakeMac) -> Bool {
        hub.workspaceRows(machineID: mac.machine.machineID).contains { $0.id.workspaceId == "ws-\(name)" }
    }

    private func terminals(_ ids: String..., agent: [String: String] = [:], selected: String? = nil) -> [LinkTerminal] {
        ids.enumerated().map { index, id in
            LinkTerminal(terminalId: id, title: id, order: index, selected: id == selected, sessionId: agent[id])
        }
    }

    private func pending(workspace: String = "shellx", machine: String = "m1") -> MachinePendingItem {
        MachinePendingItem(
            machineID: machine, machineName: "Mac", item: pendingItem("r1", workspace: workspace), actionable: true)
    }

    /// A model over a hub that is online with `mac`'s workspaces in; `patience` is the model's own wait.
    private func makeModel(
        _ mac: FakeMac, workspace: String = "shellx", sleeper: ManualSleeper = ManualSleeper(), sessions: Int = 0
    ) async throws -> (model: WorkspaceScreenModel, hub: MachineHub, run: Task<Void, Never>) {
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: sessions)
        XCTAssertTrue(online)
        let listed = await eventually { rig.hub.machines.first?.workspacesSupported == true }
        XCTAssertTrue(listed)
        let model = WorkspaceScreenModel(ref: ref(mac, workspace), hub: rig.hub, sleep: sleeper.sleep)
        let run = Task { await model.run() }
        addTeardownBlock { run.cancel() }
        return (model, rig.hub, run)
    }

    // MARK: - The chip shown first

    func testDefaultTerminalPrefersPending() {
        let workspace = linkWorkspace(
            terminals: terminals("shell", "claude", "dev", agent: ["claude": "s1"], selected: "shell"))

        XCTAssertEqual(
            WorkspaceScreenModel.defaultTerminal(in: workspace, pending: [pending()]), "claude",
            "a request waits on the agent: its chip, whatever the Mac has selected")
        XCTAssertEqual(
            WorkspaceScreenModel.defaultTerminal(in: workspace, pending: []), "shell",
            "nothing waits: the chip the Mac has selected")
        XCTAssertEqual(
            WorkspaceScreenModel.defaultTerminal(in: workspace, pending: [pending(workspace: "other")]), "shell",
            "a request of another workspace does not count")
    }

    func testDefaultTerminalFallsBackToTheFirstChip() {
        // Chips go by `order`, not by the order they came in.
        let unsorted = linkWorkspace(terminals: [
            LinkTerminal(terminalId: "b", title: "b", order: 1, selected: false),
            LinkTerminal(terminalId: "a", title: "a", order: 0, selected: false),
        ])
        XCTAssertEqual(WorkspaceScreenModel.defaultTerminal(in: unsorted, pending: []), "a")
        XCTAssertNil(WorkspaceScreenModel.defaultTerminal(in: linkWorkspace(terminals: []), pending: []))

        // A request waits but no chip runs an agent: the Mac's selection decides.
        let shells = linkWorkspace(terminals: terminals("one", "two", selected: "two"))
        XCTAssertEqual(WorkspaceScreenModel.defaultTerminal(in: shells, pending: [pending()]), "two")
    }

    func testDefaultTerminalSkipsAnAgentTheHubNoLongerLists() {
        let workspace = linkWorkspace(
            terminals: terminals("gone", "live", "shell", agent: ["gone": "s-gone", "live": "s-live"], selected: "shell"))

        XCTAssertEqual(
            WorkspaceScreenModel.defaultTerminal(in: workspace, pending: [pending()], sessions: [agentSession("s-live")]),
            "live")
        XCTAssertEqual(
            WorkspaceScreenModel.defaultTerminal(in: workspace, pending: [pending()], sessions: []), "shell",
            "no chip is an agent any more")
    }

    func testAnAgentThatNeedsInputComesFirstThenTheAskingAgentThenTheMacsSelection() {
        let workspace = linkWorkspace(
            terminals: terminals(
                "shell", "c1", "c2", "x1", agent: ["c1": "s-c1", "c2": "s-c2", "x1": "s-x1"], selected: "shell"))
        func session(_ id: String, _ state: AgentState, agent: String = "claude") -> AgentSession {
            var session = agentSession(id, state: state)
            session.agent = agent
            return session
        }

        XCTAssertEqual(
            WorkspaceScreenModel.defaultTerminal(
                in: workspace, pending: [pending()],
                sessions: [session("s-c1", .working), session("s-c2", .needsInput), session("s-x1", .working)]),
            "c2", "the one agent that needs input")
        XCTAssertEqual(
            WorkspaceScreenModel.defaultTerminal(
                in: workspace, pending: [],
                sessions: [session("s-c1", .working), session("s-c2", .needsInput)]),
            "c2", "it waits for the user even before its request is listed")
        XCTAssertEqual(
            WorkspaceScreenModel.defaultTerminal(
                in: workspace, pending: [pending()],
                sessions: [
                    session("s-c1", .working), session("s-c2", .needsInput),
                    session("s-x1", .needsInput, agent: "codex"),
                ]),
            "c2", "several need input: the one whose agent asks (the request is Claude's)")
        XCTAssertEqual(
            WorkspaceScreenModel.defaultTerminal(
                in: workspace, pending: [pending()],
                sessions: [session("s-c1", .needsInput), session("s-c2", .needsInput)]),
            "c1", "the same agent asks in both: the first, the Mac selecting neither")
        let macSelectsC2 = linkWorkspace(
            terminals: terminals("c1", "c2", agent: ["c1": "s-c1", "c2": "s-c2"], selected: "c2"))
        XCTAssertEqual(
            WorkspaceScreenModel.defaultTerminal(
                in: macSelectsC2, pending: [pending()],
                sessions: [session("s-c1", .needsInput), session("s-c2", .needsInput)]),
            "c2", "then the one the Mac has selected")
        XCTAssertEqual(
            WorkspaceScreenModel.defaultTerminal(
                in: workspace, pending: [], sessions: [session("s-c1", .working), session("s-c2", .idle)]),
            "shell", "nothing waits: the Mac's selection")
    }

    func testPendingChoosesTheAgentThatIsSelectedWhenThereAreSeveral() {
        let workspace = linkWorkspace(
            terminals: terminals("a1", "a2", agent: ["a1": "s1", "a2": "s2"], selected: "a2"))

        XCTAssertEqual(WorkspaceScreenModel.defaultTerminal(in: workspace, pending: [pending()]), "a2")
    }

    // MARK: - Panes

    func testAChipWhoseSessionTheHubDoesNotListIsAShellChip() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([
            linkWorkspace(terminals: terminals("t1", "t2", "t3", agent: ["t1": "s-live", "t2": "s-gone"]))
        ])
        await mac.upsertSession(agentSession("s-live"))
        let (model, _, _) = try await makeModel(mac, sessions: 1)

        XCTAssertEqual(model.panes.map(\.id), ["t1", "t2", "t3"])
        XCTAssertEqual(model.panes.map(\.isAgent), [true, false, false])
        XCTAssertEqual(model.panes.first?.session?.session.sessionId, "s-live")
        XCTAssertEqual(model.panes.first?.session?.machineName, "MacBook Pro")
    }

    func testPanesGoByOrder() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([
            linkWorkspace(terminals: [
                LinkTerminal(terminalId: "late", title: "late", order: 2, selected: false),
                LinkTerminal(terminalId: "first", title: "first", order: 0, selected: false),
                LinkTerminal(terminalId: "mid", title: "mid", order: 1, selected: true),
            ])
        ])
        let (model, _, _) = try await makeModel(mac)

        XCTAssertEqual(model.panes.map(\.id), ["first", "mid", "late"])
        XCTAssertEqual(model.selectedTerminalId, "mid", "the Mac's selection shows first")
    }

    func testTheModelStartsOnTheDefaultChipBeforeItRuns() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace(terminals: terminals("t1", "t2", agent: ["t2": "s1"], selected: "t1"))])
        await mac.upsertSession(agentSession("s1", state: .needsInput))
        await mac.addPending(pendingItem("r1"))
        let rig = try await HubRig.make([mac], in: self)
        _ = await rig.online(sessions: 1)
        _ = await eventually { rig.hub.pendingItems.count == 1 && rig.hub.machines.first?.workspacesSupported == true }

        let model = WorkspaceScreenModel(ref: ref(mac), hub: rig.hub, sleep: ManualSleeper().sleep)

        XCTAssertEqual(model.phase, .showing, "the first frame already has a workspace")
        XCTAssertEqual(model.selectedTerminalId, "t2", "the agent that waits for the user")
    }

    /// Spec section 6.2: the screen opens on the pane waiting for the user. With two Claude agents, the one
    /// whose session needs input, not the one the Mac has selected.
    func testTheAgentThatNeedsInputIsTheDefaultOverTheMacsSelection() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([
            linkWorkspace(terminals: terminals("a1", "a2", agent: ["a1": "s1", "a2": "s2"], selected: "a1"))
        ])
        await mac.upsertSession(agentSession("s1", state: .working))
        await mac.upsertSession(agentSession("s2", state: .needsInput))
        await mac.addPending(pendingItem("r1"))
        let rig = try await HubRig.make([mac], in: self)
        _ = await rig.online(sessions: 2)
        _ = await eventually { rig.hub.pendingItems.count == 1 && rig.hub.machines.first?.workspacesSupported == true }

        let model = WorkspaceScreenModel(ref: ref(mac), hub: rig.hub, sleep: ManualSleeper().sleep)

        XCTAssertEqual(model.selectedTerminalId, "a2", "the agent that asks, not the Mac's selection")
    }

    /// The list can come before the sessions and the request it names: until the user picks a chip, the
    /// chip shown follows what the screen learns.
    func testTheDefaultChipIsChosenAgainWhenTheSessionsArriveAfterTheList() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([
            linkWorkspace(terminals: terminals("zsh", "claude", agent: ["claude": "s1"], selected: "zsh"))
        ])
        let (model, hub, _) = try await makeModel(mac)
        XCTAssertEqual(model.selectedTerminalId, "zsh", "no session listed yet: the Mac's selection")

        await mac.upsertSession(agentSession("s1", state: .needsInput))
        await mac.addPending(pendingItem("r1"))
        let moved = await eventually { model.selectedTerminalId == "claude" }
        XCTAssertTrue(moved, "\(String(describing: model.selectedTerminalId))")

        // Once the user picked a chip, what arrives later does not move it.
        model.select("zsh")
        await mac.upsertSession(agentSession("s1", state: .working))
        await mac.upsertSession(agentSession("s1", state: .needsInput))
        await mac.addPending(pendingItem("r2"))
        let seen = await eventually { hub.pendingItems.count == 2 }
        XCTAssertTrue(seen)
        XCTAssertEqual(model.selectedTerminalId, "zsh")
    }

    // MARK: - Swiping and a chip that goes

    func testSelectingAChipSticksWhileTheMacChangesItsOwnSelection() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace(terminals: terminals("t1", "t2", "t3", selected: "t1"))])
        let (model, _, _) = try await makeModel(mac)
        XCTAssertEqual(model.selectedTerminalId, "t1")

        model.select("t2")
        model.select("nope")
        XCTAssertEqual(model.selectedTerminalId, "t2", "an id the workspace does not have is ignored")

        await mac.upsertWorkspace(linkWorkspace(terminals: terminals("t1", "t2", "t3", selected: "t3")))
        // A later change that the model has surely seen: the extra chip.
        await mac.upsertWorkspace(linkWorkspace(terminals: terminals("t1", "t2", "t3", "t4", selected: "t3")))
        let seen = await eventually { model.panes.count == 4 }
        XCTAssertTrue(seen)
        XCTAssertEqual(model.selectedTerminalId, "t2", "the phone's chip does not follow the Mac's")
    }

    func testTheChipBeingViewedGoingAwayMovesOnToTheNextOne() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace(terminals: terminals("t1", "t2", "t3", "t4"))])
        let (model, _, _) = try await makeModel(mac)

        model.select("t2")
        await mac.upsertWorkspace(linkWorkspace(terminals: terminals("t1", "t3", "t4")))
        let next = await eventually { model.selectedTerminalId == "t3" }
        XCTAssertTrue(next, "the chip after it: \(String(describing: model.selectedTerminalId))")

        model.select("t4")
        await mac.upsertWorkspace(linkWorkspace(terminals: terminals("t1", "t3")))
        let last = await eventually { model.selectedTerminalId == "t3" }
        XCTAssertTrue(last, "the last chip went: the one before it, \(String(describing: model.selectedTerminalId))")
        XCTAssertEqual(model.phase, .showing)
        XCTAssertEqual(model.shownPaneClosed, 2, "each time, the screen says the pane was closed on the Mac")
    }

    func testAChipThatIsNotBeingViewedGoingAwayChangesNothing() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace(terminals: terminals("t1", "t2", "t3"))])
        let (model, _, _) = try await makeModel(mac)
        model.select("t1")

        await mac.upsertWorkspace(linkWorkspace(terminals: terminals("t1", "t3")))
        let gone = await eventually { model.panes.map(\.id) == ["t1", "t3"] }

        XCTAssertTrue(gone)
        XCTAssertEqual(model.selectedTerminalId, "t1")
        XCTAssertEqual(model.shownPaneClosed, 0, "the pane shown is still there: nothing to say")
    }

    func testTheLastChipGoingAwayLeavesNoSelection() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace(terminals: terminals("t1"))])
        let (model, _, _) = try await makeModel(mac)

        await mac.upsertWorkspace(linkWorkspace(terminals: []))
        let empty = await eventually { model.panes.isEmpty }

        XCTAssertTrue(empty)
        XCTAssertNil(model.selectedTerminalId)
        XCTAssertEqual(model.phase, .showing, "a workspace with no terminal is still a workspace")

        await mac.upsertWorkspace(linkWorkspace(terminals: terminals("t9")))
        let back = await eventually { model.selectedTerminalId == "t9" }
        XCTAssertTrue(back, "a chip came: it shows")
    }

    func testATabClosedFromThisIPhoneGoesWithoutAWord() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace(terminals: terminals("t1", "t2", "t3"))])
        let (model, _, _) = try await makeModel(mac)
        model.select("t2")

        model.closesHere("t2")
        await mac.upsertWorkspace(linkWorkspace(terminals: terminals("t1", "t3")))
        let next = await eventually { model.selectedTerminalId == "t3" }
        XCTAssertTrue(next, "the next chip shows: \(String(describing: model.selectedTerminalId))")
        XCTAssertEqual(model.shownPaneClosed, 0, "the user closed it here: nothing to explain")

        // A close the Mac did not carry out: when the tab goes later, the Mac closed it.
        model.closesHere("t3")
        model.keeps("t3")
        await mac.upsertWorkspace(linkWorkspace(terminals: terminals("t1")))
        let moved = await eventually { model.selectedTerminalId == "t1" }
        XCTAssertTrue(moved)
        XCTAssertEqual(model.shownPaneClosed, 1, "closed on the Mac: the screen says so")
        XCTAssertEqual(model.phase, .showing)
        XCTAssertFalse(model.lastTabClosedHere)
    }

    func testTheWorkspaceGoingWithTheLastTabClosedHereIsNotClosedOnTheMac() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([
            linkWorkspace(terminals: terminals("t1", "t2")), linkWorkspace("web", order: 1, terminals: terminals("w1")),
        ])
        let (model, _, _) = try await makeModel(mac)

        model.closesHere("t1")
        await mac.upsertWorkspace(linkWorkspace(terminals: terminals("t2")))
        let one = await eventually { model.panes.map(\.id) == ["t2"] }
        XCTAssertTrue(one)
        model.closesHere("t2")
        // The Mac may list the workspace with no tab for a moment before it goes.
        await mac.upsertWorkspace(linkWorkspace(terminals: []))
        let empty = await eventually { model.panes.isEmpty }
        XCTAssertTrue(empty)
        await mac.removeWorkspace("ws-shellx")
        let dismissed = await eventually { model.phase == .dismissed }

        XCTAssertTrue(dismissed, "\(model.phase)")
        XCTAssertTrue(model.lastTabClosedHere, "the screen leaves without 'Workspace closed on the Mac'")
        XCTAssertEqual(model.shownPaneClosed, 0)
    }

    func testTheWorkspaceGoingWithATabNotClosedHereIsClosedOnTheMac() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([
            linkWorkspace(terminals: terminals("t1", "t2")), linkWorkspace("web", order: 1, terminals: terminals("w1")),
        ])
        let (model, _, _) = try await makeModel(mac)

        // Only one of its two tabs was closed here when the Mac closed the whole workspace.
        model.closesHere("t1")
        await mac.removeWorkspace("ws-shellx")
        let dismissed = await eventually { model.phase == .dismissed }

        XCTAssertTrue(dismissed, "\(model.phase)")
        XCTAssertFalse(model.lastTabClosedHere)
    }

    // MARK: - The workspace leaves, or has not come

    func testClosedWorkspaceDismisses() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace("shellx"), linkWorkspace("web", order: 1)])
        let (model, _, _) = try await makeModel(mac)
        XCTAssertEqual(model.phase, .showing)

        await mac.removeWorkspace("ws-web")
        // The other workspace leaving is not this one's business.
        let other = await eventually { model.workspace != nil }
        XCTAssertTrue(other)
        XCTAssertEqual(model.phase, .showing)

        await mac.removeWorkspace("ws-shellx")
        let dismissed = await eventually { model.phase == .dismissed }
        XCTAssertTrue(dismissed, "\(model.phase)")
        XCTAssertFalse(model.lastTabClosedHere, "closed on the Mac: the list says so")
    }

    func testDismissedStaysDismissedWhenTheWorkspaceListsAgain() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace("shellx"), linkWorkspace("web", order: 1)])
        let (model, hub, _) = try await makeModel(mac)

        await mac.removeWorkspace("ws-shellx")
        _ = await eventually { model.phase == .dismissed }
        await mac.upsertWorkspace(linkWorkspace("shellx"))
        await mac.upsertWorkspace(linkWorkspace("docs", order: 5))
        let relisted = await eventually { listed("docs", by: hub, of: mac) }
        XCTAssertTrue(relisted)

        XCTAssertEqual(model.phase, .dismissed, "the screen is already on its way out")
    }

    func testUnseenWorkspaceWaits() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace("shellx")])
        let sleeper = ManualSleeper()
        let (model, hub, _) = try await makeModel(mac, workspace: "new", sleeper: sleeper)

        // `workspace.create.result` came before the push that lists the workspace: wait, do not leave.
        XCTAssertEqual(model.phase, .waiting)
        XCTAssertNil(model.workspace)
        let timer = await eventually { sleeper.waiting == [.seconds(5)] }
        XCTAssertTrue(timer, "\(sleeper.requested)")
        var lists = await mac.workspaceListCount
        XCTAssertEqual(lists, 1)

        // Other changes, even a removal, say nothing about a workspace never seen.
        await mac.upsertWorkspace(linkWorkspace("web", order: 1))
        await mac.removeWorkspace("ws-web")
        let removed = await eventually { !listed("web", by: hub, of: mac) }
        XCTAssertTrue(removed)
        XCTAssertEqual(model.phase, .waiting)

        // The push arrives within the wait: the screen shows, and the wait ends without asking again.
        await mac.upsertWorkspace(linkWorkspace("new", order: 2, terminals: terminals("t1")))
        let showing = await eventually { model.phase == .showing }
        XCTAssertTrue(showing)
        XCTAssertEqual(model.selectedTerminalId, "t1")
        sleeper.release()
        _ = await eventually(timeout: .milliseconds(200)) { false }
        lists = await mac.workspaceListCount
        XCTAssertEqual(lists, 1, "it arrived: no refresh was needed")
        XCTAssertEqual(model.phase, .showing)
    }

    func testUnseenWorkspaceAsksTheMacOnceThenGivesUp() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace("shellx")])
        let sleeper = ManualSleeper()
        let (model, _, _) = try await makeModel(mac, workspace: "ghost", sleeper: sleeper)
        XCTAssertEqual(model.phase, .waiting)
        let timer = await eventually { sleeper.waiting == [.seconds(5)] }
        XCTAssertTrue(timer)

        sleeper.release()

        let gaveUp = await eventually { model.phase == .notFound }
        XCTAssertTrue(gaveUp, "\(model.phase)")
        let lists = await mac.workspaceListCount
        XCTAssertEqual(lists, 2, "the list was asked for once more, not again and again")
        XCTAssertEqual(sleeper.requested, [.seconds(5)])

        // A late push still shows the workspace.
        await mac.upsertWorkspace(linkWorkspace("ghost", order: 3, terminals: terminals("t1")))
        let late = await eventually { model.phase == .showing }
        XCTAssertTrue(late)
    }

    func testTheRefreshCanFindTheWorkspaceItself() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace("shellx")])
        let sleeper = ManualSleeper()
        let (model, _, _) = try await makeModel(mac, workspace: "missed", sleeper: sleeper)
        let timer = await eventually { sleeper.waiting == [.seconds(5)] }
        XCTAssertTrue(timer)

        // The push was lost: the Mac's list moved on without telling the phone.
        await mac.skipNextWorkspaceRevision()
        await mac.upsertWorkspace(linkWorkspace("missed", order: 1, terminals: terminals("t1")))
        sleeper.release()

        let found = await eventually { model.phase == .showing }
        XCTAssertTrue(found, "\(model.phase)")
    }

    func testWorkspaceOfAnUnknownMacNeverDismissesFromNothing() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace("shellx")])
        let rig = try await HubRig.make([mac], in: self)
        _ = await rig.online(sessions: 0)
        let sleeper = ManualSleeper()
        let model = WorkspaceScreenModel(
            ref: WorkspaceRef(machineID: "mac-nobody", workspaceId: "ws-shellx"), hub: rig.hub, sleep: sleeper.sleep)
        let run = Task { await model.run() }
        addTeardownBlock { run.cancel() }

        XCTAssertEqual(model.phase, .waiting)
        XCTAssertTrue(model.panes.isEmpty)
    }

    // MARK: - The Mac goes away

    func testTheLastKnownChipsStayWhileTheMacIsOffline() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace(terminals: terminals("t1", "t2", agent: ["t1": "s1"]))])
        await mac.upsertSession(agentSession("s1"))
        let backoff = ManualSleeper()
        let rig = try await HubRig.make([mac], in: self)
        _ = await rig.online(sessions: 1)
        _ = await eventually { rig.hub.machines.first?.workspacesSupported == true }
        let model = WorkspaceScreenModel(ref: ref(mac), hub: rig.hub, sleep: backoff.sleep)
        let run = Task { await model.run() }
        addTeardownBlock { run.cancel() }
        model.select("t2")

        await mac.dropLiveSessions()
        let down = await eventually { rig.hub.machines.first?.state != .online }
        XCTAssertTrue(down)

        XCTAssertEqual(model.phase, .showing)
        XCTAssertEqual(model.panes.map(\.id), ["t1", "t2"])
        XCTAssertEqual(model.panes.map(\.isAgent), [true, false], "the agent pane stays; its screen says the Mac is away")
        XCTAssertEqual(model.selectedTerminalId, "t2")
    }

    /// The relay no longer grants the Mac (`MachineHub.revoke`): the hub empties the Mac's list, but nothing was
    /// closed on the Mac. The screen keeps its last chips; it does not leave saying the workspace was closed.
    func testTheChipsStayWhenTheRelayNoLongerGrantsTheMac() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace(terminals: terminals("t1", "t2"))])
        let (model, hub, _) = try await makeModel(mac)
        XCTAssertEqual(model.phase, .showing)

        // The rig's relay grants nothing: the Mac is revoked.
        await hub.refreshGrants()
        let revoked = await eventually { hub.machines.first?.state == .revoked }
        XCTAssertTrue(revoked)
        XCTAssertTrue(hub.workspaceRows(machineID: mac.machine.machineID).isEmpty, "the hub forgot the list")
        // Whatever the model would do with that, it has had the time to.
        _ = await eventually(timeout: .milliseconds(200)) { false }

        XCTAssertEqual(model.phase, .showing, "nothing was closed on the Mac")
        XCTAssertEqual(model.panes.map(\.id), ["t1", "t2"], "the last chips stay")
    }

    /// The Mac removed this iPhone (the connection stops for good, `revoked`): the same, through the
    /// connection's own stop.
    func testTheChipsStayWhenTheMacRemovesThisIPhone() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace(terminals: terminals("t1", "t2"))])
        let rig = try await HubRig.make([mac], in: self)
        _ = await rig.online(sessions: 0)
        _ = await eventually { rig.hub.machines.first?.workspacesSupported == true }
        let model = WorkspaceScreenModel(ref: ref(mac), hub: rig.hub, sleep: ManualSleeper().sleep)
        let run = Task { await model.run() }
        addTeardownBlock { run.cancel() }
        XCTAssertEqual(model.phase, .showing)

        await mac.failNextConnects(RelayAPIError.http(status: 403, code: "not_granted"), count: 5)
        await mac.dropLiveSessions()
        let retrying = await eventually { rig.backoff.waiting.count == 1 }
        XCTAssertTrue(retrying)
        rig.backoff.release()
        let revoked = await eventually { rig.hub.machines.first?.state == .revoked }
        XCTAssertTrue(revoked)
        let emptied = await eventually { rig.hub.workspaceRows(machineID: mac.machine.machineID).isEmpty }
        XCTAssertTrue(emptied)
        _ = await eventually(timeout: .milliseconds(200)) { false }

        XCTAssertEqual(model.phase, .showing, "nothing was closed on the Mac")
        XCTAssertEqual(model.panes.map(\.id), ["t1", "t2"], "the last chips stay")
    }

    /// Back online, the Mac's list no longer fits a frame (`too_large`): the hub has no list to give, but the
    /// Mac closed nothing. The chips stay.
    func testTheChipsStayWhenTheListCannotBeReadOnReconnect() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace(terminals: terminals("t1", "t2"))])
        let rig = try await HubRig.make([mac], in: self)
        _ = await rig.online(sessions: 0)
        _ = await eventually { rig.hub.machines.first?.workspacesSupported == true }
        let model = WorkspaceScreenModel(ref: ref(mac), hub: rig.hub, sleep: ManualSleeper().sleep)
        let run = Task { await model.run() }
        addTeardownBlock { run.cancel() }

        await mac.dropLiveSessions()
        let away = await eventually { rig.hub.machines.first?.state != .online && rig.backoff.waiting.count == 1 }
        XCTAssertTrue(away)
        await mac.upsertWorkspace(
            LinkWorkspace(workspaceId: "ws-huge", title: String(repeating: "w", count: 70_000), order: 1, terminals: []))
        rig.backoff.release()
        let unreadable = await eventually {
            rig.hub.machines.first?.state == .online && rig.hub.machines.first?.workspacesSupported == false
        }
        XCTAssertTrue(unreadable)
        _ = await eventually(timeout: .milliseconds(200)) { false }

        XCTAssertEqual(model.phase, .showing, "nothing was closed on the Mac")
        XCTAssertEqual(model.panes.map(\.id), ["t1", "t2"], "the last chips stay")
    }

    func testRemovingTheMacLeavesWithoutSayingTheWorkspaceClosed() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace(terminals: terminals("t1"))])
        let (model, hub, _) = try await makeModel(mac)

        try await hub.unpair(machineID: mac.machine.machineID)

        let left = await eventually { model.phase == .machineRemoved }
        XCTAssertTrue(left, "\(model.phase)")
    }

    /// Closed on the Mac while the phone was away: once the Mac is back with its list, the screen leaves.
    func testAWorkspaceClosedWhileTheMacWasAwayLeavesWhenItIsBack() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace("shellx", terminals: terminals("t1")), linkWorkspace("web", order: 1)])
        let rig = try await HubRig.make([mac], in: self)
        _ = await rig.online(sessions: 0)
        _ = await eventually { rig.hub.machines.first?.workspacesSupported == true }
        let model = WorkspaceScreenModel(ref: ref(mac), hub: rig.hub, sleep: ManualSleeper().sleep)
        let run = Task { await model.run() }
        addTeardownBlock { run.cancel() }

        await mac.dropLiveSessions()
        let away = await eventually { rig.hub.machines.first?.state != .online && rig.backoff.waiting.count == 1 }
        XCTAssertTrue(away)
        await mac.removeWorkspace("ws-shellx")
        XCTAssertEqual(model.phase, .showing, "the phone does not know yet")

        rig.backoff.release()
        let left = await eventually { model.phase == .dismissed }
        XCTAssertTrue(left, "\(model.phase)")
    }

    @MainActor
    func testOnlyAnOnlineMacThatListsItsWorkspacesSaysOneWasClosed() {
        let model = MachineModel(machine: FakeMac(name: "MacBook Pro").machine)
        XCTAssertEqual(WorkspaceScreenModel.absence(of: nil), .machineRemoved)
        XCTAssertEqual(WorkspaceScreenModel.absence(of: model), .unknown, "connecting, nothing listed yet")
        model.state = .online
        XCTAssertEqual(WorkspaceScreenModel.absence(of: model), .unknown, "online, but its list could not be read")
        model.workspacesSupported = true
        XCTAssertEqual(WorkspaceScreenModel.absence(of: model), .closed)
        for state in [MachineLinkState.reconnecting, .revoked, .hostKeyChanged, .needsUpdate] {
            model.state = state
            XCTAssertEqual(WorkspaceScreenModel.absence(of: model), .unknown, "\(state)")
        }
    }

    // MARK: - Seen

    func testRunningMarksTheWorkspaceSeen() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace(terminals: terminals("t1", agent: ["t1": "s1"]))])
        await mac.upsertSession(agentSession("s1", state: .working))
        let rig = try await HubRig.make([mac], in: self)
        _ = await rig.online(sessions: 1)
        _ = await eventually { rig.hub.machines.first?.workspacesSupported == true }
        // The turn ends while the user is on the list: the workspace is "done".
        await mac.upsertSession(agentSession("s1", state: .idle))
        let id = mac.machine.machineID
        let done = await eventually { rig.hub.workspaceRows(machineID: id).first?.state == .done }
        XCTAssertTrue(done)

        let model = WorkspaceScreenModel(ref: ref(mac), hub: rig.hub, sleep: ManualSleeper().sleep)
        let run = Task { await model.run() }
        addTeardownBlock { run.cancel() }

        let seen = await eventually { rig.hub.workspaceRows(machineID: id).first?.state == .idle }
        XCTAssertTrue(seen, "opening the screen means the user looked")
    }

    func testRunStopsWhenCancelled() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace("shellx")])
        let sleeper = ManualSleeper()
        let (_, _, run) = try await makeModel(mac, workspace: "ghost", sleeper: sleeper)
        let timer = await eventually { sleeper.waiting.count == 1 }
        XCTAssertTrue(timer)

        run.cancel()
        await run.value

        XCTAssertEqual(sleeper.cancelled, 1, "the wait for the workspace ended with the screen")
    }


    // MARK: - The terminal shown (plan 2C)

    func testTheTerminalShownIsTheShellOrAnAgentShownAsTerminal() async throws {
        let mac = FakeMac(name: "Mac")
        await mac.setWorkspaces([linkWorkspace(terminals: terminals("claude", "zsh", agent: ["claude": "s1"], selected: "zsh"))])
        await mac.upsertSession(agentSession("s1"))
        let (model, _, _) = try await makeModel(mac, sessions: 1)
        XCTAssertEqual(model.terminalShown, "zsh")
        model.select("claude")
        XCTAssertNil(model.terminalShown, "an agent's chip shows its chat")
        model.showAsTerminal("claude", true)
        XCTAssertEqual(model.shownAsTerminal, ["claude"])
        XCTAssertEqual(model.terminalShown, "claude")
        model.showAsTerminal("claude", false)
        XCTAssertNil(model.terminalShown)
        model.showAsTerminal("nope", true)
        XCTAssertEqual(model.shownAsTerminal, [])
    }

    func testAnExpectedTerminalShowsOnceTheListHasIt() async throws {
        let mac = FakeMac(name: "Mac")
        await mac.setWorkspaces([linkWorkspace(terminals: terminals("zsh", selected: "zsh"))])
        let (model, _, _) = try await makeModel(mac)
        model.expect("t-new")
        XCTAssertEqual(model.selectedTerminalId, "zsh")
        await mac.upsertWorkspace(linkWorkspace(terminals: terminals("zsh", "t-new", selected: "zsh")))
        let shown = await eventually { model.selectedTerminalId == "t-new" }
        XCTAssertTrue(shown)
        XCTAssertEqual(model.shownPaneClosed, 0)
    }

    func testAnExpectedTerminalAlreadyListedShowsAtOnce() async throws {
        let mac = FakeMac(name: "Mac")
        await mac.setWorkspaces([linkWorkspace(terminals: terminals("zsh", "t-new", selected: "zsh"))])
        let (model, _, _) = try await makeModel(mac)
        XCTAssertEqual(model.selectedTerminalId, "zsh")
        model.expect("t-new")
        XCTAssertEqual(model.selectedTerminalId, "t-new")
    }

    func testPickingAChipDropsTheExpectedOne() async throws {
        let mac = FakeMac(name: "Mac")
        await mac.setWorkspaces([linkWorkspace(terminals: terminals("zsh", "other", selected: "zsh"))])
        let (model, _, _) = try await makeModel(mac)
        model.expect("t-new")
        model.select("other")
        await mac.upsertWorkspace(linkWorkspace(terminals: terminals("zsh", "other", "t-new", selected: "zsh")))
        let listed = await eventually { model.panes.contains { $0.id == "t-new" } }
        XCTAssertTrue(listed)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.selectedTerminalId, "other")
    }
}
