import ShellXAppCore
import ShellXAppTestSupport
import ShellXLinkCore
import SwiftUI
import XCTest
@testable import ShellX

/// "Remove from This Phone" (spec 6.8) as the signed-in scope wires it, against a fake Mac that lists two
/// ghosts (sessions it answers `not_found` for) beside two live agents: only a session an agent screen saw
/// answered `not_found` is offered, on the agent screen standalone and on the swipe of the home and of the
/// outside-workspace list; removing it takes it off every list and count, also after a launch, until the Mac
/// reports a change.
@MainActor
final class GoneRemovalWiringTests: XCTestCase {
    @MainActor private struct Rig {
        let scope: SignedInScope
        let mac: FakeMac
        let defaults: UserDefaults
        let directory: URL
        let latency: LatencyLog
        let relay: FakeRelayAccount
        let vault: AccountVault
        let actions: WorkspaceListScreen.Actions

        var hub: MachineHub { scope.hub }
        var id: String { mac.machine.machineID }

        /// The listed session `sessionId` as the hub has it now.
        func session(_ sessionId: String) -> MachineSession? {
            hub.reachableSessions.first { $0.session.sessionId == sessionId }
        }

        /// The scope the next launch makes: the same `UserDefaults`, nothing in memory.
        func relaunchedScope() -> SignedInScope {
            AppComposition.makeScope(
                hub: hub, history: ConversationStore(directory: directory), latency: latency,
                launch: LaunchMark(latency: latency), pairing: PairingModel(hub: hub, relay: relay, vault: vault),
                defaults: defaults)
        }
    }

    private let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    private var fiftyTwoHoursAgoMs: Int64 { nowMs - 52 * 3_600_000 }

    private func session(_ id: String, workspace: String, sinceMs: Int64, activityMs: Int64) -> AgentSession {
        AgentSession(
            sessionId: id, agent: "claude", workspaceId: workspace.isEmpty ? "" : "ws-\(workspace)",
            workspaceTitle: workspace, state: .working, stateSinceMs: sinceMs, lastActivityMs: activityMs)
    }

    private func chat(_ text: String) -> [ChatEntry] {
        [ChatEntry(id: "e1", rev: 1, seq: 1, role: .agent, kind: .prose, text: text, tsMs: nowMs)]
    }

    /// `ws-shellx` names `live` (working, with a chat) and `ghost` (working for 52 hours, no chat: the Mac
    /// answers `not_found`) in its tabs; outside workspaces run `outsideLive` (with a chat) and `outsideGhost`
    /// (no chat).
    private func makeRig() async throws -> Rig {
        let mac = FakeMac(name: "Richard's Mac mini (2)")
        await mac.setWorkspaces([
            LinkWorkspace(
                workspaceId: "ws-shellx", title: "shellx", order: 0,
                terminals: [
                    LinkTerminal(terminalId: "t1", title: "claude", order: 0, selected: true, sessionId: "live"),
                    LinkTerminal(terminalId: "t2", title: "claude", order: 1, selected: false, sessionId: "ghost"),
                ])
        ])
        await mac.upsertSession(session("live", workspace: "shellx", sinceMs: nowMs - 60_000, activityMs: nowMs))
        await mac.setHistory(sessionId: "live", entries: chat("working on it"))
        await mac.upsertSession(
            session("ghost", workspace: "shellx", sinceMs: fiftyTwoHoursAgoMs, activityMs: fiftyTwoHoursAgoMs))
        await mac.upsertSession(session("outsideLive", workspace: "", sinceMs: nowMs - 120_000, activityMs: nowMs - 1))
        await mac.setHistory(sessionId: "outsideLive", entries: chat("over SSH"))
        await mac.upsertSession(
            session("outsideGhost", workspace: "", sinceMs: fiftyTwoHoursAgoMs, activityMs: fiftyTwoHoursAgoMs - 1))

        let vault = AccountVault(store: InMemorySecretStore())
        try await vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "tok-1", email: "a@b.c"))
        try await vault.setMachines([mac.machine], owner: "u1")
        let suite = "GoneRemovalWiringTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gone-removal-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let relay = FakeRelayAccount()
        let latency = LatencyLog()
        let hub = MachineHub(
            vault: vault, relay: relay, connector: FakeMacFleet([mac], phoneKey: { try await vault.phoneKey() }),
            latency: latency, defaults: defaults, sleep: { try await Task.sleep(for: $0) }, onUnauthorized: {})
        addTeardownBlock { @MainActor in await hub.stopAll() }
        let scope = AppComposition.makeScope(
            hub: hub, history: ConversationStore(directory: directory), latency: latency,
            launch: LaunchMark(latency: latency), pairing: PairingModel(hub: hub, relay: relay, vault: vault),
            defaults: defaults)
        await hub.start()
        let id = mac.machine.machineID
        let ready = await WorkspaceRig.eventually {
            hub.machines.first?.state == .online && hub.reachableSessions.count == 4
                && hub.workspaceRows(machineID: id).count == 1
        }
        XCTAssertTrue(ready)
        var creating = false
        let actions = WorkspaceListActions.make(
            scope: scope, open: { _ in }, alert: { _ in },
            creating: Binding(get: { creating }, set: { creating = $0 }))
        return Rig(
            scope: scope, mac: mac, defaults: defaults, directory: directory, latency: latency, relay: relay,
            vault: vault, actions: actions)
    }

    /// Opens the agent screen's model of `sessionId` as `AgentView` does, and tells the scope what it heard
    /// as `AgentView` does.
    private func openAgent(_ sessionId: String, _ rig: Rig) async throws -> AgentThreadModel {
        let model = rig.scope.agentThread(try XCTUnwrap(rig.session(sessionId)).ref)
        addTeardownBlock { @MainActor in await model.close() }
        await model.open()
        AgentView.noteGone(model, in: rig.scope)
        return model
    }

    private func homeFocus(_ rig: Rig, _ scope: SignedInScope? = nil) -> HomeFocus {
        let scope = scope ?? rig.scope
        return HomeFocus.make(
            sessions: rig.hub.reachableSessions, pending: [], finished: rig.hub.finishTimes,
            dismissed: scope.endedDismissals.dismissals, removed: scope.goneRemovals.removals, now: Date())
    }

    private func outside(_ rig: Rig, _ scope: SignedInScope? = nil) -> [String] {
        OtherSessionsView.sessions(
            hub: rig.hub, machineID: rig.id, removed: (scope ?? rig.scope).goneRemovals.removals
        ).map(\.session.sessionId)
    }

    private func outsideRemovable(_ rig: Rig) -> Set<SessionRef> {
        rig.scope.goneRemovals.removable(
            OtherSessionsView.sessions(hub: rig.hub, machineID: rig.id, removed: rig.scope.goneRemovals.removals))
    }

    // MARK: - What is offered

    func testOnlyASessionAnAgentScreenSawGoneIsOffered() async throws {
        let rig = try await makeRig()
        let ghost = try XCTUnwrap(rig.session("ghost"))
        let outsideGhost = try XCTUnwrap(rig.session("outsideGhost"))
        XCTAssertEqual(WorkspaceListView.removableAgents(rig.scope), [], "the phone cannot know before it asks")
        XCTAssertEqual(outsideRemovable(rig), [])

        let live = try await openAgent("live", rig)
        XCTAssertNil(AgentView.removable(live, embedded: false), "a live session never gets it")
        let outsideLive = try await openAgent("outsideLive", rig)
        XCTAssertNil(AgentView.removable(outsideLive, embedded: false))
        XCTAssertEqual(WorkspaceListView.removableAgents(rig.scope), [])

        let gone = try await openAgent("ghost", rig)
        XCTAssertTrue(gone.sessionGone)
        XCTAssertEqual(AgentView.removable(gone, embedded: false)?.ref, ghost.ref)
        XCTAssertNil(AgentView.removable(gone, embedded: true), "a workspace's pane offers none")
        XCTAssertEqual(WorkspaceListView.removableAgents(rig.scope), [ghost.ref])
        XCTAssertEqual(outsideRemovable(rig), [], "the ghost has a tab: it is not on the outside list")

        _ = try await openAgent("outsideGhost", rig)
        XCTAssertEqual(WorkspaceListView.removableAgents(rig.scope), [ghost.ref, outsideGhost.ref])
        XCTAssertEqual(outsideRemovable(rig), [outsideGhost.ref])
    }

    // MARK: - Removing

    func testARemovedGhostLeavesEveryListAndCountAndStaysOffAfterALaunch() async throws {
        let rig = try await makeRig()
        XCTAssertEqual(homeFocus(rig).running.map(\.session.session.sessionId), ["live", "outsideLive", "ghost", "outsideGhost"])
        XCTAssertEqual(WorkspaceListView.groups(rig.hub, removed: rig.scope.goneRemovals.removals).first?.otherSessionCount, 2)
        _ = try await openAgent("ghost", rig)
        _ = try await openAgent("outsideGhost", rig)

        // The home's swipe, then the outside-workspace list's.
        rig.actions.removeFromPhone(try XCTUnwrap(rig.session("ghost")))
        rig.scope.goneRemovals.remove(try XCTUnwrap(rig.session("outsideGhost")))

        let focus = homeFocus(rig)
        XCTAssertEqual(focus.running.map(\.session.session.sessionId), ["live", "outsideLive"])
        XCTAssertEqual(focus.running.count, 2, "\"Running · N\" counts two")
        XCTAssertTrue(focus.needsYou.isEmpty && focus.justDone.isEmpty && focus.ended.isEmpty)
        XCTAssertEqual(outside(rig), ["outsideLive"])
        XCTAssertEqual(
            WorkspaceListView.groups(rig.hub, removed: rig.scope.goneRemovals.removals).first?.otherSessionCount, 1,
            "\"Agents outside workspaces · N\" counts one")
        XCTAssertEqual(rig.hub.reachableSessions.count, 4, "nothing was asked of the Mac")

        let relaunched = rig.relaunchedScope()
        XCTAssertEqual(homeFocus(rig, relaunched).running.map(\.session.session.sessionId), ["live", "outsideLive"])
        XCTAssertEqual(outside(rig, relaunched), ["outsideLive"])
        XCTAssertEqual(
            WorkspaceListView.removableAgents(relaunched), [], "known gone is this run's only; removals stay")
    }

    func testARemovedGhostComesBackWhenItsMacReportsAChange() async throws {
        let rig = try await makeRig()
        _ = try await openAgent("ghost", rig)
        rig.actions.removeFromPhone(try XCTUnwrap(rig.session("ghost")))
        XCTAssertFalse(homeFocus(rig).running.contains { $0.session.session.sessionId == "ghost" })

        await rig.mac.upsertSession(
            session("ghost", workspace: "shellx", sinceMs: fiftyTwoHoursAgoMs, activityMs: nowMs + 1_000))
        let back = await WorkspaceRig.eventually {
            self.homeFocus(rig).running.contains { $0.session.session.sessionId == "ghost" }
        }
        XCTAssertTrue(back, "a newer last activity shows it again")
        XCTAssertEqual(
            WorkspaceListView.removableAgents(rig.scope), [], "it changed since the phone saw it gone: no swipe")
    }
}
