import ShellXAppCore
import ShellXAppTestSupport
import ShellXLinkCore
import SwiftUI
import XCTest
@testable import ShellX

/// The workspace list's controls as `WorkspaceListActions` wires them to the signed-in scope, run one
/// by one against fake Macs: each reaches the hub call it stands for and does with the answer what
/// `WorkspaceFeedback` says (no UI automation is available, so this is the executed coverage of the
/// list's wiring).
@MainActor
final class WorkspaceListActionsTests: XCTestCase {
    /// What the actions did to the screen.
    private final class Screen {
        var routes: [HomeRoute] = []
        var alerts: [WorkspaceAlert] = []
        var creating = false
        var tasks: [Task<WorkspaceFeedback, Never>] = []
    }

    @MainActor private struct Rig {
        let scope: SignedInScope
        let screen: Screen
        let actions: WorkspaceListScreen.Actions

        var hub: MachineHub { scope.hub }

        /// The feedback of the command the last action started.
        func lastFeedback() async -> WorkspaceFeedback? {
            await screen.tasks.last?.value
        }
    }

    private func eventually(_ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    /// A signed-in scope, made as `AppComposition` makes it, over a hub connected to `macs`.
    private func makeRig(_ macs: [FakeMac]) async throws -> Rig {
        let vault = AccountVault(store: InMemorySecretStore())
        try await vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "tok-1", email: "a@b.c"))
        try await vault.setMachines(macs.map(\.machine), owner: "u1")
        let suite = "WorkspaceListActionsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-actions-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let relay = FakeRelayAccount()
        let latency = LatencyLog()
        let hub = MachineHub(
            vault: vault, relay: relay, connector: FakeMacFleet(macs, phoneKey: { try await vault.phoneKey() }),
            latency: latency, defaults: defaults, sleep: { try await Task.sleep(for: $0) }, onUnauthorized: {})
        addTeardownBlock { @MainActor in await hub.stopAll() }
        let scope = AppComposition.makeScope(
            hub: hub, history: ConversationStore(directory: directory), latency: latency,
            launch: LaunchMark(latency: latency), pairing: PairingModel(hub: hub, relay: relay, vault: vault))
        await hub.start()
        let screen = Screen()
        let actions = WorkspaceListActions.make(
            scope: scope, open: { screen.routes.append($0) }, alert: { screen.alerts.append($0) },
            creating: Binding(get: { screen.creating }, set: { screen.creating = $0 }),
            done: { screen.tasks.append($0) })
        return Rig(scope: scope, screen: screen, actions: actions)
    }

    private func workspace(_ name: String, order: Int = 0) -> LinkWorkspace {
        LinkWorkspace(
            workspaceId: "ws-\(name)", title: name, order: order,
            terminals: [LinkTerminal(terminalId: "\(name)-t1", title: "zsh", order: 0, selected: true)])
    }

    private func macWithWorkspaces(_ names: [String], name: String = "MacBook Pro") async -> FakeMac {
        let mac = FakeMac(name: name)
        await mac.setWorkspaces(names.enumerated().map { workspace($1, order: $0) })
        return mac
    }

    private func ref(_ mac: FakeMac, _ name: String) -> WorkspaceRef {
        WorkspaceRef(machineID: mac.machine.machineID, workspaceId: "ws-\(name)")
    }

    private func titles(_ rig: Rig, _ mac: FakeMac) -> [String] {
        rig.hub.workspaceRows(machineID: mac.machine.machineID).map(\.title)
    }

    // MARK: - Screens

    func testControlsPushTheirScreens() async throws {
        let mac = await macWithWorkspaces(["shellx"])
        let rig = try await makeRig([mac])
        let target = ref(mac, "shellx")

        rig.actions.openWorkspace(target)
        rig.actions.openPending()
        rig.actions.openSettings()
        rig.actions.openMachines()
        rig.actions.openOtherSessions(mac.machine.machineID)

        XCTAssertEqual(
            rig.screen.routes,
            [.workspace(target), .pending, .settings, .machines, .otherSessions(machineID: mac.machine.machineID)])
    }

    func testEndedFoldPushesTheEndedPage() async throws {
        let mac = await macWithWorkspaces(["shellx"])
        let rig = try await makeRig([mac])

        rig.actions.openEnded()

        XCTAssertEqual(rig.screen.routes, [.ended])
    }

    func testOpeningAWorkspaceMarksItSeen() async throws {
        let mac = await macWithWorkspaces(["shellx"])
        let session = AgentSession(
            sessionId: "s1", agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx", state: .working)
        await mac.upsertSession(session)
        let rig = try await makeRig([mac])
        let id = mac.machine.machineID
        let running = await eventually { rig.hub.workspaceRows(machineID: id).map(\.state) == [.running] }
        XCTAssertTrue(running)

        // The agent finishes its turn: the card says so until the workspace is opened.
        var done = session
        done.state = .idle
        await mac.upsertSession(done)
        let finished = await eventually { rig.hub.workspaceRows(machineID: id).map(\.state) == [.done] }
        XCTAssertTrue(finished)

        rig.actions.openWorkspace(ref(mac, "shellx"))

        XCTAssertEqual(rig.hub.workspaceRows(machineID: id).map(\.state), [.idle])
    }

    // MARK: - Commands

    func testCreateOpensTheNewWorkspace() async throws {
        let mac = await macWithWorkspaces(["shellx"])
        let rig = try await makeRig([mac])
        let id = mac.machine.machineID
        let online = await eventually { rig.hub.machines.first?.state == .online }
        XCTAssertTrue(online)

        rig.actions.create(id)
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .open(WorkspaceRef(machineID: id, workspaceId: "ws-new-1")))
        XCTAssertEqual(rig.screen.routes, [.workspace(WorkspaceRef(machineID: id, workspaceId: "ws-new-1"))])
        XCTAssertEqual(rig.screen.alerts, [])
        XCTAssertFalse(rig.screen.creating, "＋ works again once the Mac answered")
        let calls = await mac.workspaceCalls
        XCTAssertEqual(calls, ["create"])
        let arrived = await eventually { self.titles(rig, mac) == ["shellx", "Workspace 1"] }
        XCTAssertTrue(arrived, "\(titles(rig, mac))")
    }

    func testASecondTapOnCreateWaitsForTheFirst() async throws {
        let mac = await macWithWorkspaces(["shellx"])
        let rig = try await makeRig([mac])
        let id = mac.machine.machineID
        let online = await eventually { rig.hub.machines.first?.state == .online }
        XCTAssertTrue(online)
        await mac.holdWorkspaceControl()

        rig.actions.create(id)
        XCTAssertTrue(rig.screen.creating)
        rig.actions.create(id)
        XCTAssertEqual(rig.screen.tasks.count, 1, "the second tap started nothing")
        let held = await eventually { await mac.workspaceCalls == ["create"] }
        XCTAssertTrue(held)
        await mac.releaseWorkspaceControl()
        _ = await rig.lastFeedback()

        let calls = await mac.workspaceCalls
        XCTAssertEqual(calls, ["create"])
        XCTAssertFalse(rig.screen.creating)
    }

    func testRenameChangesTheRowByPush() async throws {
        let mac = await macWithWorkspaces(["shellx", "web"])
        let rig = try await makeRig([mac])
        let listed = await eventually { self.titles(rig, mac) == ["shellx", "web"] }
        XCTAssertTrue(listed)

        rig.actions.rename(ref(mac, "web"), "landing")
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, WorkspaceFeedback.nothing)
        let calls = await mac.workspaceCalls
        XCTAssertEqual(calls, ["rename:ws-web:landing"])
        let renamed = await eventually { self.titles(rig, mac) == ["shellx", "landing"] }
        XCTAssertTrue(renamed, "\(titles(rig, mac))")
        XCTAssertEqual(rig.screen.alerts, [])
    }

    func testCloseRemovesTheRowByPush() async throws {
        let mac = await macWithWorkspaces(["shellx", "web"])
        let rig = try await makeRig([mac])
        let listed = await eventually { self.titles(rig, mac) == ["shellx", "web"] }
        XCTAssertTrue(listed)

        rig.actions.close(ref(mac, "web"))
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, WorkspaceFeedback.nothing)
        let calls = await mac.workspaceCalls
        XCTAssertEqual(calls, ["close:ws-web"])
        let closed = await eventually { self.titles(rig, mac) == ["shellx"] }
        XCTAssertTrue(closed, "\(titles(rig, mac))")
    }

    func testClosingTheLastWorkspaceIsAnAlert() async throws {
        let mac = await macWithWorkspaces(["shellx"])
        let rig = try await makeRig([mac])
        let listed = await eventually { self.titles(rig, mac) == ["shellx"] }
        XCTAssertTrue(listed)

        rig.actions.close(ref(mac, "shellx"))
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .alert(.refusedClose))
        XCTAssertEqual(rig.screen.alerts, [.refusedClose])
        XCTAssertEqual(titles(rig, mac), ["shellx"], "the row stays")
    }

    func testRenameBlockedByTheMacIsAnAlert() async throws {
        let mac = await macWithWorkspaces(["shellx"])
        let rig = try await makeRig([mac])
        let listed = await eventually { self.titles(rig, mac) == ["shellx"] }
        XCTAssertTrue(listed)
        await mac.setNextWorkspaceOutcome(.refused)

        rig.actions.rename(ref(mac, "shellx"), "x")
        _ = await rig.lastFeedback()

        XCTAssertEqual(rig.screen.alerts, [.refusedControl])
    }

    func testAWorkspaceTheMacDoesNotHaveRefreshesTheListQuietly() async throws {
        let mac = await macWithWorkspaces(["shellx"])
        let rig = try await makeRig([mac])
        let listed = await eventually { self.titles(rig, mac) == ["shellx"] }
        XCTAssertTrue(listed)
        let before = await mac.workspaceListCount

        rig.actions.rename(WorkspaceRef(machineID: mac.machine.machineID, workspaceId: "ws-ghost"), "x")
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .refresh)
        XCTAssertEqual(rig.screen.alerts, [], "no word to the user")
        let after = await mac.workspaceListCount
        XCTAssertEqual(after, before + 1, "the Mac was asked for its list again")
    }

    func testAMacThatIsNotOnlineAnswersOfflineWithAnAlert() async throws {
        let mac = await macWithWorkspaces(["shellx"])
        let rig = try await makeRig([mac])

        rig.actions.create("mac-unknown")
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .alert(.offline))
        XCTAssertEqual(rig.screen.alerts, [.offline])
        XCTAssertFalse(rig.screen.creating)
        let calls = await mac.workspaceCalls
        XCTAssertEqual(calls, [])
    }

    // MARK: - Closing an agent

    /// A Mac with the workspace `shellx`, where the agent `claude` (session `s1`) works.
    /// A Mac with the workspace `shellx`, whose one tab runs the agent `claude` (session `s1`).
    private func macWithAnAgent(name: String = "MacBook Pro", acceptsAgentClose: Bool = true) async -> FakeMac {
        let mac = FakeMac(name: name, acceptsAgentClose: acceptsAgentClose)
        await mac.setWorkspaces([
            LinkWorkspace(
                workspaceId: "ws-shellx", title: "shellx", order: 0,
                terminals: [
                    LinkTerminal(terminalId: "shellx-t1", title: "claude", order: 0, selected: true, sessionId: "s1")
                ])
        ])
        await mac.upsertSession(
            AgentSession(
                sessionId: "s1", agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx", state: .working))
        return mac
    }

    private func agentRef(_ mac: FakeMac) -> SessionRef {
        SessionRef(machineID: mac.machine.machineID, sessionId: "s1", agent: "claude", workspaceTitle: "shellx")
    }

    func testCloseAgentAsksTheMacOnce() async throws {
        let mac = await macWithAnAgent()
        let rig = try await makeRig([mac])
        let running = await eventually { rig.hub.machines.first?.state == .online && rig.hub.liveSessions.count == 1 }
        XCTAssertTrue(running)
        await mac.holdWorkspaceControl()

        rig.actions.closeAgent(agentRef(mac))
        rig.actions.closeAgent(agentRef(mac))
        XCTAssertEqual(rig.screen.tasks.count, 1, "the second tap started nothing")
        let held = await eventually { await mac.agentCloses == ["s1"] }
        XCTAssertTrue(held)
        await mac.releaseWorkspaceControl()
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .nothing, "the card leaves for Ended by the Mac's push")
        let calls = await mac.agentCloses
        XCTAssertEqual(calls, ["s1"])
        XCTAssertEqual(rig.screen.alerts, [])
        let ended = await eventually { rig.hub.liveSessions.isEmpty }
        XCTAssertTrue(ended)

        // Answered: Close goes out again (and the Mac says this agent has stopped).
        rig.actions.closeAgent(agentRef(mac))
        XCTAssertEqual(rig.screen.tasks.count, 2)
        let again = await rig.lastFeedback()
        XCTAssertEqual(again, .alert(.agentNotClosable))
    }

    func testCloseAgentTheMacCannotCloseIsAnAlert() async throws {
        let mac = await macWithAnAgent()
        let rig = try await makeRig([mac])
        let running = await eventually { rig.hub.machines.first?.state == .online && rig.hub.liveSessions.count == 1 }
        XCTAssertTrue(running)
        let lists = await mac.workspaceListCount
        await mac.setNextAgentCloseOutcome(.notFound)

        rig.actions.closeAgent(agentRef(mac))
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .alert(.agentNotClosable))
        XCTAssertEqual(rig.screen.alerts, [.agentNotClosable])
        let listsAfter = await mac.workspaceListCount
        XCTAssertEqual(listsAfter, lists, "an agent the Mac cannot close is not a workspace list gone stale")
        XCTAssertEqual(rig.hub.liveSessions.count, 1, "the agent still runs")
    }

    func testCloseAgentTheMacRefusesSaysWhy() async throws {
        let mac = await macWithAnAgent()
        let rig = try await makeRig([mac])
        let running = await eventually { rig.hub.machines.first?.state == .online && rig.hub.liveSessions.count == 1 }
        XCTAssertTrue(running)
        // Remote control blocked, or the agent's tab is the last of a pinned or kept-open workspace.
        await mac.setNextAgentCloseOutcome(.refused)

        rig.actions.closeAgent(agentRef(mac))
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .alert(.refusedCloseAgent))
        XCTAssertEqual(rig.screen.alerts, [.refusedCloseAgent])
        XCTAssertEqual(rig.hub.liveSessions.count, 1, "the agent still runs")
    }

    func testOnlyAnOnlineMacThatTakesAgentCloseOffersIt() async throws {
        let modern = await macWithAnAgent(name: "MacBook Pro")
        let old = await macWithAnAgent(name: "iMac", acceptsAgentClose: false)
        let rig = try await makeRig([modern, old])
        let ready = await eventually {
            rig.hub.machines.count == 2 && rig.hub.machines.allSatisfy { $0.state == .online }
        }
        XCTAssertTrue(ready)

        XCTAssertEqual(WorkspaceListView.closableAgents(rig.hub), [agentRef(modern)])

        // The modern Mac goes away and does not come back.
        let id = modern.machine.machineID
        await modern.failNextConnects(URLError(.notConnectedToInternet), count: 1000)
        await modern.dropLiveSessions()
        let away = await eventually { rig.hub.machines.first { $0.id == id }?.state != .online }
        XCTAssertTrue(away)
        XCTAssertTrue(rig.hub.supportsAgentClose(id), "it took agent.close when it was last online")
        XCTAssertEqual(WorkspaceListView.closableAgents(rig.hub), [], "no Close while the Mac is away")
    }

    /// Close Agent is offered only for an agent a tab of the Mac's listed workspaces names: `agent.close` finds
    /// nothing else, so an agent outside workspaces (run over SSH, or in a workspace since closed) has no Close
    /// anywhere, and neither has an agent that ended in its tab.
    func testOnlyAnAgentWithAListedTabOffersClose() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([
            LinkWorkspace(
                workspaceId: "ws-shellx", title: "shellx", order: 0,
                terminals: [
                    LinkTerminal(terminalId: "t1", title: "claude", order: 0, selected: true, sessionId: "s1"),
                    LinkTerminal(terminalId: "t2", title: "zsh", order: 1, selected: false, sessionId: "s3"),
                ])
        ])
        // `s1` runs in a listed tab; `s2` over SSH, which no listed tab names; `s3` ended in its tab.
        await mac.upsertSession(
            AgentSession(
                sessionId: "s1", agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx", state: .working))
        await mac.upsertSession(
            AgentSession(sessionId: "s2", agent: "claude", workspaceId: "", workspaceTitle: "", state: .working))
        await mac.upsertSession(
            AgentSession(
                sessionId: "s3", agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx", state: .ended))
        let rig = try await makeRig([mac])
        let id = mac.machine.machineID
        let ready = await eventually {
            rig.hub.machines.first?.state == .online && rig.hub.reachableSessions.count == 3
                && rig.hub.workspaceRows(machineID: id).count == 1
        }
        XCTAssertTrue(ready)
        let sessions = Dictionary(uniqueKeysWithValues: rig.hub.reachableSessions.map { ($0.session.sessionId, $0) })

        XCTAssertTrue(WorkspaceListActions.canClose(try XCTUnwrap(sessions["s1"]), hub: rig.hub))
        XCTAssertFalse(
            WorkspaceListActions.canClose(try XCTUnwrap(sessions["s2"]), hub: rig.hub),
            "no listed tab names it: the Mac would answer not_found")
        XCTAssertFalse(
            WorkspaceListActions.canClose(try XCTUnwrap(sessions["s3"]), hub: rig.hub), "its tab runs the shell now")
        XCTAssertEqual(rig.hub.otherSessions(machineID: id).map(\.session.sessionId), ["s2"])
        XCTAssertFalse(
            rig.hub.otherSessions(machineID: id).contains { WorkspaceListActions.canClose($0, hub: rig.hub) },
            "no agent outside workspaces offers Close")
        // The home's swipe goes by the same rule.
        XCTAssertEqual(WorkspaceListView.closableAgents(rig.hub), [try XCTUnwrap(sessions["s1"]).ref])
    }

    // MARK: - Closing a tab

    /// A Mac with the workspace `shellx`: a shell `t1` and the agent `claude` (session `s1`) in `t2`.
    private func macWithTabs(name: String = "MacBook Pro", acceptsTerminalClose: Bool = true) async -> FakeMac {
        let mac = FakeMac(name: name, acceptsTerminalClose: acceptsTerminalClose)
        await mac.setWorkspaces([
            LinkWorkspace(
                workspaceId: "ws-shellx", title: "shellx", order: 0,
                terminals: [
                    LinkTerminal(terminalId: "t1", title: "zsh", order: 0, selected: true),
                    LinkTerminal(terminalId: "t2", title: "claude", order: 1, selected: false, sessionId: "s1"),
                ])
        ])
        await mac.upsertSession(
            AgentSession(
                sessionId: "s1", agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx", state: .working))
        return mac
    }

    private func tabs(_ rig: Rig, _ mac: FakeMac) -> [String] {
        rig.hub.machines.first { $0.id == mac.machine.machineID }?.workspaces.workspace("ws-shellx")?.terminals
            .map(\.terminalId) ?? []
    }

    private func terminalCloses(_ mac: FakeMac) async -> [String] {
        await mac.terminalCloses.map { "\($0.workspaceId)/\($0.terminalId)" }
    }

    private func closeTab(_ rig: Rig, _ mac: FakeMac, _ terminalId: String) {
        WorkspaceListActions.closeTab(
            machineID: mac.machine.machineID, workspaceId: "ws-shellx", terminalId: terminalId, hub: rig.hub,
            alert: { rig.screen.alerts.append($0) }, done: { rig.screen.tasks.append($0) })
    }

    func testCloseTabAsksTheMacOnce() async throws {
        let mac = await macWithTabs()
        let rig = try await makeRig([mac])
        let listed = await eventually { rig.hub.machines.first?.state == .online && self.tabs(rig, mac) == ["t1", "t2"] }
        XCTAssertTrue(listed)
        await mac.holdWorkspaceControl()

        // A long-press's Close Tab… and the menu's, on the same tab, both confirmed.
        closeTab(rig, mac, "t1")
        closeTab(rig, mac, "t1")
        XCTAssertEqual(rig.screen.tasks.count, 1, "the second close started nothing")
        let held = await eventually { await self.terminalCloses(mac) == ["ws-shellx/t1"] }
        XCTAssertTrue(held)
        // Another tab is another close.
        closeTab(rig, mac, "t2")
        XCTAssertEqual(rig.screen.tasks.count, 2)
        await mac.releaseWorkspaceControl()
        for task in rig.screen.tasks { _ = await task.value }

        let calls = await terminalCloses(mac)
        XCTAssertEqual(Set(calls), ["ws-shellx/t1", "ws-shellx/t2"])
        XCTAssertEqual(calls.filter { $0 == "ws-shellx/t1" }.count, 1, "exactly one terminal.close for t1")
        XCTAssertEqual(rig.screen.alerts, [])

        // Answered: Close Tab goes out again (and the Mac says the tab is no longer there).
        let before = rig.screen.tasks.count
        closeTab(rig, mac, "t1")
        XCTAssertEqual(rig.screen.tasks.count, before + 1)
        let again = await rig.lastFeedback()
        XCTAssertEqual(again, .alert(.tabNotClosable))
    }

    func testCloseTabTheMacCannotCloseIsAnAlert() async throws {
        let mac = await macWithTabs()
        let rig = try await makeRig([mac])
        let listed = await eventually { rig.hub.machines.first?.state == .online && self.tabs(rig, mac) == ["t1", "t2"] }
        XCTAssertTrue(listed)
        let lists = await mac.workspaceListCount
        await mac.setNextTerminalCloseOutcome(.notFound)

        closeTab(rig, mac, "t1")
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .alert(.tabNotClosable))
        XCTAssertEqual(rig.screen.alerts, [.tabNotClosable])
        let listsAfter = await mac.workspaceListCount
        XCTAssertEqual(listsAfter, lists, "said, not refreshed quietly")
        XCTAssertEqual(tabs(rig, mac), ["t1", "t2"])
    }

    func testCloseTabTheMacRefusesSaysWhy() async throws {
        let mac = await macWithTabs()
        let rig = try await makeRig([mac])
        let listed = await eventually { rig.hub.machines.first?.state == .online && self.tabs(rig, mac) == ["t1", "t2"] }
        XCTAssertTrue(listed)
        // Remote control blocked, or the last tab of a pinned or kept-open workspace.
        await mac.setNextTerminalCloseOutcome(.refused)

        closeTab(rig, mac, "t1")
        let feedback = await rig.lastFeedback()

        XCTAssertEqual(feedback, .alert(.refusedCloseTab))
        XCTAssertEqual(rig.screen.alerts, [.refusedCloseTab])
        XCTAssertEqual(tabs(rig, mac), ["t1", "t2"], "the tab stays")
    }

    func testAMacWithoutTerminalCloseOffersNoCloseTab() async throws {
        let modern = await macWithTabs(name: "MacBook Pro")
        let old = await macWithTabs(name: "iMac", acceptsTerminalClose: false)
        let rig = try await makeRig([modern, old])
        let ready = await eventually {
            rig.hub.machines.count == 2 && rig.hub.machines.allSatisfy { $0.state == .online }
                && self.tabs(rig, old) == ["t1", "t2"]
        }
        XCTAssertTrue(ready)

        XCTAssertTrue(WorkspaceListActions.canCloseTab(machineID: modern.machine.machineID, hub: rig.hub))
        XCTAssertFalse(WorkspaceListActions.canCloseTab(machineID: old.machine.machineID, hub: rig.hub))
        XCTAssertEqual(
            WorkspaceMenuItem.items(
                canCloseTab: WorkspaceListActions.canCloseTab(machineID: old.machine.machineID, hub: rig.hub)),
            [.rename, .closeWorkspace])

        // Nothing reaches such a Mac even if a close were started: only the frames the phone sent can show it.
        let before = old.phoneFrameCount
        WorkspaceListActions.closeTab(
            machineID: old.machine.machineID, workspaceId: "ws-shellx", terminalId: "t1", hub: rig.hub,
            alert: { rig.screen.alerts.append($0) }, done: { rig.screen.tasks.append($0) })
        _ = await rig.lastFeedback()
        XCTAssertEqual(old.phoneFrameCount, before, "no frame is sent to a Mac from before terminal_close")
        let calls = await old.terminalCloses
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(tabs(rig, old), ["t1", "t2"])
    }

    func testPullToRefreshAsksTheOnlineMacsAgain() async throws {
        let mac = await macWithWorkspaces(["shellx"])
        let rig = try await makeRig([mac])
        let listed = await eventually { self.titles(rig, mac) == ["shellx"] }
        XCTAssertTrue(listed)

        await rig.actions.refresh()

        let lists = await mac.workspaceListCount
        XCTAssertEqual(lists, 2)
    }

    // MARK: - What the list shows

    func testGroupsPutTheDefaultMacFirstAndFlagAnOldOne() async throws {
        let modern = await macWithWorkspaces(["shellx", "web"], name: "MacBook Pro")
        let old = FakeMac(name: "iMac", servesWorkspaces: false)
        await old.upsertSession(
            AgentSession(
                sessionId: "s1", agent: "claude", workspaceId: "ws-x", workspaceTitle: "x", state: .working))
        let rig = try await makeRig([modern, old])
        let ready = await eventually {
            rig.hub.machines.allSatisfy { $0.state == .online } && rig.hub.machines.count == 2
        }
        XCTAssertTrue(ready)
        rig.hub.defaultMachineID = old.machine.machineID

        let groups = WorkspaceListView.groups(rig.hub)

        XCTAssertEqual(groups.map(\.name), ["iMac", "MacBook Pro"], "the default Mac is first")
        XCTAssertEqual(groups.map(\.isDefault), [true, false])
        XCTAssertEqual(groups.map(\.listsWorkspaces), [false, true], "an old Mac cannot list workspaces")
        XCTAssertEqual(groups.map(\.allowsControl), [false, true])
        XCTAssertEqual(groups.map(\.canControl), [false, true])
        XCTAssertEqual(groups[1].rows.map(\.title), ["shellx", "web"])
        XCTAssertEqual(groups.map(\.otherSessionCount), [1, 0], "the old Mac's sessions are all 'other'")
    }

    func testAMacNotOnlineYetIsNotCalledOld() async throws {
        let mac = await macWithWorkspaces(["shellx"])
        let rig = try await makeRig([mac])
        // Before the first connection finishes, the Mac has not said what it lists.
        let groups = WorkspaceListView.groups(rig.hub)
        if let group = groups.first, group.state != .online {
            XCTAssertTrue(group.listsWorkspaces)
        }
        let online = await eventually { rig.hub.machines.first?.state == .online }
        XCTAssertTrue(online)
        XCTAssertEqual(WorkspaceListView.groups(rig.hub).first?.listsWorkspaces, true)
    }
}
