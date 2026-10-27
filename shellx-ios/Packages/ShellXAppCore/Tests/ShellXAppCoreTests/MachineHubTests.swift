import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// Values a `@MainActor` test collects from an async stream.
@MainActor
final class Collected<Element> {
    var items: [Element] = []
}

@MainActor
final class MachineHubTests: XCTestCase {
    private struct Rig {
        var hub: MachineHub
        var vault: AccountVault
        var relay: FakeRelayAccount
        var defaults: UserDefaults
        var latency: LatencyLog
        var unauthorized: Collected<Void>
    }

    private func listing(_ machine: PairedMachine, name: String? = nil) -> PairedMachineListing {
        PairedMachineListing(
            grantID: "g-\(machine.machineID)", machineID: machine.machineID, name: name ?? machine.name,
            platform: "macos", online: true, linkSlot: machine.linkSlot, fingerprint: "f")
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "MachineHubTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return defaults
    }

    private func rig(
        _ macs: [FakeMac], saved: [FakeMac]? = nil, sleeper: ManualSleeper = ManualSleeper(),
        defaults: UserDefaults? = nil
    ) async throws -> Rig {
        let vault = AccountVault(store: InMemorySecretStore())
        try await vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "tok-1", email: "a@b.c"))
        try await vault.setMachines((saved ?? macs).map(\.machine), owner: "u1")
        let relay = FakeRelayAccount()
        await relay.setGrants(macs.map { listing($0.machine) })
        let latency = LatencyLog()
        let unauthorized = Collected<Void>()
        let defaults = defaults ?? makeDefaults()
        let hub = MachineHub(
            vault: vault, relay: relay, connector: FakeMacFleet(macs, phoneKey: { try await vault.phoneKey() }),
            latency: latency, defaults: defaults, sleep: sleeper.sleep,
            onUnauthorized: { unauthorized.items.append(()) })
        addTeardownBlock { await hub.stopAll() }
        return Rig(
            hub: hub, vault: vault, relay: relay, defaults: defaults, latency: latency, unauthorized: unauthorized)
    }

    private func model(_ hub: MachineHub, _ mac: FakeMac) -> MachineModel? {
        hub.machines.first { $0.machine.machineID == mac.machine.machineID }
    }

    private func allOnline(_ hub: MachineHub) -> Bool {
        !hub.machines.isEmpty && hub.machines.allSatisfy { $0.state == .online }
    }

    // MARK: - Brief tests

    func testStartsOneConnectionPerPairedMachine() async throws {
        let a = FakeMac(name: "MacBook Pro")
        let b = FakeMac(name: "Mac mini")
        let rig = try await rig([a, b])

        await rig.hub.start()
        await rig.hub.start()

        XCTAssertEqual(rig.hub.machines.map(\.name), ["MacBook Pro", "Mac mini"])
        let online = await eventually { allOnline(rig.hub) }
        XCTAssertTrue(online, "\(rig.hub.machines.map(\.state))")
        let connectsA = await a.connectCount
        let connectsB = await b.connectCount
        XCTAssertEqual([connectsA, connectsB], [1, 1])
    }

    func testPendingMergedAcrossMachinesSortedByCreation() async throws {
        let a = FakeMac(name: "MacBook Pro")
        let b = FakeMac(name: "Mac mini")
        await a.addPending(pendingItem("a1", createdAtMs: 30))
        await a.addPending(pendingItem("a2", createdAtMs: 10))
        await b.addPending(pendingItem("b1", createdAtMs: 20))
        let rig = try await rig([a, b])

        await rig.hub.start()

        let merged = await eventually { rig.hub.pendingItems.count == 3 }
        XCTAssertTrue(merged, "\(rig.hub.pendingItems.map(\.item.requestId))")
        let items = rig.hub.pendingItems
        XCTAssertEqual(items.map(\.item.requestId), ["a2", "b1", "a1"])
        XCTAssertEqual(items.map(\.machineName), ["MacBook Pro", "Mac mini", "MacBook Pro"])
        XCTAssertEqual(items.map(\.actionable), [true, true, true])
        XCTAssertEqual(items[1].id, PendingKey(machineID: b.machine.machineID, requestId: "b1"))
    }

    func testPathChangeForcesReconnect() async throws {
        let a = FakeMac(name: "MacBook Pro")
        let b = FakeMac(name: "Mac mini")
        await a.addPending(pendingItem("a1"))
        await b.failNextConnects(URLError(.notConnectedToInternet), count: 1)
        let sleeper = ManualSleeper()
        let rig = try await rig([a, b], sleeper: sleeper)
        await rig.hub.start()
        let settled = await eventually {
            guard case .offline = model(rig.hub, b)?.state else { return false }
            return model(rig.hub, a)?.state == .online && sleeper.waiting.count == 1
        }
        XCTAssertTrue(settled, "\(rig.hub.machines.map(\.state))")

        // Wi-Fi to cellular: the live session may be dead without anyone knowing yet.
        rig.hub.networkChanged()

        let reconnected = await eventually {
            let connectsA = await a.connectCount
            let connectsB = await b.connectCount
            return connectsA == 2 && connectsB == 2 && allOnline(rig.hub)
        }
        XCTAssertTrue(reconnected, "\(rig.hub.machines.map(\.state))")
        XCTAssertEqual(sleeper.cancelled, 1, "the offline Mac skipped the rest of its backoff")
        let liveA = await eventually { await a.liveSessionCount == 1 }
        XCTAssertTrue(liveA, "the old session to MacBook Pro was closed")
        XCTAssertEqual(rig.hub.pendingItems.map(\.actionable), [true])
    }

    func testBackgroundClosesAfterGrace() async throws {
        let a = FakeMac(name: "MacBook Pro")
        await a.addPending(pendingItem("a1"))
        let sleeper = ManualSleeper()
        let rig = try await rig([a], sleeper: sleeper)
        await rig.hub.start()
        _ = await eventually { allOnline(rig.hub) }

        let hub = rig.hub
        let background = Task { await hub.appDidEnterBackground() }
        let graceStarted = await eventually { sleeper.waiting == [MachineHub.backgroundGrace] }
        XCTAssertTrue(graceStarted, "\(sleeper.waiting)")
        XCTAssertEqual(MachineHub.backgroundGrace, .seconds(25))
        let stillLive = await a.liveSessionCount
        XCTAssertEqual(stillLive, 1, "nothing closes during the grace")

        sleeper.release()
        await background.value

        let closed = await eventually { await a.liveSessionCount == 0 }
        XCTAssertTrue(closed)
        XCTAssertNotEqual(model(rig.hub, a)?.state, .online)
        XCTAssertEqual(rig.hub.pendingItems.map(\.actionable), [false])
        do {
            _ = try await rig.hub.reply(
                PendingKey(machineID: a.machine.machineID, requestId: "a1"), decision: .permission(.once))
            XCTFail("a reply while suspended must fail")
        } catch {
            XCTAssertEqual(error as? LinkCallError, .offline(machineName: "MacBook Pro"))
        }

        rig.hub.appDidBecomeActive()
        let back = await eventually { allOnline(rig.hub) && rig.hub.pendingItems.map(\.actionable) == [true] }
        XCTAssertTrue(back, "\(rig.hub.machines.map(\.state))")
        let connects = await a.connectCount
        XCTAssertEqual(connects, 2)
    }

    func testQuickReturnKeepsSessions() async throws {
        let a = FakeMac(name: "MacBook Pro")
        let sleeper = ManualSleeper()
        let rig = try await rig([a], sleeper: sleeper)
        await rig.hub.start()
        _ = await eventually { allOnline(rig.hub) }

        let hub = rig.hub
        let background = Task { await hub.appDidEnterBackground() }
        _ = await eventually { sleeper.waiting == [MachineHub.backgroundGrace] }

        rig.hub.appDidBecomeActive()
        await background.value

        XCTAssertEqual(sleeper.cancelled, 1, "coming back cancels the grace")
        let connects = await a.connectCount
        let live = await a.liveSessionCount
        XCTAssertEqual(connects, 1)
        XCTAssertEqual(live, 1)
        XCTAssertEqual(model(rig.hub, a)?.state, .online)
    }

    func testRefreshMarksMissingGrantRevokedAndRenames() async throws {
        let a = FakeMac(name: "MacBook Pro")
        let b = FakeMac(name: "Mac mini")
        await b.addPending(pendingItem("b1"))
        let rig = try await rig([a, b])
        await rig.hub.start()
        _ = await eventually { allOnline(rig.hub) && rig.hub.pendingItems.count == 1 }

        await rig.relay.setGrants([listing(a.machine, name: "Studio")])
        await rig.hub.refreshGrants()

        XCTAssertEqual(model(rig.hub, a)?.name, "Studio")
        XCTAssertEqual(model(rig.hub, a)?.state, .online)
        XCTAssertEqual(model(rig.hub, b)?.state, .revoked)
        XCTAssertEqual(rig.hub.pendingItems.map(\.item.requestId), [])
        let closed = await eventually { await b.liveSessionCount == 0 }
        XCTAssertTrue(closed, "the revoked Mac's session was closed")
        let saved = try await rig.vault.machines()
        XCTAssertEqual(saved.map(\.machineID), [a.machine.machineID, b.machine.machineID], "refresh does not write the vault")
        XCTAssertEqual(rig.hub.machines.count, 2, "a revoked Mac stays listed until the user removes it")
    }

    func testUnauthorizedCallsCoordinator() async throws {
        let a = FakeMac(name: "MacBook Pro")
        await a.failNextConnects(RelayAPIError.http(status: 401, code: "unauthorized"), count: 1)
        let vault = AccountVault(store: InMemorySecretStore())
        try await vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "tok-1", email: "a@b.c"))
        try await vault.setMachines([a.machine], owner: "u1")
        let relay = FakeRelayAccount()
        let defaults = makeDefaults()
        let box = CoordinatorBox()
        let coordinator = AppCoordinator(
            vault: vault, relay: relay, deviceName: "iPhone", wipers: [],
            makeHub: {
                MachineHub(
                    vault: vault, relay: relay, connector: FakeMacFleet([a], phoneKey: { try await vault.phoneKey() }),
                    latency: LatencyLog(), defaults: defaults, sleep: instantSleep,
                    onUnauthorized: { await box.coordinator?.handleUnauthorized() })
            })
        box.coordinator = coordinator
        addTeardownBlock { await coordinator.hub?.stopAll() }

        await coordinator.launch()

        let signedOut = await eventually { coordinator.phase == .signedOut(expired: true) && coordinator.hub == nil }
        XCTAssertTrue(signedOut, "\(coordinator.phase)")
        let machines = try await vault.machines()
        XCTAssertEqual(machines, [a.machine], "an expired token keeps the paired Macs")
        let connects = await a.connectCount
        XCTAssertEqual(connects, 1)
    }

    func testChatAndSessionUpdatesMulticast() async throws {
        let a = FakeMac(name: "MacBook Pro")
        await a.upsertSession(agentSession("s1"))
        await a.setHistory(sessionId: "s1", entries: [])
        let rig = try await rig([a])
        await rig.hub.start()
        _ = await eventually { allOnline(rig.hub) && rig.hub.liveSessions.count == 1 }

        let chatA = Collected<(SessionRef, [ChatEntry])>()
        let chatB = Collected<(SessionRef, [ChatEntry])>()
        let listsA = Collected<(machineID: String, sessions: [AgentSession])>()
        let listsB = Collected<(machineID: String, sessions: [AgentSession])>()
        let streamChatA = rig.hub.chatUpdates()
        let streamChatB = rig.hub.chatUpdates()
        let streamListsA = rig.hub.sessionUpdates()
        let streamListsB = rig.hub.sessionUpdates()
        let readers = [
            Task { for await update in streamChatA { chatA.items.append(update) } },
            Task { for await update in streamListsA { listsA.items.append(update) } },
        ]
        let readerChatB = Task { for await update in streamChatB { chatB.items.append(update) } }
        let readerListsB = Task { for await update in streamListsB { listsB.items.append(update) } }
        defer { for reader in readers { reader.cancel() } }

        await a.pushChat(sessionId: "s1", entries: [chatEntry(1)])
        await a.upsertSession(agentSession("s2"))

        let both = await eventually {
            chatA.items.count == 1 && chatB.items.count == 1 && listsA.items.count == 1 && listsB.items.count == 1
        }
        XCTAssertTrue(both, "\(chatA.items.count) \(chatB.items.count) \(listsA.items.count) \(listsB.items.count)")
        let ref = SessionRef(machineID: a.machine.machineID, sessionId: "s1", agent: "claude", workspaceTitle: "shellx")
        XCTAssertEqual(chatA.items.first?.0, ref)
        XCTAssertEqual(chatA.items.first?.0.workspaceTitle, "shellx")
        XCTAssertEqual(chatA.items.first?.1, [chatEntry(1)])
        XCTAssertEqual(chatB.items.first?.1, [chatEntry(1)])
        XCTAssertEqual(listsA.items.first?.machineID, a.machine.machineID)
        XCTAssertEqual(Set(listsB.items.first?.sessions.map(\.sessionId) ?? []), ["s1", "s2"])

        // A reader that stops is dropped; the other keeps receiving.
        readerChatB.cancel()
        readerListsB.cancel()
        let dropped = await eventually { rig.hub.chatSubscriberCount == 1 && rig.hub.sessionSubscriberCount == 1 }
        XCTAssertTrue(dropped)
        await a.pushChat(sessionId: "s1", entries: [chatEntry(2)])
        let second = await eventually { chatA.items.count == 2 }
        XCTAssertTrue(second)
        XCTAssertEqual(chatB.items.count, 1)

        // No replay: a new reader only sees what comes after it.
        let late = Collected<(SessionRef, [ChatEntry])>()
        let streamLate = rig.hub.chatUpdates()
        let readerLate = Task { for await update in streamLate { late.items.append(update) } }
        defer { readerLate.cancel() }
        await a.pushChat(sessionId: "s1", entries: [chatEntry(3)])
        let third = await eventually { chatA.items.count == 3 && late.items.count == 1 }
        XCTAssertTrue(third)
        XCTAssertEqual(late.items.first?.1, [chatEntry(3)])
    }

    // MARK: - Calls, pairing, default Mac

    func testCallsRouteToTheirMac() async throws {
        let a = FakeMac(name: "MacBook Pro")
        let b = FakeMac(name: "Mac mini")
        await a.addPending(pendingItem("a1"))
        await b.addPending(pendingItem("b1"))
        await a.upsertSession(agentSession("s1"))
        await a.setHistory(sessionId: "s1", entries: [chatEntry(1), chatEntry(2)])
        await a.setInterruptOutcome(.sent)
        let rig = try await rig([a, b])
        await rig.hub.start()
        _ = await eventually { allOnline(rig.hub) && rig.hub.pendingItems.count == 2 }

        let outcome = try await rig.hub.reply(
            PendingKey(machineID: b.machine.machineID, requestId: "b1"), decision: .permission(.always))
        XCTAssertEqual(outcome, .delivered)
        let decisionsA = await a.decisions
        let decisionsB = await b.decisions
        XCTAssertEqual(decisionsA, [])
        XCTAssertEqual(decisionsB, [FakeMac.Decision(requestId: "b1", decision: .permission(.always))])
        XCTAssertEqual(rig.latency.summary(.replyRoundTrip)?.count, 1)

        let ref = try XCTUnwrap(rig.hub.liveSessions.first?.ref)
        XCTAssertEqual(ref.machineID, a.machine.machineID)
        let page = try await rig.hub.chatHistory(ref, beforeSeq: nil, limit: 10)
        XCTAssertEqual(page.entries, [chatEntry(1), chatEntry(2)])
        XCTAssertFalse(page.hasMore)
        let sent = try await rig.hub.chatSend(ref, text: "run the tests")
        XCTAssertEqual(sent, .submitted)
        let texts = await a.sentTexts
        XCTAssertEqual(texts, [FakeMac.SentText(sessionId: "s1", text: "run the tests")])
        let interrupted = try await rig.hub.chatInterrupt(ref, hard: true)
        XCTAssertEqual(interrupted, .sent)
        let interrupts = await a.interrupts
        XCTAssertEqual(interrupts, [FakeMac.Interrupt(sessionId: "s1", hard: true)])

        do {
            _ = try await rig.hub.reply(PendingKey(machineID: "nope", requestId: "x"), decision: .permission(.once))
            XCTFail("an unknown Mac must fail")
        } catch {
            XCTAssertEqual(error as? LinkCallError, .unknownMachine)
        }
    }

    func testAddSavesMachineAndReplacesSameID() async throws {
        let a = FakeMac(name: "MacBook Pro")
        let rig = try await rig([a], saved: [])
        await rig.hub.start()
        XCTAssertEqual(rig.hub.machines.count, 0)

        try await rig.hub.add(a.machine)
        let online = await eventually { allOnline(rig.hub) }
        XCTAssertTrue(online)
        var saved = try await rig.vault.machines()
        XCTAssertEqual(saved, [a.machine])
        let owner = try await rig.vault.machinesOwner()
        XCTAssertEqual(owner, "u1")
        XCTAssertEqual(rig.hub.defaultMachineID, a.machine.machineID)

        var renamed = a.machine
        renamed.name = "Studio"
        try await rig.hub.add(renamed)
        XCTAssertEqual(rig.hub.machines.map(\.name), ["Studio"])
        saved = try await rig.vault.machines()
        XCTAssertEqual(saved, [renamed])
        let back = await eventually { allOnline(rig.hub) }
        XCTAssertTrue(back)
        let live = await eventually { await a.liveSessionCount == 1 }
        XCTAssertTrue(live, "the replaced connection was stopped")
    }

    func testDefaultMachineFallsBackToFirst() async throws {
        let a = FakeMac(name: "MacBook Pro")
        let b = FakeMac(name: "Mac mini")
        let defaults = makeDefaults()
        let rig = try await rig([a, b], defaults: defaults)
        XCTAssertNil(rig.hub.defaultMachineID, "no Macs, no default")
        await rig.hub.start()
        XCTAssertEqual(rig.hub.defaultMachineID, a.machine.machineID)

        rig.hub.defaultMachineID = b.machine.machineID
        XCTAssertEqual(defaults.string(forKey: "shellx.defaultMachineID"), b.machine.machineID)
        XCTAssertEqual(rig.hub.defaultMachineID, b.machine.machineID)

        // A default whose Mac is gone falls back to the first Mac.
        defaults.set("removed-mac", forKey: "shellx.defaultMachineID")
        let other = try await self.rig([a, b], defaults: defaults)
        await other.hub.start()
        XCTAssertEqual(other.hub.defaultMachineID, a.machine.machineID)
    }

    func testRefreshUnauthorizedReports() async throws {
        let a = FakeMac(name: "MacBook Pro")
        let rig = try await rig([a])
        await rig.relay.setError(RelayAPIError.http(status: 401, code: "unauthorized"), for: .machines)

        await rig.hub.refreshGrants()
        await rig.hub.refreshGrants()

        XCTAssertEqual(rig.unauthorized.items.count, 1, "reported once")
    }
}

/// Lets a hub's `onUnauthorized` reach the coordinator that owns the hub, as the app's composition does.
@MainActor
final class CoordinatorBox {
    weak var coordinator: AppCoordinator?
}
