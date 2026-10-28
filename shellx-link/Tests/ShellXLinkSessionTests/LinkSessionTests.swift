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
        let outcome = try await within { try await client.reply(requestId: "r1", decision: .permission(.once)) }
        XCTAssertEqual(outcome, .delivered)
        XCTAssertEqual(feed.replies.map(\.requestId), ["r1"])
        XCTAssertEqual(feed.replies.first?.decision, .permission(.once))
    }

    func testReplyTwiceIsAlreadyHandled() async throws {
        let feed = FakeFeedSource([permissionItem("r1")])
        let client = try await connect(makeHost(feed))
        let first = try await within { try await client.reply(requestId: "r1", decision: .permission(.once)) }
        let second = try await within { try await client.reply(requestId: "r1", decision: .permission(.once)) }
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

        let outcome = try await within { try await clientA.reply(requestId: "r1", decision: .permission(.always)) }
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

    func testDisconnectClosesLiveSessionsOfKey() async throws {
        let feed = FakeFeedSource([permissionItem("r1")])
        let rig = makeHost(feed, clientCount: 2)
        let clientA = try await connect(rig, clientIndex: 0)
        let clientB = try await connect(rig, clientIndex: 1)
        _ = try await within { try await clientA.snapshot() }
        _ = try await within { try await clientB.snapshot() }

        await rig.host.disconnect(clientKey: rig.clientKeys[0].publicKey)

        do {
            _ = try await within { try await clientA.snapshot() }
            XCTFail("the disconnected client still got an answer")
        } catch {
            XCTAssertEqual(error as? LinkClientError, .sessionClosed, "unexpected error \(error)")
        }
        let other = try await within { try await clientB.snapshot() }
        XCTAssertEqual(other.pending.map(\.requestId), ["r1"])
    }

    func testHandshakeRejectedAfterUntrust() async throws {
        let feed = FakeFeedSource([permissionItem("r1")])
        let clientKey = NoiseStaticKey()
        let hostKey = NoiseStaticKey()
        let trusted = Collector<Set<Data>>()
        trusted.append([clientKey.publicKey])
        let host = LinkHost(
            key: hostKey, trustedClients: { trusted.items.last ?? [] }, feed: feed, hostVersion: "test-host",
            machineName: "Test Mac")
        let rig = Rig(host: host, hostKey: hostKey, clientKeys: [clientKey])
        let first = try await connect(rig)
        _ = try await within { try await first.snapshot() }

        trusted.append([])
        await host.disconnect(clientKey: clientKey.publicKey)

        do {
            _ = try await connect(rig)
            XCTFail("connect succeeded after the key was untrusted")
        } catch {
            XCTAssertEqual(error as? RelayError, .closed, "unexpected error \(error)")
        }
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
            guard case let .welcome(_, _, name, _) = first, name == machineName else {
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
        try await raw.send(.snapshotGet(callId: "c1"))
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
            try await ch.send(.welcome(protocolVersion: 1, hostVersion: "test", machineName: "mac", features: []))
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
            try await ch.send(.error(code: "protocol_mismatch", message: "update the app", callId: nil))
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

    func testOversizedSnapshotAnswersTooLargeAndSessionStaysUsable() async throws {
        // One item that does not fit in a frame even without its preview: the host answers the call
        // with `error` `too_large` (PROTOCOL.md section 6) instead of leaving it unanswered.
        let huge = PendingItem(
            requestId: "huge", kind: .permission, agent: "claude", workspaceId: "ws-1",
            workspaceTitle: String(repeating: "w", count: 70_000), createdAtMs: 1)
        let feed = FakeFeedSource([huge])
        let quickRequests = LinkTimings(
            pingInterval: .seconds(20), idleTimeout: .seconds(45), requestTimeout: .milliseconds(200))
        let rig = makeHost(feed)
        let (end, served) = startServe(rig.host)
        let client = try await connectClient(end, rig, timings: quickRequests)

        do {
            _ = try await within { try await client.snapshot() }
            XCTFail("an oversized snapshot was answered")
        } catch {
            guard case let .remote(code, _)? = error as? LinkClientError else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(code, "too_large")
        }

        feed.resolveLocally(requestId: "huge")
        feed.add(permissionItem("r1"))
        let snap = try await within { try await client.snapshot() }
        XCTAssertEqual(snap.pending.map(\.requestId), ["r1"])
        let outcome = try await within { try await client.reply(requestId: "r1", decision: .permission(.once)) }
        XCTAssertEqual(outcome, .delivered)
        XCTAssertFalse(served.isSet)
    }

    func testReplyCarriesCallIdAndResultMatches() async throws {
        let hostKey = NoiseStaticKey()
        let clientKey = NoiseStaticKey()
        let (clientEnd, hostEnd) = makeInMemoryCircuitPair()
        let seen = Collector<LinkMessage>()
        let rawHost = Task {
            let ch = try await SecureChannel.open(hostEnd, role: .responder, key: hostKey, trusts: { _ in true })
            _ = try await ch.receive()
            try await ch.send(.welcome(protocolVersion: 1, hostVersion: "test", machineName: "mac", features: []))
            for _ in 0..<2 {
                let message = try await ch.receive()
                seen.append(message)
                guard case let .reply(callId, requestId, _) = message else { throw RelayError.closed }
                try await ch.send(.replyResult(callId: callId, requestId: requestId, outcome: .delivered))
            }
        }
        let client = try await LinkClient.connect(
            clientEnd, key: clientKey, hostKey: hostKey.publicKey, clientVersion: "1", deviceName: "phone",
            timings: .standard)
        clients.append(client)
        let a = try await within { try await client.reply(requestId: "r1", decision: .permission(.once)) }
        let b = try await within { try await client.reply(requestId: "r1", decision: .permission(.deny)) }
        XCTAssertEqual([a, b], [.delivered, .delivered])
        try await rawHost.value
        let callIds = seen.items.compactMap { message -> String? in
            if case let .reply(callId, _, _) = message { return callId }
            return nil
        }
        XCTAssertEqual(callIds.count, 2)
        XCTAssertEqual(Set(callIds).count, 2, "call ids must be unique")
        XCTAssertTrue(callIds.allSatisfy { (1...LinkCodec.maxCallIdBytes).contains($0.utf8.count) })
    }

    func testLateResultOfTimedOutCallIsDropped() async throws {
        // The host answers the first call after the client gave up on it, in front of the answer to
        // the second call: the late answer carries the first call's id and must not reach the second.
        let hostKey = NoiseStaticKey()
        let clientKey = NoiseStaticKey()
        let (clientEnd, hostEnd) = makeInMemoryCircuitPair()
        let rawHost = Task {
            let ch = try await SecureChannel.open(hostEnd, role: .responder, key: hostKey, trusts: { _ in true })
            _ = try await ch.receive()
            try await ch.send(.welcome(protocolVersion: 1, hostVersion: "test", machineName: "mac", features: []))
            guard case let .reply(first, _, _) = try await ch.receive() else { throw RelayError.closed }
            guard case let .reply(second, _, _) = try await ch.receive() else { throw RelayError.closed }
            try await ch.send(.replyResult(callId: first, requestId: "r1", outcome: .delivered))
            try await ch.send(.replyResult(callId: second, requestId: "r1", outcome: .alreadyHandled))
        }
        let client = try await LinkClient.connect(
            clientEnd, key: clientKey, hostKey: hostKey.publicKey, clientVersion: "1", deviceName: "phone",
            timings: LinkTimings(pingInterval: .seconds(20), idleTimeout: .seconds(45), requestTimeout: .seconds(1)))
        clients.append(client)

        do {
            _ = try await within { try await client.reply(requestId: "r1", decision: .permission(.deny)) }
            XCTFail("the unanswered reply did not time out")
        } catch {
            XCTAssertEqual(error as? LinkClientError, .timedOut, "unexpected error \(error)")
        }
        let retry = try await within { try await client.reply(requestId: "r1", decision: .permission(.once)) }
        XCTAssertEqual(retry, .alreadyHandled, "the late result of the first call reached the second")
        try await rawHost.value
    }

    func testHostEchoesCallIdOnBadRequest() async throws {
        let rig = makeHost(FakeFeedSource())
        let (end, _) = startServe(rig.host)
        let raw = try await rawEstablished(end, rig)
        // A reply without `request_id`: undecodable, but its call_id is readable.
        try await raw.send(frame: Data(#"{"v":1,"t":"agent.reply","call_id":"c9","decision":{"kind":"permission","mode":"once"}}"#.utf8))
        let received = try await within { try await raw.receive() }
        guard case let .error(code, _, callId) = received else {
            return XCTFail("expected an error")
        }
        XCTAssertEqual(code, "bad_request")
        XCTAssertEqual(callId, "c9")
        // Without a readable call_id the error carries none, and the session stays usable.
        try await raw.send(frame: Data(#"{"v":1,"t":"agent.reply","request_id":"r"}"#.utf8))
        let second = try await within { try await raw.receive() }
        guard case let .error(_, _, noId) = second else {
            return XCTFail("expected an error")
        }
        XCTAssertNil(noId)
        try await raw.send(.snapshotGet(callId: "c10"))
        let third = try await within { try await raw.receive() }
        guard case let .snapshot(answerId, _, _) = third else {
            return XCTFail("expected a snapshot")
        }
        XCTAssertEqual(answerId, "c10")
    }

    /// A call this host predates (a newer phone's method) is answered `unsupported` with its `call_id`, so the phone
    /// fails it at once instead of waiting 10 s; an unknown frame without a valid `call_id` stays ignored.
    func testUnknownCallIsAnsweredUnsupported() async throws {
        let rig = makeHost(FakeFeedSource())
        let (end, served) = startServe(rig.host)
        let raw = try await rawEstablished(end, rig)
        try await raw.send(frame: Data(#"{"v":1,"t":"future.notice","x":1}"#.utf8))
        let tooLong = String(repeating: "c", count: LinkCodec.maxCallIdBytes + 1)
        try await raw.send(frame: Data(#"{"v":1,"t":"future.call","call_id":"\#(tooLong)"}"#.utf8))
        try await raw.send(frame: Data(#"{"v":1,"t":"future.call","call_id":"f1","x":[1,2]}"#.utf8))
        let answer = try await within(.seconds(2)) { try await raw.receive() }
        guard case let .error(code, _, callId) = answer else { return XCTFail("expected an error, got \(answer)") }
        XCTAssertEqual(code, "unsupported")
        XCTAssertEqual(callId, "f1", "only the frame with a valid call_id is answered")
        // Nothing else was answered, and the session stays usable.
        try await raw.send(.ping(nonce: 3))
        let pong = try await within(.seconds(2)) { try await raw.receive() }
        XCTAssertEqual(pong, .pong(nonce: 3))
        XCTAssertFalse(served.isSet)
    }

    func testRemoteErrorWithCallIdFailsOnlyThatCall() async throws {
        let hostKey = NoiseStaticKey()
        let clientKey = NoiseStaticKey()
        let (clientEnd, hostEnd) = makeInMemoryCircuitPair()
        let rawHost = Task {
            let ch = try await SecureChannel.open(hostEnd, role: .responder, key: hostKey, trusts: { _ in true })
            _ = try await ch.receive()
            try await ch.send(.welcome(protocolVersion: 1, hostVersion: "test", machineName: "mac", features: []))
            guard case let .reply(callId, _, _) = try await ch.receive() else { throw RelayError.closed }
            try await ch.send(.error(code: "bad_request", message: "nope", callId: callId))
            guard case let .snapshotGet(next) = try await ch.receive() else { throw RelayError.closed }
            try await ch.send(.snapshot(callId: next, revision: 3, pending: []))
        }
        let client = try await LinkClient.connect(
            clientEnd, key: clientKey, hostKey: hostKey.publicKey, clientVersion: "1", deviceName: "phone",
            timings: .standard)
        clients.append(client)
        do {
            _ = try await within { try await client.reply(requestId: "r1", decision: .permission(.once)) }
            XCTFail("the error did not fail the call")
        } catch {
            XCTAssertEqual(error as? LinkClientError, .remote(code: "bad_request", message: "nope"))
        }
        let snap = try await within { try await client.snapshot() }
        XCTAssertEqual(snap.revision, 3)
        try await rawHost.value
    }

    func testQuestionDecisionReachesFeed() async throws {
        let feed = FakeFeedSource([permissionItem("q1")])
        let client = try await connect(makeHost(feed))
        let outcome = try await within {
            try await client.reply(requestId: "q1", decision: .question(selections: ["Blue", "Green"]))
        }
        XCTAssertEqual(outcome, .delivered)
        XCTAssertEqual(feed.replies.first?.decision, .question(selections: ["Blue", "Green"]))
    }

    func testExitPlanDecisionCarriesFeedback() async throws {
        let feed = FakeFeedSource([permissionItem("p1")])
        let client = try await connect(makeHost(feed))
        let outcome = try await within {
            try await client.reply(requestId: "p1", decision: .exitPlan(.manual, feedback: "add tests \u{1F680}"))
        }
        XCTAssertEqual(outcome, .delivered)
        XCTAssertEqual(feed.replies.first?.decision, .exitPlan(.manual, feedback: "add tests \u{1F680}"))
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
            _ = try await within { try await client.reply(requestId: "r1", decision: .permission(.deny)) }
            XCTFail("the slow reply did not time out")
        } catch {
            XCTAssertEqual(error as? LinkClientError, .timedOut, "unexpected error \(error)")
        }
        let retry = try await within { try await client.reply(requestId: "r1", decision: .permission(.once)) }

        let answers = feed.answers
        XCTAssertEqual(answers.map(\.decision), [.permission(.deny), .permission(.once)], "the retry overtook the first reply")
        XCTAssertEqual(retry, answers.first { $0.decision == .permission(.once) }?.outcome, "the retry got another reply's outcome")
        XCTAssertEqual(retry, .alreadyHandled)
    }

    func testRepliesToDifferentRequestsRunConcurrently() async throws {
        let feed = SlowFirstReplyFeed(
            FakeFeedSource([permissionItem("slow"), permissionItem("fast")]), slowIds: ["slow"],
            delay: .milliseconds(1500))
        let client = try await connect(makeHost(feed))
        let slow = Task { try await within { try await client.reply(requestId: "slow", decision: .permission(.once)) } }
        try await Task.sleep(for: .milliseconds(50))
        let start = ContinuousClock.now
        let fast = try await within { try await client.reply(requestId: "fast", decision: .permission(.once)) }
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

    // MARK: - Agent sessions and chat (PROTOCOL.md sections 4 and 6)

    func testSessionsSnapshotThenChanges() async throws {
        let sessions = FakeSessionSource([agentSession("s1", title: "Fix relay")])
        let client = try await connect(makeHost(FakeFeedSource(), sessions: sessions))
        let snap = try await within { try await client.sessions() }
        XCTAssertEqual(snap.revision, 0)
        XCTAssertEqual(snap.sessions, [agentSession("s1", title: "Fix relay")])

        let seen = collect(client.sessionChanges)
        sessions.upsert(agentSession("s2", state: .working))
        sessions.remove("s1")
        let arrived = await eventually { seen.items.count == 2 }
        XCTAssertTrue(arrived, "agent.sessions.changed did not arrive")
        XCTAssertEqual(seen.items.map(\.revision), [1, 2])
        XCTAssertEqual(seen.items.first?.upserted.map(\.sessionId), ["s2"])
        XCTAssertEqual(seen.items.first?.upserted.first?.state, .working)
        XCTAssertEqual(seen.items.last?.removed, ["s1"])
        let after = try await within { try await client.sessions() }
        XCTAssertEqual(after.revision, 2)
        XCTAssertEqual(after.sessions.map(\.sessionId), ["s2"])
    }

    func testSessionChangeGapForcesResync() async throws {
        let sessions = FakeSessionSource([agentSession("s1")])
        let client = try await connect(makeHost(FakeFeedSource(), sessions: sessions))
        let first = try await within { try await client.sessions() }
        let seen = collect(client.sessionChanges)

        // The source raised its revision once without a change reaching the phone: the next change
        // is two above the phone's current one, which means it missed one (section 4).
        sessions.skipRevision()
        sessions.upsert(agentSession("s2"))
        let arrived = await eventually { !seen.items.isEmpty }
        XCTAssertTrue(arrived)
        XCTAssertEqual(seen.items.first?.revision, first.revision + 2)

        let resynced = try await within { try await client.sessions() }
        XCTAssertEqual(resynced.revision, 2)
        XCTAssertEqual(resynced.sessions.map(\.sessionId), ["s1", "s2"])
    }

    func testChatHistoryRoundTrip() async throws {
        let transcript = (1...5).map { chatEntry($0) }
        let chat = FakeChatSource(["s1": transcript])
        let client = try await connect(makeHost(FakeFeedSource(), chat: chat))
        let latest = try await within { try await client.chatHistory(sessionId: "s1", beforeSeq: nil, limit: 3) }
        XCTAssertEqual(latest.entries.map(\.seq), [3, 4, 5])
        XCTAssertTrue(latest.hasMore)
        let older = try await within { try await client.chatHistory(sessionId: "s1", beforeSeq: 3, limit: 3) }
        XCTAssertEqual(older.entries, Array(transcript.prefix(2)))
        XCTAssertFalse(older.hasMore)
    }

    func testHistoryPageShrinksToFit() async throws {
        let text = String(repeating: "h", count: ChatEntry.maxTextBytes)
        let transcript = (1...50).map { chatEntry($0, text: text) }
        let chat = FakeChatSource(["s1": transcript])
        let rig = makeHost(FakeFeedSource(), chat: chat)
        let (end, _) = startServe(rig.host)
        let raw = try await rawEstablished(end, rig)
        try await raw.send(.chatHistoryGet(callId: "h1", sessionId: "s1", beforeSeq: nil, limit: 50))
        let answer = try await within { try await raw.receive() }
        guard case let .chatHistory(callId, sessionId, entries, hasMore) = answer else {
            return XCTFail("unexpected answer \(answer)")
        }
        XCTAssertEqual(callId, "h1")
        XCTAssertEqual(sessionId, "s1")
        XCTAssertTrue(hasMore, "dropped entries must set has_more")
        XCTAssertFalse(entries.isEmpty)
        XCTAssertLessThan(entries.count, 50)
        // The oldest entries go first: what is left is the newest run, oldest to newest.
        XCTAssertEqual(entries.last?.seq, 50)
        XCTAssertEqual(entries.map(\.seq), Array((51 - entries.count)...50))
        XCTAssertLessThanOrEqual(try LinkCodec.encode(answer).count, LinkCodec.maxFrameBytes)
        // One more entry would not have fit.
        let oneMore = LinkMessage.chatHistory(
            callId: "h1", sessionId: "s1", entries: Array(transcript.suffix(entries.count + 1)), hasMore: true)
        XCTAssertThrowsError(try LinkCodec.encode(oneMore))
    }

    /// `groups` seqs of `size` entries each; the entries of one group share the seq.
    private func groupedTranscript(groups: Int, size: Int, textBytes: Int) -> [ChatEntry] {
        (1...groups).flatMap { seq in
            (0..<size).map { index in
                ChatEntry(
                    id: "e-\(seq)-\(index)", rev: 1, seq: seq, role: .agent, kind: .prose,
                    text: String(repeating: "g", count: textBytes), tsMs: 1_700_000_000_000 + Int64(seq))
            }
        }
    }

    func testHistoryPageNeverSplitsASeqGroup() async throws {
        let transcript = groupedTranscript(groups: 12, size: 4, textBytes: 3500)
        let chat = FakeChatSource(["s1": transcript])
        let client = try await connect(makeHost(FakeFeedSource(), chat: chat))
        // 48 entries (12 groups) are asked for; ~192 KB cannot fit one frame.
        var beforeSeq: Int?
        var served: [ChatEntry] = []
        var pages = 0
        while true {
            let before = beforeSeq
            let page = try await within { try await client.chatHistory(sessionId: "s1", beforeSeq: before, limit: 48) }
            XCTAssertFalse(page.entries.isEmpty)
            let counts = Dictionary(grouping: page.entries, by: \.seq).mapValues(\.count)
            for (seq, count) in counts { XCTAssertEqual(count, 4, "seq \(seq) is split") }
            if pages == 0 { XCTAssertTrue(page.hasMore, "dropped groups must set has_more") }
            served = page.entries + served
            pages += 1
            guard page.hasMore, let oldest = page.entries.map(\.seq).min() else { break }
            if let beforeSeq { XCTAssertLessThan(oldest, beforeSeq) }
            beforeSeq = oldest
            if pages > 20 { XCTFail("paging does not terminate"); break }
        }
        XCTAssertGreaterThan(pages, 1)
        XCTAssertEqual(served.map(\.id), transcript.map(\.id), "no entry skipped or repeated")
    }

    func testSingleOversizedGroupAnswersTooLarge() async throws {
        // 20 entries sharing one seq, 4096 bytes each after the cap: more than one frame.
        let group = (0..<20).map { index in
            ChatEntry(
                id: "big-\(index)", rev: 1, seq: 1, role: .agent, kind: .prose,
                text: String(repeating: "b", count: ChatEntry.maxTextBytes), tsMs: 1_700_000_000_000)
        }
        let chat = FakeChatSource(["s1": group])
        let client = try await connect(makeHost(FakeFeedSource(), chat: chat))
        do {
            _ = try await within { try await client.chatHistory(sessionId: "s1", beforeSeq: nil, limit: 20) }
            XCTFail("expected too_large")
        } catch let LinkClientError.remote(code, _) {
            XCTAssertEqual(code, "too_large")
        }
    }

    func testHostCapsOversizedEntryText() async throws {
        let huge = String(repeating: "\u{00E9}", count: 500_000)
        let chat = FakeChatSource(["s1": [chatEntry(1, text: huge)]])
        let client = try await connect(makeHost(FakeFeedSource(), chat: chat))
        let seen = collect(client.chatEntries)
        let page = try await within { try await client.chatHistory(sessionId: "s1", beforeSeq: nil, limit: 10) }
        XCTAssertEqual(page.entries.count, 1)
        XCTAssertTrue(page.entries.first?.truncated == true)
        XCTAssertLessThanOrEqual(page.entries.first?.text.utf8.count ?? .max, ChatEntry.maxTextBytes)
        XCTAssertFalse(page.hasMore)
        chat.append([chatEntry(2, text: huge)], to: "s1")
        let arrived = await eventually { !seen.items.isEmpty }
        XCTAssertTrue(arrived)
        XCTAssertTrue(seen.items.first?.entries.first?.truncated == true)
    }

    func testChatEntriesPushedToEveryClient() async throws {
        let chat = FakeChatSource(["s1": [chatEntry(1)]])
        let rig = makeHost(FakeFeedSource(), clientCount: 2, chat: chat)
        let clientA = try await connect(rig, clientIndex: 0)
        let clientB = try await connect(rig, clientIndex: 1)
        let seenByA = collect(clientA.chatEntries)
        let seenByB = collect(clientB.chatEntries)
        chat.append([chatEntry(2), chatEntry(3)], to: "s1")
        for (name, seen) in [("A", seenByA), ("B", seenByB)] {
            let arrived = await eventually { !seen.items.isEmpty }
            XCTAssertTrue(arrived, "client \(name) got no chat.entries")
            XCTAssertEqual(seen.items.first?.sessionId, "s1")
            XCTAssertEqual(seen.items.first?.entries.map(\.seq), [2, 3])
        }
    }

    /// A transcript the Mac replaced (a fork's oversized first read, `claude --resume` rotating the file) reaches
    /// the phone as a reset, in order with the session's entries: what came before it belongs to the old
    /// transcript, what follows to the new one, and a fresh history page is the new transcript.
    func testChatResetReachesTheClientInOrder() async throws {
        let chat = FakeChatSource(["s1": [chatEntry(1)]])
        let client = try await connect(makeHost(FakeFeedSource(), chat: chat))
        let seen = collect(client.chatEntries)
        chat.append([chatEntry(2)], to: "s1")
        chat.reset("s1", to: [chatEntry(0, text: "forked head")])
        chat.append([chatEntry(1, rev: 2, text: "new turn")], to: "s1")
        let arrived = await eventually { seen.items.count == 3 }
        XCTAssertTrue(arrived, "pushes: \(seen.items)")
        XCTAssertEqual(seen.items, [
            .upsert(sessionId: "s1", entries: [chatEntry(2)]),
            .reset(sessionId: "s1"),
            .upsert(sessionId: "s1", entries: [chatEntry(1, rev: 2, text: "new turn")]),
        ])
        // Read through the tuple-shaped accessors too: a reset is an empty upsert of its session.
        XCTAssertEqual(seen.items.map(\.sessionId), ["s1", "s1", "s1"])
        XCTAssertEqual(seen.items.map(\.entries.count), [1, 0, 1])
        let page = try await within { try await client.chatHistory(sessionId: "s1", beforeSeq: nil, limit: 10) }
        XCTAssertEqual(page.entries.map(\.text), ["forked head", "new turn"])
    }

    /// Until the host takes attachments (it offers no feature), every `attach.*` call is `unsupported` with its
    /// `call_id`, like a host without the feature; the host-only answers sent by a client are `bad_request`
    /// (PROTOCOL.md sections 5 and 7).
    func testAttachFramesAreUnsupportedOrMisdirected() async throws {
        let rig = makeHost(FakeFeedSource(), chat: FakeChatSource(["s1": []]))
        let (end, served) = startServe(rig.host)
        let raw = try await rawEstablished(end, rig)
        let calls: [(LinkMessage, String)] = [
            (.attachBegin(callId: "u1", kind: .image, name: "a.jpg", size: 3), "u1"),
            (.attachChunk(callId: "u2", attachmentId: "a1", offset: 0, data: Data([1, 2, 3])), "u2"),
            (.attachEnd(callId: "u3", attachmentId: "a1", sha256: Data(count: 32)), "u3"),
        ]
        for (call, expectedId) in calls {
            try await raw.send(call)
            let answer = try await within { try await raw.receive() }
            guard case let .error(code, _, callId) = answer else { return XCTFail("expected an error, got \(answer)") }
            XCTAssertEqual(code, "unsupported", "\(call)")
            XCTAssertEqual(callId, expectedId)
        }
        let misdirected: [(LinkMessage, String)] = [
            (.attachReady(callId: "m1", attachmentId: "a1"), "m1"),
            (.attachChunkResult(callId: "m2", attachmentId: "a1", received: 3), "m2"),
            (.attachEndResult(callId: "m3", attachmentId: "a1"), "m3"),
        ]
        for (frame, expectedId) in misdirected {
            try await raw.send(frame)
            let answer = try await within { try await raw.receive() }
            guard case let .error(code, _, callId) = answer else { return XCTFail("expected an error, got \(answer)") }
            XCTAssertEqual(code, "bad_request", "\(frame)")
            XCTAssertEqual(callId, expectedId)
        }
        // A message that names attachments is still sent as text: the attachments are not used yet.
        try await raw.send(.chatSend(callId: "u4", sessionId: "s1", text: "see this", attachments: ["a1"]))
        let sent = try await within { try await raw.receive() }
        XCTAssertEqual(sent, .chatSendResult(callId: "u4", outcome: .submitted))
        XCTAssertFalse(served.isSet)
    }

    /// A client resolves a waiting `attach.*` call with the host's answer, and ignores the client-only frames a
    /// host should never send.
    func testClientResolvesAttachAnswersAndIgnoresClientOnlyFrames() async throws {
        let hostKey = NoiseStaticKey()
        let clientKey = NoiseStaticKey()
        let (clientEnd, hostEnd) = makeInMemoryCircuitPair()
        let rawHost = Task {
            let ch = try await SecureChannel.open(hostEnd, role: .responder, key: hostKey, trusts: { _ in true })
            _ = try await ch.receive()
            try await ch.send(.welcome(protocolVersion: 1, hostVersion: "test", machineName: "mac", features: ["attachments"]))
            guard case let .attachBegin(first, _, _, _) = try await ch.receive() else { throw RelayError.closed }
            // Frames a host does not send are ignored; they do not answer the call.
            try await ch.send(.attachBegin(callId: first, kind: .file, name: "x", size: 1))
            try await ch.send(.attachChunk(callId: first, attachmentId: "a1", offset: 0, data: Data([1])))
            try await ch.send(.attachEnd(callId: first, attachmentId: "a1", sha256: Data(count: 32)))
            try await ch.send(.attachReady(callId: first, attachmentId: "a1"))
            guard case let .attachChunk(second, _, _, _) = try await ch.receive() else { throw RelayError.closed }
            try await ch.send(.attachChunkResult(callId: second, attachmentId: "a1", received: 1))
            guard case let .attachEnd(third, _, _) = try await ch.receive() else { throw RelayError.closed }
            try await ch.send(.attachEndResult(callId: third, attachmentId: "a1"))
        }
        let client = try await LinkClient.connect(
            clientEnd, key: clientKey, hostKey: hostKey.publicKey, clientVersion: "1", deviceName: "phone",
            timings: .standard)
        clients.append(client)
        let ready = try await within { try await client.call { .attachBegin(callId: $0, kind: .file, name: "x", size: 1) } }
        guard case .attachReady(_, "a1") = ready else { return XCTFail("unexpected answer \(ready)") }
        let chunk = try await within {
            try await client.call { .attachChunk(callId: $0, attachmentId: "a1", offset: 0, data: Data([1])) }
        }
        guard case .attachChunkResult(_, "a1", 1) = chunk else { return XCTFail("unexpected answer \(chunk)") }
        let end = try await within { try await client.call { .attachEnd(callId: $0, attachmentId: "a1", sha256: Data(count: 32)) } }
        guard case .attachEndResult(_, "a1") = end else { return XCTFail("unexpected answer \(end)") }
        try await rawHost.value
    }

    /// `chat.reset` is a host push: it goes out as its own frame, and a client that sends one gets `bad_request`.
    func testChatResetIsAHostPush() async throws {
        let chat = FakeChatSource(["s1": []])
        let rig = makeHost(FakeFeedSource(), chat: chat)
        let (end, served) = startServe(rig.host)
        let raw = try await rawEstablished(end, rig)
        chat.reset("s1", to: [])
        let pushed = try await within { try await raw.receive() }
        XCTAssertEqual(pushed, .chatReset(sessionId: "s1"))
        try await raw.send(.chatReset(sessionId: "s1"))
        let answer = try await within { try await raw.receive() }
        XCTAssertEqual(errorCode(answer), "bad_request")
        XCTAssertFalse(served.isSet)
    }

    func testOversizeChatEntriesSplitIntoFrames() async throws {
        let chat = FakeChatSource(["s1": []])
        let client = try await connect(makeHost(FakeFeedSource(), chat: chat))
        let seen = collect(client.chatEntries)
        let text = String(repeating: "p", count: ChatEntry.maxTextBytes)
        chat.append((1...40).map { chatEntry($0, text: text) }, to: "s1")
        let arrived = await eventually { seen.items.flatMap(\.entries).count == 40 }
        XCTAssertTrue(arrived, "split chat.entries lost entries")
        XCTAssertGreaterThan(seen.items.count, 1)
        XCTAssertEqual(seen.items.flatMap(\.entries).map(\.seq), Array(1...40))
    }

    func testChatSendAndInterruptOutcomes() async throws {
        let chat = FakeChatSource(["s1": [], "s2": [], "s3": []])
        chat.setSendOutcome(.busy, for: "s2")
        chat.setSendOutcome(.failed, for: "s3")
        chat.setInterruptOutcome(.failed, for: "s3")
        let client = try await connect(makeHost(FakeFeedSource(), chat: chat))

        let submitted = try await within { try await client.chatSend(sessionId: "s1", text: "go on") }
        let busy = try await within { try await client.chatSend(sessionId: "s2", text: "hi") }
        let failed = try await within { try await client.chatSend(sessionId: "s3", text: "hi") }
        let missing = try await within { try await client.chatSend(sessionId: "nope", text: "hi") }
        XCTAssertEqual([submitted, busy, failed, missing], [.submitted, .busy, .failed, .notFound])
        XCTAssertEqual(chat.sends.first?.text, "go on")

        let sent = try await within { try await client.chatInterrupt(sessionId: "s1", hard: false) }
        let hard = try await within { try await client.chatInterrupt(sessionId: "s1", hard: true) }
        let interruptFailed = try await within { try await client.chatInterrupt(sessionId: "s3", hard: false) }
        let interruptMissing = try await within { try await client.chatInterrupt(sessionId: "nope", hard: false) }
        XCTAssertEqual([sent, hard, interruptFailed, interruptMissing], [.sent, .sent, .failed, .notFound])
        XCTAssertEqual(chat.interrupts.map(\.hard), [false, true, false, false])
    }

    func testChatSendTextBoundsAreEnforced() async throws {
        let chat = FakeChatSource(["s1": []])
        let rig = makeHost(FakeFeedSource(), chat: chat)
        let (end, _) = startServe(rig.host)
        let raw = try await rawEstablished(end, rig)
        let tooLong = String(repeating: "t", count: 16_385)
        for (callId, text) in [("t1", ""), ("t2", tooLong)] {
            try await raw.send(.chatSend(callId: callId, sessionId: "s1", text: text, attachments: []))
            let answer = try await within { try await raw.receive() }
            XCTAssertEqual(errorCode(answer), "bad_request")
            guard case let .error(_, _, id) = answer else { return XCTFail("unexpected answer \(answer)") }
            XCTAssertEqual(id, callId)
        }
        let longest = String(repeating: "t", count: 16_384)
        try await raw.send(.chatSend(callId: "t3", sessionId: "s1", text: longest, attachments: []))
        let ok = try await within { try await raw.receive() }
        XCTAssertEqual(ok, .chatSendResult(callId: "t3", outcome: .submitted))
        for (callId, limit) in [("t4", 0), ("t5", 51)] {
            try await raw.send(.chatHistoryGet(callId: callId, sessionId: "s1", beforeSeq: nil, limit: limit))
            let answer = try await within { try await raw.receive() }
            XCTAssertEqual(errorCode(answer), "bad_request")
        }
        XCTAssertEqual(chat.sends.count, 1, "an out-of-range text reached the chat source")
    }

    func testMissingChatSourceAnswersUnsupported() async throws {
        let client = try await connect(makeHost(FakeFeedSource()))
        let calls: [(String, @Sendable () async throws -> Void)] = [
            ("sessions", { _ = try await client.sessions() }),
            ("history", { _ = try await client.chatHistory(sessionId: "s1", beforeSeq: nil, limit: 10) }),
            ("send", { _ = try await client.chatSend(sessionId: "s1", text: "x") }),
            ("interrupt", { _ = try await client.chatInterrupt(sessionId: "s1", hard: false) }),
        ]
        for (name, call) in calls {
            do {
                try await within { try await call() }
                XCTFail("\(name) was answered without a source")
            } catch {
                guard case let .remote(code, _)? = error as? LinkClientError else {
                    XCTFail("\(name): unexpected error \(error)")
                    continue
                }
                XCTAssertEqual(code, "unsupported", name)
            }
        }
        // The session stays usable.
        let snap = try await within { try await client.snapshot() }
        XCTAssertTrue(snap.pending.isEmpty)
    }

    func testUnknownSessionAnswersNotFound() async throws {
        let chat = FakeChatSource(["s1": [chatEntry(1)]])
        let client = try await connect(makeHost(FakeFeedSource(), chat: chat))
        do {
            _ = try await within { try await client.chatHistory(sessionId: "nope", beforeSeq: nil, limit: 10) }
            XCTFail("history of an unknown session was answered")
        } catch {
            guard case let .remote(code, _)? = error as? LinkClientError else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(code, "not_found")
        }
        let known = try await within { try await client.chatHistory(sessionId: "s1", beforeSeq: nil, limit: 10) }
        XCTAssertEqual(known.entries.map(\.seq), [1])
    }

    func testOversizedSessionsDropTitlesThenAnswerTooLarge() async throws {
        let many = (0..<300).map {
            agentSession(String(format: "s%03d", $0), title: String(repeating: "t", count: 400))
        }
        let sessions = FakeSessionSource(many)
        let client = try await connect(makeHost(FakeFeedSource(), sessions: sessions))
        let snap = try await within { try await client.sessions() }
        XCTAssertEqual(snap.sessions.count, 300)
        XCTAssertTrue(snap.sessions.allSatisfy { $0.title == nil }, "titles are dropped when the list does not fit")
        XCTAssertEqual(snap.sessions.first?.workspaceTitle, "shellx")

        sessions.upsert(agentSession("huge", workspaceTitle: String(repeating: "w", count: 70_000)))
        do {
            _ = try await within { try await client.sessions() }
            XCTFail("an oversized session list was answered")
        } catch {
            guard case let .remote(code, _)? = error as? LinkClientError else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(code, "too_large")
        }
    }

    func testSessionEndReleasesSessionAndChatSubscriptions() async throws {
        let sessions = FakeSessionSource()
        let chat = FakeChatSource()
        let rig = makeHost(FakeFeedSource(), sessions: sessions, chat: chat)
        let (end, served) = startServe(rig.host)
        let client = try await connectClient(end, rig)
        _ = try await within { try await client.sessions() }
        XCTAssertEqual(sessions.activeSubscribers, 1)
        XCTAssertEqual(chat.activeSubscribers, 1)
        await client.close()
        let ended = await eventually { served.isSet }
        XCTAssertTrue(ended)
        let released = await eventually { sessions.activeSubscribers == 0 && chat.activeSubscribers == 0 }
        XCTAssertTrue(released, "the host leaked a subscription")
    }

    func testAnswerOfAnotherTypeIsUnexpectedAnswerNotRemote() async throws {
        let hostKey = NoiseStaticKey()
        let clientKey = NoiseStaticKey()
        let (clientEnd, hostEnd) = makeInMemoryCircuitPair()
        let rawHost = Task {
            let ch = try await SecureChannel.open(hostEnd, role: .responder, key: hostKey, trusts: { _ in true })
            _ = try await ch.receive()
            try await ch.send(.welcome(protocolVersion: 1, hostVersion: "test", machineName: "mac", features: []))
            guard case let .snapshotGet(callId) = try await ch.receive() else { throw RelayError.closed }
            try await ch.send(.chatSendResult(callId: callId, outcome: .submitted))
        }
        let client = try await LinkClient.connect(
            clientEnd, key: clientKey, hostKey: hostKey.publicKey, clientVersion: "1", deviceName: "phone",
            timings: .standard)
        clients.append(client)
        do {
            _ = try await within { try await client.snapshot() }
            XCTFail("a chat.send.result answered a snapshot call")
        } catch {
            XCTAssertEqual(error as? LinkClientError, .unexpectedAnswer, "unexpected error \(error)")
        }
        try await rawHost.value
    }

    // MARK: - Helpers

    private struct Rig {
        let host: LinkHost
        let hostKey: NoiseStaticKey
        let clientKeys: [NoiseStaticKey]
    }

    private func makeHost(
        _ feed: any AgentFeedSource, clientCount: Int = 1, trustClients: Bool = true, timings: LinkTimings = .standard,
        machineName: String = "Test Mac", sessions: (any AgentSessionSource)? = nil, chat: (any AgentChatSource)? = nil
    ) -> Rig {
        let hostKey = NoiseStaticKey()
        let clientKeys = (0..<clientCount).map { _ in NoiseStaticKey() }
        let trusted: Set<Data> = trustClients ? Set(clientKeys.map(\.publicKey)) : []
        let host = LinkHost(
            key: hostKey, trustedClients: { trusted }, feed: feed, sessions: sessions, chat: chat, hostVersion: "test-host",
            machineName: machineName, timings: timings)
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
        XCTAssertEqual(welcome, .welcome(protocolVersion: 1, hostVersion: "test-host", machineName: "Test Mac", features: []))
        return raw
    }

    private func errorCode(_ message: LinkMessage) -> String? {
        guard case let .error(code, _, _) = message else { return nil }
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
