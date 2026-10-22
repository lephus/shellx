import Foundation
import ShellXLinkCore
import ShellXLinkRelay
@testable import ShellXLinkSession
import XCTest

final class LinkSessionTests: XCTestCase {
    private var serveTasks: [Task<Void, Never>] = []
    private var clients: [LinkClient] = []

    override func tearDown() async throws {
        for client in clients { await client.close() }
        // Cancelling `serve` must end the session (the cancelled receive closes the circuit).
        for task in serveTasks {
            task.cancel()
            await task.value
        }
        serveTasks = []
        clients = []
    }

    // MARK: - Brief tests

    func testHelloWelcomeAndSnapshot() async throws {
        let feed = FakeFeedSource([permissionItem("r1")])
        let rig = makeHost(feed)
        let client = try await connect(rig)
        let snap = try await within { try await client.snapshot() }
        XCTAssertEqual(snap.pending.count, 1)
        XCTAssertEqual(snap.pending.first?.kind, .permission)
        XCTAssertEqual(snap.pending.first?.toolName, "Bash")
    }

    func testReplyDelivered() async throws {
        let feed = FakeFeedSource([permissionItem("r1")])
        let client = try await connect(makeHost(feed))
        let outcome = try await within { try await client.reply(requestId: "r1", mode: .once) }
        XCTAssertEqual(outcome, .delivered)
        XCTAssertEqual(feed.replies.map(\.requestId), ["r1"])
        XCTAssertEqual(feed.replies.first?.mode, .once)
    }

    func testReplyTwiceIsAlreadyHandled() async throws {
        let feed = FakeFeedSource([permissionItem("r1")])
        let client = try await connect(makeHost(feed))
        let first = try await within { try await client.reply(requestId: "r1", mode: .once) }
        let second = try await within { try await client.reply(requestId: "r1", mode: .once) }
        XCTAssertEqual(first, .delivered)
        XCTAssertEqual(second, .alreadyHandled)
    }

    func testChangedPushedWithinOneSecond() async throws {
        let feed = FakeFeedSource([permissionItem("r1")])
        let client = try await connect(makeHost(feed))
        let seen = collect(client.changes)
        let start = ContinuousClock.now
        feed.add(permissionItem("r2"))
        let arrived = await eventually(within: .seconds(1)) {
            seen.items.contains { $0.added.map(\.requestId) == ["r2"] }
        }
        XCTAssertTrue(arrived, "agent.changed did not arrive within 1 s")
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(1))
    }

    func testTwoClientsSeeResolution() async throws {
        let feed = FakeFeedSource([permissionItem("r1")])
        let rig = makeHost(feed, clientCount: 2)
        let clientA = try await connect(rig, clientIndex: 0)
        let clientB = try await connect(rig, clientIndex: 1)
        let seenByA = collect(clientA.changes)
        let seenByB = collect(clientB.changes)

        feed.add(permissionItem("r2"))
        for (name, seen) in [("A", seenByA), ("B", seenByB)] {
            let added = await eventually { seen.items.contains { $0.added.map(\.requestId) == ["r2"] } }
            XCTAssertTrue(added, "client \(name) did not learn that r2 was added")
        }

        let outcome = try await within { try await clientA.reply(requestId: "r1", mode: .always) }
        XCTAssertEqual(outcome, .delivered)
        for (name, seen) in [("A", seenByA), ("B", seenByB)] {
            let resolved = await eventually { seen.items.contains { $0.resolved == ["r1"] } }
            XCTAssertTrue(resolved, "client \(name) did not learn that r1 was resolved")
        }
    }

    func testUntrustedClientDropped() async throws {
        let feed = FakeFeedSource([permissionItem("r1")])
        let rig = makeHost(feed, clientCount: 1, trustClients: false)
        do {
            _ = try await connect(rig)
            XCTFail("connect succeeded for an untrusted client")
        } catch {
            // The client finishes its side of the handshake; the host then drops the circuit.
            XCTAssertEqual(error as? RelayError, .closed, "unexpected error \(error)")
        }
        XCTAssertTrue(feed.untouched, "host called the feed for an untrusted client")
    }

    func testReconnectGetsFreshSnapshot() async throws {
        let feed = FakeFeedSource([permissionItem("r1")])
        let rig = makeHost(feed)
        let (end1, served1) = startServe(rig.host)
        let client1 = try await connectClient(end1, rig)
        let first = try await within { try await client1.snapshot() }
        XCTAssertEqual(first.pending.map(\.requestId), ["r1"])

        await end1.close()
        let ended = await eventually { served1.isSet }
        XCTAssertTrue(ended, "serve did not end after the circuit closed")
        feed.resolveLocally(requestId: "r1")
        feed.add(permissionItem("r2"))

        let client2 = try await connect(rig)
        let second = try await within { try await client2.snapshot() }
        XCTAssertEqual(second.pending.map(\.requestId), ["r2"])
    }

    func testClientRejectsWrongHostKeyBeforeMessage3() async throws {
        let impostorKey = NoiseStaticKey()
        let expectedHostKey = NoiseStaticKey()
        let (clientEnd, hostEnd) = makeInMemoryCircuitPair()
        let responder = Task { () -> String in
            var handshake = NoiseHandshake(role: .responder, local: impostorKey, trusts: { _ in true })
            let message1 = try await hostEnd.receive()
            _ = try handshake.readMessage(message1)
            try await hostEnd.send(try handshake.writeMessage(payload: Data()))
            do {
                _ = try await hostEnd.receive()
                return "received message 3"
            } catch {
                return "\(error)"
            }
        }
        do {
            _ = try await LinkClient.connect(
                clientEnd, key: NoiseStaticKey(), hostKey: expectedHostKey.publicKey, clientVersion: "1",
                deviceName: "phone")
            XCTFail("connect succeeded against the wrong host key")
        } catch {
            XCTAssertEqual(error as? NoiseError, .untrustedPeer, "unexpected error \(error)")
        }
        // Message 3 would reveal the phone's static key to the impostor; it must never be sent.
        let responderSaw = try await responder.value
        XCTAssertEqual(responderSaw, "\(RelayError.closed)")
    }

    // MARK: - PROTOCOL.md section 7: errors and phases

    func testWelcomeIsFirstFrameWhileFeedChanges() async throws {
        let feed = FakeFeedSource()
        // A change lands the moment the host subscribes, so a pusher started before `welcome`
        // would have an `agent.changed` ready to race it.
        feed.changeOnSubscribe = true
        let churn = Task {
            var n = 0
            while !Task.isCancelled {
                n += 1
                feed.add(permissionItem("c\(n)"))
                await Task.yield()
            }
        }
        defer { churn.cancel() }
        // A long machine name makes `welcome` slow to encode, giving a racing pusher a head start.
        let machineName = String(repeating: "m", count: 60_000)
        let rig = makeHost(feed, machineName: machineName)
        for _ in 0..<100 {
            let (end, _) = startServe(rig.host)
            let raw = try await rawChannel(end, rig)
            try await raw.send(.hello(clientVersion: "raw", deviceName: "raw"))
            let first = try await raw.receive()
            guard case let .welcome(_, _, name) = first, name == machineName else {
                XCTFail("the first frame after hello was \(String(describing: first).prefix(80)), not welcome")
                return
            }
            // The change from the subscription still arrives after `welcome`: nothing was lost.
            var sawSubscribeChange = false
            while !sawSubscribeChange {
                guard case let .changed(_, added, _) = try await raw.receive() else { continue }
                sawSubscribeChange = added.contains { $0.requestId.hasPrefix("sub-") }
            }
            await raw.close()
        }
    }

    func testFirstFrameNotHelloGetsBadRequestAndClose() async throws {
        let feed = FakeFeedSource([permissionItem("r1")])
        let rig = makeHost(feed)
        let (end, served) = startServe(rig.host)
        let raw = try await rawChannel(end, rig)
        try await raw.send(.snapshotGet)
        let reply = try await raw.receive()
        XCTAssertEqual(errorCode(reply), "bad_request")
        await assertClosed(raw)
        let ended = await eventually { served.isSet }
        XCTAssertTrue(ended)
        XCTAssertTrue(feed.untouched)
    }

    func testWrongVersionGetsProtocolMismatchAndClose() async throws {
        let rig = makeHost(FakeFeedSource())
        let (end, served) = startServe(rig.host)
        let raw = try await rawEstablished(end, rig)
        try await raw.send(frame: Data(#"{"v":2,"t":"ping","nonce":1}"#.utf8))
        let reply = try await raw.receive()
        XCTAssertEqual(errorCode(reply), "protocol_mismatch")
        await assertClosed(raw)
        let ended = await eventually { served.isSet }
        XCTAssertTrue(ended)
    }

    func testUndecodableFrameOnHostKeepsSession() async throws {
        let rig = makeHost(FakeFeedSource())
        let (end, served) = startServe(rig.host)
        let raw = try await rawEstablished(end, rig)
        try await raw.send(frame: Data(#"{"v":1,"t":"ping"}"#.utf8))
        let rejected = try await raw.receive()
        XCTAssertEqual(errorCode(rejected), "bad_request")
        try await raw.send(.ping(nonce: 7))
        let pong = try await raw.receive()
        XCTAssertEqual(pong, .pong(nonce: 7))
        XCTAssertFalse(served.isSet)
    }

    func testClientDropsUndecodableFrame() async throws {
        let hostKey = NoiseStaticKey()
        let clientKey = NoiseStaticKey()
        let (clientEnd, hostEnd) = makeInMemoryCircuitPair()
        let rawHost = Task {
            let ch = try await SecureChannel.open(
                hostEnd, role: .responder, key: hostKey, trusts: { $0 == clientKey.publicKey })
            guard case .hello = try await ch.receive() else { throw RelayError.closed }
            try await ch.send(.welcome(protocolVersion: 1, hostVersion: "test", machineName: "mac"))
            try await ch.send(frame: Data(#"{"v":1,"t":"agent.changed","revision":1}"#.utf8))
            try await ch.send(.changed(revision: 2, added: [permissionItem("r9")], resolved: []))
            return ch
        }
        let client = try await LinkClient.connect(
            clientEnd, key: clientKey, hostKey: hostKey.publicKey, clientVersion: "1", deviceName: "phone")
        clients.append(client)
        let seen = collect(client.changes)
        _ = try await rawHost.value
        let arrived = await eventually { seen.items.contains { $0.revision == 2 } }
        XCTAssertTrue(arrived, "the valid frame after an undecodable one was lost")
        XCTAssertEqual(seen.items.map(\.revision), [2])
    }

    func testClientSeesProtocolMismatch() async throws {
        let hostKey = NoiseStaticKey()
        let clientKey = NoiseStaticKey()
        let (clientEnd, hostEnd) = makeInMemoryCircuitPair()
        let rawHost = Task {
            let ch = try await SecureChannel.open(
                hostEnd, role: .responder, key: hostKey, trusts: { _ in true })
            _ = try await ch.receive()
            try await ch.send(.error(code: "protocol_mismatch", message: "update the app"))
        }
        do {
            _ = try await LinkClient.connect(
                clientEnd, key: clientKey, hostKey: hostKey.publicKey, clientVersion: "1", deviceName: "phone")
            XCTFail("connect succeeded against protocol_mismatch")
        } catch let error as LinkClientError {
            XCTAssertEqual(error, .protocolMismatch(message: "update the app"))
        }
        try await rawHost.value
    }

    // MARK: - PROTOCOL.md section 6: oversize frames

    func testOversizeSnapshotIsShrunk() async throws {
        let feed = FakeFeedSource([permissionItem("a00", preview: String(repeating: "x", count: 20_000))])
        let client = try await connect(makeHost(feed))

        // Step 1: a single long preview is cut to 8192 bytes.
        var snap = try await within { try await client.snapshot() }
        XCTAssertEqual(snap.pending.first?.toolInputPreview?.utf8.count, 8192)

        // Step 2: ten 8000-byte previews do not fit at 8192, so all are cut to 1024.
        feed.add((1...9).map { permissionItem(String(format: "a%02d", $0), preview: String(repeating: "y", count: 8000)) })
        snap = try await within { try await client.snapshot() }
        XCTAssertEqual(snap.pending.count, 10)
        XCTAssertEqual(Set(snap.pending.map { $0.toolInputPreview?.utf8.count }), [1024])

        // Step 3: sixty items do not fit even at 1024, so previews are omitted.
        feed.add((10...59).map { permissionItem(String(format: "a%02d", $0), preview: String(repeating: "z", count: 2000)) })
        snap = try await within { try await client.snapshot() }
        XCTAssertEqual(snap.pending.count, 60)
        XCTAssertTrue(snap.pending.allSatisfy { $0.toolInputPreview == nil })
        XCTAssertEqual(snap.pending.first?.toolName, "Bash")
    }

    func testOversizeChangedIsShrunk() async throws {
        let feed = FakeFeedSource()
        let client = try await connect(makeHost(feed))
        let seen = collect(client.changes)
        feed.add((0..<10).map { permissionItem("b\($0)", preview: String(repeating: "q", count: 8000)) })
        let arrived = await eventually { !seen.items.isEmpty }
        XCTAssertTrue(arrived, "an oversize agent.changed was not sent")
        let added = seen.items.first?.added ?? []
        XCTAssertEqual(added.count, 10)
        XCTAssertEqual(Set(added.map { $0.toolInputPreview?.utf8.count }), [1024])
    }

    // MARK: - PROTOCOL.md section 2: empty handshake payloads

    func testNonEmptyHandshakePayloadAborts() async throws {
        let hostKey = NoiseStaticKey()
        let clientKey = NoiseStaticKey()
        let (clientEnd, hostEnd) = makeInMemoryCircuitPair()
        let responder = Task {
            try await SecureChannel.open(hostEnd, role: .responder, key: hostKey, trusts: { _ in true })
        }
        var handshake = NoiseHandshake(role: .initiator, local: clientKey, trusts: { _ in true })
        try await clientEnd.send(handshake.writeMessage(payload: Data("hi".utf8)))
        do {
            _ = try await responder.value
            XCTFail("responder accepted a non-empty handshake payload")
        } catch {
            XCTAssertEqual(error as? SecureChannelError, .nonEmptyHandshakePayload)
        }
        do {
            _ = try await clientEnd.receive()
            XCTFail("circuit stayed open after the handshake was aborted")
        } catch {}
    }

    // MARK: - Request timeout

    func testDroppedSnapshotTimesOutAndSessionStaysUsable() async throws {
        // One item that does not fit in a frame even without its preview: the host must drop the
        // snapshot (PROTOCOL.md section 6) and the client must not wait forever.
        let huge = PendingItem(
            requestId: "huge", kind: .permission, agent: "claude", workspaceId: "ws-1",
            workspaceTitle: String(repeating: "w", count: 70_000), createdAtMs: 1)
        let feed = FakeFeedSource([huge])
        let quickRequests = LinkTimings(
            pingInterval: .seconds(20), idleTimeout: .seconds(45), requestTimeout: .milliseconds(200))
        let rig = makeHost(feed)
        let (end, served) = startServe(rig.host)
        let client = try await connectClient(end, rig, timings: quickRequests)

        let start = ContinuousClock.now
        do {
            _ = try await within { try await client.snapshot() }
            XCTFail("a dropped snapshot was answered")
        } catch {
            XCTAssertEqual(error as? LinkClientError, .timedOut, "unexpected error \(error)")
        }
        let waited = ContinuousClock.now - start
        XCTAssertGreaterThanOrEqual(waited, .milliseconds(150))
        XCTAssertLessThan(waited, .seconds(3))

        feed.resolveLocally(requestId: "huge")
        feed.add(permissionItem("r1"))
        let snap = try await within { try await client.snapshot() }
        XCTAssertEqual(snap.pending.map(\.requestId), ["r1"])
        let outcome = try await within { try await client.reply(requestId: "r1", mode: .once) }
        XCTAssertEqual(outcome, .delivered)
        XCTAssertFalse(served.isSet)
    }

    func testLateReplyResultIsNotGivenToNewerReply() async throws {
        let hostKey = NoiseStaticKey()
        let clientKey = NoiseStaticKey()
        let (clientEnd, hostEnd) = makeInMemoryCircuitPair()
        // A slow host: it answers the first reply only after the client gave up on it.
        let rawHost = Task {
            let ch = try await SecureChannel.open(hostEnd, role: .responder, key: hostKey, trusts: { _ in true })
            _ = try await ch.receive()
            try await ch.send(.welcome(protocolVersion: 1, hostVersion: "test", machineName: "mac"))
            guard case .reply = try await ch.receive() else { throw RelayError.closed }
            // 500 ms after the first call's 1 s timeout, 500 ms before the retry's.
            try await Task.sleep(for: .milliseconds(1500))
            try await ch.send(.replyResult(requestId: "r1", outcome: .delivered))
            guard case .reply = try await ch.receive() else { throw RelayError.closed }
            try await ch.send(.replyResult(requestId: "r1", outcome: .alreadyHandled))
        }
        let client = try await LinkClient.connect(
            clientEnd, key: clientKey, hostKey: hostKey.publicKey, clientVersion: "1", deviceName: "phone",
            timings: LinkTimings(pingInterval: .seconds(20), idleTimeout: .seconds(45), requestTimeout: .seconds(1)))
        clients.append(client)

        do {
            _ = try await within { try await client.reply(requestId: "r1", mode: .deny) }
            XCTFail("the slow reply did not time out")
        } catch {
            XCTAssertEqual(error as? LinkClientError, .timedOut, "unexpected error \(error)")
        }
        let retry = try await within { try await client.reply(requestId: "r1", mode: .once) }
        XCTAssertEqual(retry, .alreadyHandled, "the late result of the first reply reached the retry")
        try await rawHost.value
    }

    func testRepliesToOneRequestKeepTheirOwnOutcome() async throws {
        // The first reply waits on a slow hook past the client's timeout; the retry would be
        // answered at once if the host let it overtake.
        let feed = SlowFirstReplyFeed(
            FakeFeedSource([permissionItem("r1")]), slowIds: ["r1"], delay: .milliseconds(1500))
        let rig = makeHost(feed)
        let (end, _) = startServe(rig.host)
        let client = try await connectClient(
            end, rig,
            timings: LinkTimings(pingInterval: .seconds(20), idleTimeout: .seconds(45), requestTimeout: .seconds(1)))

        do {
            _ = try await within { try await client.reply(requestId: "r1", mode: .deny) }
            XCTFail("the slow reply did not time out")
        } catch {
            XCTAssertEqual(error as? LinkClientError, .timedOut, "unexpected error \(error)")
        }
        let retry = try await within { try await client.reply(requestId: "r1", mode: .once) }

        let answers = feed.answers
        XCTAssertEqual(answers.map(\.mode), [.deny, .once], "the retry overtook the first reply")
        XCTAssertEqual(retry, answers.first { $0.mode == .once }?.outcome, "the retry got another reply's outcome")
        XCTAssertEqual(retry, .alreadyHandled)
    }

    func testRepliesToDifferentRequestsRunConcurrently() async throws {
        let feed = SlowFirstReplyFeed(
            FakeFeedSource([permissionItem("slow"), permissionItem("fast")]), slowIds: ["slow"],
            delay: .milliseconds(1500))
        let client = try await connect(makeHost(feed))
        let slow = Task { try await within { try await client.reply(requestId: "slow", mode: .once) } }
        try await Task.sleep(for: .milliseconds(50))
        let start = ContinuousClock.now
        let fast = try await within { try await client.reply(requestId: "fast", mode: .once) }
        XCTAssertEqual(fast, .delivered)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(1), "a slow reply blocked another request")
        let slowOutcome = try await slow.value
        XCTAssertEqual(slowOutcome, .delivered)
    }

    // MARK: - Liveness

    func testWatchdogClosesSilentSession() async throws {
        let fast = LinkTimings(pingInterval: .milliseconds(50), idleTimeout: .milliseconds(300))
        let rig = makeHost(FakeFeedSource(), timings: fast)
        let (end, served) = startServe(rig.host)
        _ = try await rawEstablished(end, rig)
        let start = ContinuousClock.now
        // The raw peer never answers pings, so the host hears nothing and must close.
        let ended = await eventually(within: .seconds(3)) { served.isSet }
        XCTAssertTrue(ended, "the host kept a silent session open")
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - start, .milliseconds(250))
    }

    func testPingsKeepIdleSessionAlive() async throws {
        let fast = LinkTimings(pingInterval: .milliseconds(50), idleTimeout: .milliseconds(300))
        let feed = FakeFeedSource([permissionItem("r1")])
        let rig = makeHost(feed, timings: fast)
        let (end, served) = startServe(rig.host)
        let client = try await connectClient(end, rig, timings: fast)
        try await Task.sleep(for: .seconds(1))
        XCTAssertFalse(served.isSet, "the session died although both sides were pinging")
        let snap = try await within { try await client.snapshot() }
        XCTAssertEqual(snap.pending.map(\.requestId), ["r1"])
    }

    // MARK: - Feed subscription lifetime

    func testSessionEndReleasesFeedSubscription() async throws {
        let feed = FakeFeedSource([permissionItem("r1")])
        let rig = makeHost(feed)
        let (end, served) = startServe(rig.host)
        let client = try await connectClient(end, rig)
        _ = try await within { try await client.snapshot() }
        XCTAssertEqual(feed.activeSubscribers, 1)
        await client.close()
        let ended = await eventually { served.isSet }
        XCTAssertTrue(ended)
        let released = await eventually { feed.activeSubscribers == 0 }
        XCTAssertTrue(released, "the host leaked its changes() subscription")
        XCTAssertEqual(feed.changesCalls, 1)
    }

    // MARK: - Helpers

    private struct Rig {
        let host: LinkHost
        let hostKey: NoiseStaticKey
        let clientKeys: [NoiseStaticKey]
    }

    private func makeHost(
        _ feed: any AgentFeedSource, clientCount: Int = 1, trustClients: Bool = true, timings: LinkTimings = .standard,
        machineName: String = "Test Mac"
    ) -> Rig {
        let hostKey = NoiseStaticKey()
        let clientKeys = (0..<clientCount).map { _ in NoiseStaticKey() }
        let trusted: Set<Data> = trustClients ? Set(clientKeys.map(\.publicKey)) : []
        let host = LinkHost(
            key: hostKey, trustedClients: { trusted }, feed: feed, hostVersion: "test-host", machineName: machineName,
            timings: timings)
        return Rig(host: host, hostKey: hostKey, clientKeys: clientKeys)
    }

    /// Serves one new circuit; returns the client end and a flag set when `serve` returns.
    private func startServe(_ host: LinkHost) -> (any RelayCircuit, Flag) {
        let (clientEnd, hostEnd) = makeInMemoryCircuitPair()
        let done = Flag()
        serveTasks.append(Task {
            await host.serve(hostEnd)
            done.set()
        })
        return (clientEnd, done)
    }

    private func connect(_ rig: Rig, clientIndex: Int = 0) async throws -> LinkClient {
        let (end, _) = startServe(rig.host)
        return try await connectClient(end, rig, clientIndex: clientIndex)
    }

    private func connectClient(
        _ end: any RelayCircuit, _ rig: Rig, clientIndex: Int = 0, timings: LinkTimings = .standard
    ) async throws -> LinkClient {
        let client = try await LinkClient.connect(
            end, key: rig.clientKeys[clientIndex], hostKey: rig.hostKey.publicKey, clientVersion: "test-client",
            deviceName: "Test Phone", timings: timings)
        clients.append(client)
        return client
    }

    private func rawChannel(_ end: any RelayCircuit, _ rig: Rig) async throws -> SecureChannel {
        let hostPublic = rig.hostKey.publicKey
        return try await SecureChannel.open(end, role: .initiator, key: rig.clientKeys[0], trusts: { $0 == hostPublic })
    }

    /// A raw channel past `hello` / `welcome`.
    private func rawEstablished(_ end: any RelayCircuit, _ rig: Rig) async throws -> SecureChannel {
        let raw = try await rawChannel(end, rig)
        try await raw.send(.hello(clientVersion: "raw", deviceName: "raw"))
        let welcome = try await raw.receive()
        XCTAssertEqual(welcome, .welcome(protocolVersion: 1, hostVersion: "test-host", machineName: "Test Mac"))
        return raw
    }

    private func errorCode(_ message: LinkMessage) -> String? {
        guard case let .error(code, _) = message else { return nil }
        return code
    }

    private func assertClosed(_ channel: SecureChannel, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            let extra = try await channel.receive()
            XCTFail("expected the host to close, got \(extra)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? RelayError, .closed, file: file, line: line)
        }
    }
}

// MARK: - Test utilities

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

final class Collector<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Element] = []
    var items: [Element] { lock.withLock { stored } }
    func append(_ element: Element) { lock.withLock { stored.append(element) } }
}

/// Collects every element of `stream` in the background. The stream is never cancelled, because
/// cancelling an `AsyncStream` iteration would end the stream itself.
func collect<Element: Sendable>(_ stream: AsyncStream<Element>) -> Collector<Element> {
    let collector = Collector<Element>()
    Task {
        for await element in stream { collector.append(element) }
    }
    return collector
}

struct TimedOut: Error {}

/// Runs `operation`, cancelling it and throwing `TimedOut` after `timeout`, so a lost answer
/// fails the test instead of hanging it.
func within<T: Sendable>(
    _ timeout: Duration = .seconds(5), _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw TimedOut()
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw TimedOut() }
        return result
    }
}

/// Polls `condition` until it holds or `within` has passed.
func eventually(within timeout: Duration = .seconds(2), _ condition: @Sendable () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
