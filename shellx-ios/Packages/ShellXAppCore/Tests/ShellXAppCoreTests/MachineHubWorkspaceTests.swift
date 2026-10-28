import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// The hub's workspace list, rows and control calls, against a `FakeMac` (a real `LinkHost`).
@MainActor
final class MachineHubWorkspaceTests: XCTestCase {
    private func makeHub(
        _ mac: FakeMac, sleep: @escaping @Sendable (Duration) async throws -> Void = instantSleep
    ) async throws -> MachineHub {
        let vault = AccountVault(store: InMemorySecretStore())
        try await vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "tok-1", email: "a@b.c"))
        try await vault.setMachines([mac.machine], owner: "u1")
        let suite = "MachineHubWorkspaceTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let hub = MachineHub(
            vault: vault, relay: FakeRelayAccount(),
            connector: FakeMacFleet([mac], phoneKey: { try await vault.phoneKey() }), latency: LatencyLog(),
            defaults: UserDefaults(suiteName: suite)!, sleep: sleep, onUnauthorized: {})
        addTeardownBlock { await hub.stopAll() }
        await hub.start()
        return hub
    }

    private func ref(_ mac: FakeMac, _ workspace: String = "shellx") -> WorkspaceRef {
        WorkspaceRef(machineID: mac.machine.machineID, workspaceId: "ws-\(workspace)")
    }

    private func isOnline(_ hub: MachineHub) -> Bool {
        hub.machines.first?.state == .online
    }

    // MARK: - The list

    func testListArrivesAfterConnect() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([
            linkWorkspace("web", order: 1),
            linkWorkspace("shellx", order: 0, terminals: [linkTerminal("t1")], directory: "~/code/shellx", branch: "main"),
        ])
        let hub = try await makeHub(mac)
        let id = mac.machine.machineID

        let arrived = await eventually { hub.workspaceRows(machineID: id).count == 2 }

        XCTAssertTrue(arrived)
        let rows = hub.workspaceRows(machineID: id)
        XCTAssertEqual(rows.map(\.title), ["shellx", "web"])
        XCTAssertEqual(rows[0].directory, "~/code/shellx")
        XCTAssertEqual(rows[0].branch, "main")
        XCTAssertEqual(rows[0].terminals.map(\.terminalId), ["t1"])
        XCTAssertEqual(rows.map(\.state), [.idle, .idle])
        XCTAssertEqual(hub.machines.first?.workspacesSupported, true)
        XCTAssertTrue(hub.supportsWorkspaceControl(id))
        let lists = await mac.workspaceListCount
        XCTAssertEqual(lists, 1)
    }

    func testOldMacWithoutFeatureIsUnsupported() async throws {
        let mac = FakeMac(name: "Old Mac", servesWorkspaces: false)
        await mac.upsertSession(agentSession("s1"))
        let hub = try await makeHub(mac)
        let id = mac.machine.machineID

        let ready = await eventually { isOnline(hub) && hub.liveSessions.count == 1 }

        XCTAssertTrue(ready)
        XCTAssertEqual(hub.machines.first?.workspacesSupported, false)
        XCTAssertEqual(hub.workspaceRows(machineID: id), [])
        XCTAssertFalse(hub.supportsWorkspaceControl(id))
        // With no list every session is one a terminal does not name.
        XCTAssertEqual(hub.otherSessions(machineID: id).map(\.session.sessionId), ["s1"])
    }

    func testChangesArriveAsTheyHappen() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace("shellx")])
        let hub = try await makeHub(mac)
        let id = mac.machine.machineID
        _ = await eventually { hub.workspaceRows(machineID: id).count == 1 }

        await mac.upsertWorkspace(linkWorkspace("web", order: 1))
        await mac.upsertWorkspace(linkWorkspace("shellx", order: 0, terminals: [linkTerminal("t9")]))
        await mac.removeWorkspace("ws-web")

        let applied = await eventually {
            let rows = hub.workspaceRows(machineID: id)
            return rows.map(\.title) == ["shellx"] && rows[0].terminals.map(\.terminalId) == ["t9"]
        }
        XCTAssertTrue(applied, "\(hub.workspaceRows(machineID: id))")
        let lists = await mac.workspaceListCount
        XCTAssertEqual(lists, 1, "every change applied on its own, no refetch")
    }

    func testGapRefetchesList() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace("shellx")])
        let hub = try await makeHub(mac)
        let id = mac.machine.machineID
        _ = await eventually { hub.workspaceRows(machineID: id).count == 1 }

        await mac.skipNextWorkspaceRevision()
        await mac.upsertWorkspace(linkWorkspace("web", order: 1))

        let resynced = await eventually { hub.workspaceRows(machineID: id).map(\.title) == ["shellx", "web"] }
        XCTAssertTrue(resynced, "\(hub.workspaceRows(machineID: id))")
        let lists = await mac.workspaceListCount
        let connects = await mac.connectCount
        XCTAssertEqual(lists, 2, "a gap asks for the list again")
        XCTAssertEqual(connects, 1, "inside the live session")
        XCTAssertTrue(isOnline(hub))
    }

    func testReconnectReplacesList() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace("old-a"), linkWorkspace("old-b", order: 1)])
        let sleeper = ManualSleeper()
        let hub = try await makeHub(mac, sleep: sleeper.sleep)
        let id = mac.machine.machineID
        let first = await eventually { hub.workspaceRows(machineID: id).count == 2 }
        XCTAssertTrue(first)

        await mac.dropLiveSessions()
        let waiting = await eventually { hub.machines.first?.state == .reconnecting && sleeper.waiting.count == 1 }
        XCTAssertTrue(waiting, "\(String(describing: hub.machines.first?.state))")
        await mac.setWorkspaces([linkWorkspace("new", order: 0)])
        // The last known list stays while the Mac is out of reach, as the sessions do.
        XCTAssertEqual(hub.workspaceRows(machineID: id).map(\.title), ["old-a", "old-b"])

        sleeper.release()

        let replaced = await eventually { isOnline(hub) && hub.workspaceRows(machineID: id).map(\.title) == ["new"] }
        XCTAssertTrue(replaced, "\(hub.workspaceRows(machineID: id).map(\.title))")
        let connects = await mac.connectCount
        XCTAssertEqual(connects, 2)
    }

    // MARK: - Control

    func testCreateRenameCloseCallMac() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace("shellx")])
        let hub = try await makeHub(mac)
        let id = mac.machine.machineID
        _ = await eventually { hub.workspaceRows(machineID: id).count == 1 }

        let created = await hub.createWorkspace(machineID: id)
        guard case let .ok(newId?) = created else { return XCTFail("\(created)") }
        let appeared = await eventually { hub.workspaceRows(machineID: id).contains { $0.id.workspaceId == newId } }
        XCTAssertTrue(appeared)

        let newRef = WorkspaceRef(machineID: id, workspaceId: newId)
        let renamed = await hub.renameWorkspace(newRef, title: "Docs")
        XCTAssertEqual(renamed, .ok(workspaceId: nil))
        let retitled = await eventually { hub.workspaceRows(machineID: id).first { $0.id == newRef }?.title == "Docs" }
        XCTAssertTrue(retitled)

        let closed = await hub.closeWorkspace(newRef)
        XCTAssertEqual(closed, .ok(workspaceId: nil))
        let gone = await eventually { hub.workspaceRows(machineID: id).map(\.id.workspaceId) == ["ws-shellx"] }
        XCTAssertTrue(gone)

        let calls = await mac.workspaceCalls
        XCTAssertEqual(calls, ["create", "rename:\(newId):Docs", "close:\(newId)"])
    }

    func testRefusedCloseKeepsRow() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace("shellx")])
        let hub = try await makeHub(mac)
        let id = mac.machine.machineID
        _ = await eventually { hub.workspaceRows(machineID: id).count == 1 }

        await mac.setNextWorkspaceOutcome(.refused)
        let refused = await hub.closeWorkspace(ref(mac))
        XCTAssertEqual(refused, .refused)

        // A later change arrives after any wrong removal would have: the row is still there.
        await mac.upsertWorkspace(linkWorkspace("web", order: 1))
        let later = await eventually { hub.workspaceRows(machineID: id).count == 2 }
        XCTAssertTrue(later)
        XCTAssertEqual(hub.workspaceRows(machineID: id).map(\.title), ["shellx", "web"])

        // The outcome was for one call: the next close is the Mac's own answer.
        let closed = await hub.closeWorkspace(ref(mac))
        XCTAssertEqual(closed, .ok(workspaceId: nil))
        let gone = await eventually { hub.workspaceRows(machineID: id).map(\.title) == ["web"] }
        XCTAssertTrue(gone)
    }

    func testOutcomesMapToResults() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace("shellx")])
        let hub = try await makeHub(mac)
        let id = mac.machine.machineID
        _ = await eventually { hub.workspaceRows(machineID: id).count == 1 }

        let expected: [(WorkspaceControlOutcome, WorkspaceCommandResult)] = [
            (.notFound, .notFound), (.refused, .refused), (.failed, .failed),
            // An outcome from a newer Mac: it answered, but what it did is not known.
            (.other("queued"), .unknown),
        ]
        for (outcome, result) in expected {
            await mac.setNextWorkspaceOutcome(outcome)
            let created = await hub.createWorkspace(machineID: id)
            XCTAssertEqual(created, result, "create \(outcome)")
            await mac.setNextWorkspaceOutcome(outcome)
            let renamed = await hub.renameWorkspace(ref(mac), title: "x")
            XCTAssertEqual(renamed, result, "rename \(outcome)")
            await mac.setNextWorkspaceOutcome(outcome)
            let closed = await hub.closeWorkspace(ref(mac))
            XCTAssertEqual(closed, result, "close \(outcome)")
        }
        let rows = hub.workspaceRows(machineID: id)
        XCTAssertEqual(rows.map(\.title), ["shellx"])
    }

    func testRealNotFoundForAnIdTheMacDoesNotHave() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let hub = try await makeHub(mac)
        let id = mac.machine.machineID
        _ = await eventually { isOnline(hub) }

        let renamed = await hub.renameWorkspace(WorkspaceRef(machineID: id, workspaceId: "ws-gone"), title: "x")
        let closed = await hub.closeWorkspace(WorkspaceRef(machineID: id, workspaceId: "ws-gone"))

        XCTAssertEqual([renamed, closed], [.notFound, .notFound])
    }

    func testMacThatIsNotOnlineAnswersOfflineWithoutCalling() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.failNextConnects(URLError(.notConnectedToInternet), count: 1000)
        let sleeper = ManualSleeper()
        let hub = try await makeHub(mac, sleep: sleeper.sleep)
        let id = mac.machine.machineID
        let down = await eventually {
            if case .offline = hub.machines.first?.state { return true }
            return false
        }
        XCTAssertTrue(down)

        let created = await hub.createWorkspace(machineID: id)
        let renamed = await hub.renameWorkspace(ref(mac), title: "x")
        let closed = await hub.closeWorkspace(ref(mac))
        let unknownMac = await hub.createWorkspace(machineID: "mac-nobody")

        XCTAssertEqual([created, renamed, closed, unknownMac], [.offline, .offline, .offline, .offline])
        let calls = await mac.workspaceCalls
        XCTAssertEqual(calls, [])
    }

    func testConnectionLostWhileWaitingIsUnknownAndNotSentAgain() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let sleeper = ManualSleeper()
        let hub = try await makeHub(mac, sleep: sleeper.sleep)
        let id = mac.machine.machineID
        _ = await eventually { isOnline(hub) }
        await mac.holdWorkspaceControl()

        let call = Task { await hub.createWorkspace(machineID: id) }
        let received = await eventually { await mac.workspaceCalls == ["create"] }
        XCTAssertTrue(received)
        // The host waits for its held call before it lets the session go: drop from the side.
        let drop = Task { await mac.dropLiveSessions() }
        let result = await call.value
        await mac.releaseWorkspaceControl()
        await drop.value

        XCTAssertEqual(result, .unknown)
        // The Mac did act (it made the workspace); the phone finds out from the list, not by retrying.
        sleeper.release()
        let back = await eventually { isOnline(hub) && hub.workspaceRows(machineID: id).count == 1 }
        XCTAssertTrue(back, "\(hub.workspaceRows(machineID: id))")
        let calls = await mac.workspaceCalls
        XCTAssertEqual(calls, ["create"])
    }

    func testSupportsWorkspaceControlFollowsTheFeature() async throws {
        let withControl = FakeMac(name: "New Mac")
        let readOnly = FakeMac(name: "Read-only Mac", acceptsWorkspaceControl: false)
        await readOnly.setWorkspaces([linkWorkspace("shellx")])

        let hubA = try await makeHub(withControl)
        let hubB = try await makeHub(readOnly)

        // Unknown until the Mac was online once.
        let a = await eventually { isOnline(hubA) }
        let b = await eventually { isOnline(hubB) && hubB.workspaceRows(machineID: readOnly.machine.machineID).count == 1 }
        XCTAssertTrue(a && b)
        XCTAssertTrue(hubA.supportsWorkspaceControl(withControl.machine.machineID))
        XCTAssertFalse(hubB.supportsWorkspaceControl(readOnly.machine.machineID))
        XCTAssertFalse(hubA.supportsWorkspaceControl("mac-nobody"))
        let refused = await hubB.createWorkspace(machineID: readOnly.machine.machineID)
        XCTAssertEqual(refused, .failed, "nothing is sent to a Mac that takes no control")
        let calls = await readOnly.workspaceCalls
        XCTAssertEqual(calls, [])
    }

    // MARK: - Sessions no terminal names

    func testOtherSessionsExcludeChippedOnes() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([
            linkWorkspace("shellx", terminals: [linkTerminal("t1", sessionId: "s1"), linkTerminal("t2")]),
            linkWorkspace("web", order: 1, terminals: [linkTerminal("t3", sessionId: "s3")]),
        ])
        await mac.upsertSession(agentSession("s1", lastActivityMs: 500))
        // In a listed workspace, but in no terminal.
        await mac.upsertSession(agentSession("s2", lastActivityMs: 400))
        await mac.upsertSession(agentSession("s3", state: .idle, lastActivityMs: 300, workspace: "web"))
        // Ended, and its workspace is not on the list any more.
        await mac.upsertSession(
            AgentSession(
                sessionId: "s4", agent: "claude", workspaceId: "ws-closed", workspaceTitle: "closed", state: .ended,
                stateSinceMs: 1, lastActivityMs: 200))
        // No workspace at all.
        await mac.upsertSession(
            AgentSession(
                sessionId: "s5", agent: "claude", workspaceId: "", workspaceTitle: "", state: .idle, stateSinceMs: 1,
                lastActivityMs: 100))
        let hub = try await makeHub(mac)
        let id = mac.machine.machineID

        let ready = await eventually { hub.workspaceRows(machineID: id).count == 2 && hub.otherSessions(machineID: id).count == 3 }

        XCTAssertTrue(ready, "\(hub.otherSessions(machineID: id).map(\.session.sessionId))")
        let others = hub.otherSessions(machineID: id)
        XCTAssertEqual(others.map(\.session.sessionId), ["s2", "s4", "s5"])
        XCTAssertEqual(others.map(\.machineID), [id, id, id])
        XCTAssertEqual(others.map(\.machineName), ["MacBook Pro", "MacBook Pro", "MacBook Pro"])
        XCTAssertEqual(others.map(\.online), [true, true, true])
        XCTAssertEqual(hub.otherSessions(machineID: "mac-nobody"), [])
    }

    // MARK: - Done

    private func finishedRig() async throws -> (mac: FakeMac, hub: MachineHub, id: String) {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([
            linkWorkspace("shellx", terminals: [linkTerminal("t1", sessionId: "s1")]),
            linkWorkspace("web", order: 1),
        ])
        await mac.upsertSession(agentSession("s1", state: .working, lastActivityMs: 1, stateSinceMs: 1))
        await mac.upsertSession(agentSession("s2", state: .working, lastActivityMs: 1, stateSinceMs: 1, workspace: "web"))
        let hub = try await makeHub(mac)
        let id = mac.machine.machineID
        let running = await eventually { hub.workspaceRows(machineID: id).map(\.state) == [.running, .running] }
        XCTAssertTrue(running, "\(hub.workspaceRows(machineID: id).map(\.state))")
        return (mac, hub, id)
    }

    func testDoneFromFinishedSession() async throws {
        let (mac, hub, id) = try await finishedRig()
        XCTAssertEqual(hub.finishedSessionIds(machineID: id), [])

        await mac.upsertSession(agentSession("s1", state: .idle, lastActivityMs: 2, stateSinceMs: 2))

        let done = await eventually { hub.workspaceRows(machineID: id).map(\.state) == [.done, .running] }
        XCTAssertTrue(done, "\(hub.workspaceRows(machineID: id).map(\.state))")
        XCTAssertEqual(hub.finishedSessionIds(machineID: id), ["s1"])
        XCTAssertEqual(hub.finishedSessionIds(machineID: "mac-nobody"), [])
    }

    func testDoneClearsAfterMarkSeen() async throws {
        let (mac, hub, id) = try await finishedRig()
        await mac.upsertSession(agentSession("s1", state: .idle, lastActivityMs: 2, stateSinceMs: 2))
        await mac.upsertSession(agentSession("s2", state: .idle, lastActivityMs: 2, stateSinceMs: 2, workspace: "web"))
        let both = await eventually { hub.workspaceRows(machineID: id).map(\.state) == [.done, .done] }
        XCTAssertTrue(both, "\(hub.workspaceRows(machineID: id).map(\.state))")

        hub.markSeen(ref(mac))

        XCTAssertEqual(hub.workspaceRows(machineID: id).map(\.state), [.idle, .done], "only the opened workspace")
        XCTAssertEqual(hub.finishedSessionIds(machineID: id), ["s2"])
        // The same finish replayed (a resync, a nudge) is not a new one.
        await mac.upsertSession(agentSession("s1", state: .idle, lastActivityMs: 3, stateSinceMs: 2))
        let replayed = await eventually { hub.liveSessions.first { $0.session.sessionId == "s1" }?.session.lastActivityMs == 3 }
        XCTAssertTrue(replayed)
        XCTAssertEqual(hub.workspaceRows(machineID: id).map(\.state), [.idle, .done])
    }

    func testDoneEndsWhenTheAgentWorksAgain() async throws {
        let (mac, hub, id) = try await finishedRig()
        await mac.upsertSession(agentSession("s1", state: .idle, lastActivityMs: 2, stateSinceMs: 2))
        let done = await eventually { hub.finishedSessionIds(machineID: id) == ["s1"] }
        XCTAssertTrue(done)

        await mac.upsertSession(agentSession("s1", state: .working, lastActivityMs: 3, stateSinceMs: 3))
        let running = await eventually { hub.workspaceRows(machineID: id).map(\.state) == [.running, .running] }
        XCTAssertTrue(running)
        XCTAssertEqual(hub.finishedSessionIds(machineID: id), [])

        // The next finish is a new one, and it shows.
        await mac.upsertSession(agentSession("s1", state: .idle, lastActivityMs: 4, stateSinceMs: 4))
        let again = await eventually { hub.workspaceRows(machineID: id).map(\.state) == [.done, .running] }
        XCTAssertTrue(again)
    }

    func testIdleFromTheStartIsNotDone() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace("shellx")])
        await mac.upsertSession(agentSession("s1", state: .idle))
        let hub = try await makeHub(mac)
        let id = mac.machine.machineID

        let ready = await eventually { isOnline(hub) && hub.liveSessions.count == 1 }

        XCTAssertTrue(ready)
        XCTAssertEqual(hub.workspaceRows(machineID: id).map(\.state), [.idle])
        XCTAssertEqual(hub.finishedSessionIds(machineID: id), [])
    }

    func testFinishWhileDisconnectedIsDoneOnReconnect() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace("shellx")])
        await mac.upsertSession(agentSession("s1", state: .working, lastActivityMs: 1, stateSinceMs: 1))
        let sleeper = ManualSleeper()
        let hub = try await makeHub(mac, sleep: sleeper.sleep)
        let id = mac.machine.machineID
        let running = await eventually { hub.workspaceRows(machineID: id).map(\.state) == [.running] }
        XCTAssertTrue(running)

        await mac.dropLiveSessions()
        let waiting = await eventually { hub.machines.first?.state == .reconnecting && sleeper.waiting.count == 1 }
        XCTAssertTrue(waiting)
        await mac.upsertSession(agentSession("s1", state: .idle, lastActivityMs: 2, stateSinceMs: 2))
        sleeper.release()

        let done = await eventually { hub.workspaceRows(machineID: id).map(\.state) == [.done] }
        XCTAssertTrue(done, "\(hub.workspaceRows(machineID: id).map(\.state))")
    }

    func testPendingMakesTheRowNeedYou() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.setWorkspaces([linkWorkspace("shellx"), linkWorkspace("web", order: 1)])
        await mac.upsertSession(agentSession("s1", state: .working))
        await mac.addPending(pendingItem("r1", workspace: "shellx"))
        let hub = try await makeHub(mac)
        let id = mac.machine.machineID

        let ready = await eventually { hub.workspaceRows(machineID: id).map(\.state) == [.needsYou, .idle] }

        XCTAssertTrue(ready, "\(hub.workspaceRows(machineID: id).map(\.state))")
        XCTAssertEqual(hub.workspaceRows(machineID: id).first?.question, "ls")
    }
}
