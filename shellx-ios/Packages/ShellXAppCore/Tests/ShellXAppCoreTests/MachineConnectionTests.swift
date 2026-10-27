import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import ShellXLinkSession
import XCTest

@testable import ShellXAppCore

final class MachineConnectionTests: XCTestCase {
    private var connections: [MachineConnection] = []

    override func tearDown() async throws {
        for connection in connections { await connection.stop() }
        connections = []
    }

    private func connect(
        _ mac: FakeMac, sleep: @escaping @Sendable (Duration) async throws -> Void = instantSleep,
        latency: LatencyLog = LatencyLog()
    ) async -> (MachineConnection, EventLog) {
        let phone = NoiseStaticKey()
        let connection = MachineConnection(
            machine: mac.machine, connector: mac.connector(phoneKey: { phone }), latency: latency, sleep: sleep)
        connections.append(connection)
        let log = EventLog(connection.events)
        await connection.start()
        return (connection, log)
    }

    // MARK: - Session

    func testConnectsAndPublishesPendingAndSessions() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(pendingItem("r1"))
        await mac.upsertSession(agentSession("s1"))

        let (_, log) = await connect(mac)

        let online = await eventually { log.isOnline }
        XCTAssertTrue(online, "\(log.states)")
        XCTAssertEqual(log.states, [.connecting, .online])
        XCTAssertEqual(log.pendingIDs, ["r1"])
        XCTAssertEqual(log.pending?.actionable, true)
        XCTAssertEqual(log.sessionIDs, ["s1"])
        XCTAssertEqual(log.sessions?.supported, true)
        let connects = await mac.connectCount
        XCTAssertEqual(connects, 1)
    }

    func testChangesAppliedInOrder() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(pendingItem("r1", createdAtMs: 10))
        let latency = LatencyLog()
        let (_, log) = await connect(mac, latency: latency)
        _ = await eventually { log.isOnline }
        let base = try XCTUnwrap(log.pending?.set.revision)

        await mac.addPending(pendingItem("r3", createdAtMs: 30))
        await mac.addPending(pendingItem("r2", createdAtMs: 20))
        await mac.resolvePending("r1")
        await mac.upsertSession(agentSession("s1", lastActivityMs: 1))
        await mac.upsertSession(agentSession("s2", lastActivityMs: 2))
        await mac.removeSession("s1")

        let applied = await eventually { log.pending?.set.revision == base + 3 && log.sessionIDs == ["s2"] }
        XCTAssertTrue(applied, "\(log.pendingIDs) \(log.sessionIDs)")
        XCTAssertEqual(log.pendingIDs, ["r2", "r3"])
        // Every change was applied on its own, one revision after the other.
        let revisions = log.pendingEvents.map(\.set.revision)
        XCTAssertEqual(Array(revisions.suffix(4)), [base, base + 1, base + 2, base + 3])
        XCTAssertEqual(latency.summary(.pendingArrival)?.count, 2)
        XCTAssertEqual(latency.summary(.sessionChangeArrival)?.count, 2)
        let snapshots = await mac.snapshotCount
        XCTAssertEqual(snapshots, 1)
    }

    func testRevisionGapTriggersResync() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(pendingItem("r1", createdAtMs: 10))
        let (_, log) = await connect(mac)
        _ = await eventually { log.isOnline }

        await mac.skipNextPendingRevision()
        await mac.addPending(pendingItem("r2", createdAtMs: 20))
        await mac.skipNextSessionRevision()
        await mac.upsertSession(agentSession("s9"))

        let resynced = await eventually { log.pendingIDs == ["r1", "r2"] && log.sessionIDs == ["s9"] }
        XCTAssertTrue(resynced, "\(log.pendingIDs) \(log.sessionIDs)")
        let snapshots = await mac.snapshotCount
        let sessionLists = await mac.sessionListCount
        let connects = await mac.connectCount
        XCTAssertEqual(snapshots, 2, "a gap asks for a new snapshot")
        XCTAssertEqual(sessionLists, 2, "a session gap asks for the list again")
        XCTAssertEqual(connects, 1, "the resync happens inside the live session")
        XCTAssertEqual(log.state, .online)
    }

    func testHostWithoutSessionsStillServesPending() async throws {
        let mac = FakeMac(name: "Old Mac", servesSessionsAndChat: false)
        await mac.addPending(pendingItem("r1", createdAtMs: 10))
        let (_, log) = await connect(mac)

        let online = await eventually { log.isOnline }
        XCTAssertTrue(online, "\(log.states)")
        XCTAssertEqual(log.sessions?.supported, false)
        XCTAssertEqual(log.sessionIDs, [])

        await mac.addPending(pendingItem("r2", createdAtMs: 20))
        let arrived = await eventually { log.pendingIDs == ["r1", "r2"] }
        XCTAssertTrue(arrived, "\(log.pendingIDs)")
        XCTAssertEqual(log.pending?.actionable, true)
    }

    func testChatEntriesConsumedWithoutSubscribers() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.upsertSession(agentSession("s1"))
        await mac.setHistory(sessionId: "s1", entries: [])
        let (_, log) = await connect(mac)
        _ = await eventually { log.isOnline }

        // Nobody looks at chat: the connection still drains every push off the client's unbounded
        // buffer (it hands them on as events and keeps none), and pending items keep flowing.
        for batch in 0..<100 {
            await mac.pushChat(sessionId: "s1", entries: (0..<100).map { chatEntry(batch * 100 + $0) })
        }
        await mac.addPending(pendingItem("r1"))

        let drained = await eventually(timeout: .seconds(30)) { log.chatEntries == 10_000 && log.pendingIDs == ["r1"] }
        XCTAssertTrue(drained, "chat \(log.chatEntries), pending \(log.pendingIDs)")
    }

    // MARK: - Reconnect

    func testSessionEndReconnects() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(pendingItem("r1"))
        let (_, log) = await connect(mac)
        _ = await eventually { log.isOnline }

        await mac.dropLiveSessions()

        let back = await eventually { log.states.count >= 4 && log.isOnline }
        XCTAssertTrue(back, "\(log.states)")
        XCTAssertEqual(log.states, [.connecting, .online, .reconnecting, .online])
        XCTAssertEqual(log.pendingIDs, ["r1"])
        XCTAssertEqual(log.pending?.actionable, true)
        let connects = await mac.connectCount
        XCTAssertEqual(connects, 2)
    }

    func testPendingDisabledWhileReconnectingClearedWhenOffline() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(pendingItem("r1"))
        let sleeper = ManualSleeper()
        let (connection, log) = await connect(mac, sleep: sleeper.sleep)
        _ = await eventually { log.isOnline }
        XCTAssertEqual(log.pending?.actionable, true)

        await mac.failNextConnects(URLError(.notConnectedToInternet), count: 1)
        await mac.dropLiveSessions()

        // The session is gone: the items stay, but nothing may act on them.
        let reconnecting = await eventually { log.state == .reconnecting && sleeper.waiting.count == 1 }
        XCTAssertTrue(reconnecting, "\(log.states)")
        XCTAssertEqual(log.pendingIDs, ["r1"])
        XCTAssertEqual(log.pending?.actionable, false)
        do {
            _ = try await connection.call { try await $0.snapshot() }
            XCTFail("a call while reconnecting must fail")
        } catch {
            XCTAssertEqual(error as? LinkCallError, .offline(machineName: "MacBook Pro"))
        }
        XCTAssertEqual(seconds(try XCTUnwrap(sleeper.waiting.first)), 0.5, accuracy: 0.11)

        // The first reconnect fails: the Mac is offline and its items are gone.
        sleeper.release()
        let offline = await eventually { log.isOffline && sleeper.waiting.count == 1 }
        XCTAssertTrue(offline, "\(log.states)")
        XCTAssertEqual(log.pendingIDs, [])
        XCTAssertEqual(log.pending?.actionable, false)
        XCTAssertEqual(seconds(try XCTUnwrap(sleeper.waiting.first)), 1, accuracy: 0.21)

        // The next attempt succeeds and resyncs.
        sleeper.release()
        let online = await eventually { log.isOnline }
        XCTAssertTrue(online, "\(log.states)")
        XCTAssertEqual(log.pendingIDs, ["r1"])
        XCTAssertEqual(log.pending?.actionable, true)
        guard case .offline = log.states.dropLast().last else { return XCTFail("\(log.states)") }
    }

    func testNotGrantedStopsLoopAndMarksRevoked() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(pendingItem("r1"))
        let (connection, log) = await connect(mac)
        _ = await eventually { log.isOnline }

        await mac.failNextConnects(RelayAPIError.http(status: 403, code: "not_granted"), count: 5)
        await mac.dropLiveSessions()

        let stopped = await eventually { log.finished }
        XCTAssertTrue(stopped, "\(log.states)")
        XCTAssertEqual(log.state, .revoked)
        XCTAssertEqual(log.pendingIDs, [])
        XCTAssertEqual(log.pending?.actionable, false)
        await connection.reconnectNow()
        await connection.forceReconnect()
        let connects = await mac.connectCount
        XCTAssertEqual(connects, 2, "the loop stopped after the refusal")
    }

    func testUnauthorizedStopsAndReports() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.failNextConnects(RelayAPIError.http(status: 401, code: "unauthorized"), count: 5)
        let (_, log) = await connect(mac)

        let stopped = await eventually { log.finished }
        XCTAssertTrue(stopped, "\(log.states)")
        XCTAssertEqual(log.signedOut, 1)
        XCTAssertNotEqual(log.state, .online)
        XCTAssertEqual(log.pending?.actionable ?? false, false)
        let connects = await mac.connectCount
        XCTAssertEqual(connects, 1)
    }

    func testUntrustedHostStops() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.rotateHostKey()
        let (_, log) = await connect(mac)

        let stopped = await eventually { log.finished }
        XCTAssertTrue(stopped, "\(log.states)")
        XCTAssertEqual(log.state, .hostKeyChanged)
        let connects = await mac.connectCount
        XCTAssertEqual(connects, 1)
    }

    func testProtocolMismatchStops() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.failNextConnects(LinkClientError.protocolMismatch(message: "the host speaks protocol 2"), count: 5)
        let (_, log) = await connect(mac)

        let stopped = await eventually { log.finished }
        XCTAssertTrue(stopped, "\(log.states)")
        XCTAssertEqual(log.state, .needsUpdate)
        let connects = await mac.connectCount
        XCTAssertEqual(connects, 1)
    }

    func testReconnectNowSkipsBackoff() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.failNextConnects(URLError(.cannotConnectToHost), count: 1)
        let sleeper = ManualSleeper()
        let (connection, log) = await connect(mac, sleep: sleeper.sleep)

        let waiting = await eventually { log.isOffline && sleeper.waiting.count == 1 }
        XCTAssertTrue(waiting, "\(log.states)")

        await connection.reconnectNow()

        let online = await eventually { log.isOnline }
        XCTAssertTrue(online, "\(log.states)")
        XCTAssertEqual(sleeper.cancelled, 1, "the backoff wait was cut short")
        let connects = await mac.connectCount
        XCTAssertEqual(connects, 2)
    }

    func testCallWhenOfflineThrowsOffline() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(pendingItem("r1"))
        await mac.failNextConnects(URLError(.notConnectedToInternet), count: 1)
        let sleeper = ManualSleeper()
        let (connection, log) = await connect(mac, sleep: sleeper.sleep)
        _ = await eventually { log.isOffline }

        do {
            _ = try await connection.call { try await $0.reply(requestId: "r1", decision: .permission(.once)) }
            XCTFail("a call while offline must fail")
        } catch {
            XCTAssertEqual(error as? LinkCallError, .offline(machineName: "MacBook Pro"))
        }
        let decisions = await mac.decisions
        XCTAssertEqual(decisions, [], "nothing reached the Mac")

        sleeper.release()
        _ = await eventually { log.isOnline }
        let outcome = try await connection.call { try await $0.reply(requestId: "r1", decision: .permission(.once)) }
        XCTAssertEqual(outcome, .delivered)
    }

    func testForceReconnectAbortsAnAttemptStillSyncing() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(pendingItem("r1"))
        await mac.holdSnapshots()
        let sleeper = ManualSleeper()
        let (connection, log) = await connect(mac, sleep: sleeper.sleep)
        let syncing = await eventually { await mac.heldSnapshotCount == 1 }
        XCTAssertTrue(syncing)

        await connection.forceReconnect()

        let replaced = await eventually(timeout: .seconds(3)) { await mac.connectCount == 2 }
        XCTAssertTrue(replaced, "the attempt was dropped and started again")
        await mac.releaseSnapshots()
        let online = await eventually { log.isOnline }
        XCTAssertTrue(online, "\(log.states)")
        // Dropping our own attempt is not a failure: no offline, no cleared items, no backoff.
        XCTAssertEqual(log.states, [.connecting, .online])
        XCTAssertEqual(log.pendingIDs, ["r1"])
        XCTAssertEqual(sleeper.requested, [])
    }

    func testSlotMismatchStops() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.failNextConnects(RelayAPIError.slotMismatch, count: 5)
        let (_, log) = await connect(mac)

        let stopped = await eventually { log.finished }
        XCTAssertTrue(stopped, "\(log.states)")
        XCTAssertEqual(log.state, .hostKeyChanged)
        let connects = await mac.connectCount
        XCTAssertEqual(connects, 1)
    }

    func testForceReconnectReplacesLiveSession() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let sleeper = ManualSleeper()
        let (connection, log) = await connect(mac, sleep: sleeper.sleep)
        _ = await eventually { log.isOnline }

        await connection.forceReconnect()

        let back = await eventually { log.states == [.connecting, .online, .reconnecting, .online] }
        XCTAssertTrue(back, "\(log.states)")
        XCTAssertEqual(sleeper.requested, [], "a forced reconnect does not wait")
        let connects = await mac.connectCount
        XCTAssertEqual(connects, 2)
        let oneLive = await eventually { await mac.liveSessionCount == 1 }
        XCTAssertTrue(oneLive, "the old session was closed")
    }
}
