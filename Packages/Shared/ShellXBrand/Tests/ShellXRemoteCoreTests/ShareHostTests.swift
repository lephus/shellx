import CryptoKit
import Foundation
import XCTest
@testable import ShellXRemoteCore

// MARK: - Relay control codec

final class ShareRelayControlTests: XCTestCase {
    private func object(_ text: String) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary)
    }

    func testEncodesRegisterJoinPing() throws {
        XCTAssertEqual(try object(ShareRelayControl.register(protocol: 5, slot: "s1", ticket: "tk").encoded()),
                       ["type": "register", "protocol": 5, "slot": "s1", "ticket": "tk"])
        XCTAssertEqual(try object(ShareRelayControl.join(protocol: 5, slot: "s1", circuit: "c1", lane: "l1",
                                                         generation: 7, ticket: "jt", role: .daemon).encoded()),
                       ["type": "join", "protocol": 5, "slot": "s1", "circuit": "c1", "lane": "l1",
                        "generation": 7, "ticket": "jt", "role": "daemon"])
        XCTAssertEqual(try object(ShareRelayControl.ping(nonce: 3).encoded()), ["type": "ping", "nonce": 3])
    }

    func testDecodesRelayReplies() {
        XCTAssertEqual(ShareRelayControl.decode(#"{"type":"registered","lease_seconds":30}"#), .registered(leaseSeconds: 30))
        XCTAssertEqual(ShareRelayControl.decode(#"{"type":"incoming","circuit":"c","lane":"l","generation":18446744073709551615,"join_ticket":"o2.x"}"#),
                       .incoming(circuit: "c", lane: "l", generation: .max, joinTicket: "o2.x"))
        XCTAssertEqual(ShareRelayControl.decode(#"{"type":"ready","circuit":"c","lane":"l","generation":2}"#),
                       .ready(circuit: "c", lane: "l", generation: 2))
        XCTAssertEqual(ShareRelayControl.decode(#"{"type":"pong","nonce":9}"#), .pong(nonce: 9))
        XCTAssertEqual(ShareRelayControl.decode(#"{"type":"error","code":"lease-expired","message":"m","retryable":true}"#),
                       .error(code: "lease-expired", message: "m", retryable: true))
        XCTAssertNil(ShareRelayControl.decode(#"{"type":"registered"}"#))
        XCTAssertNil(ShareRelayControl.decode(#"{"type":"bogus"}"#))
        XCTAssertNil(ShareRelayControl.decode("not json"))
    }

    func testRoundTripsEveryCase() {
        let all: [ShareRelayControl] = [
            .register(protocol: 5, slot: "s", ticket: "t"), .registered(leaseSeconds: 30),
            .incoming(circuit: "c", lane: "l", generation: 1, joinTicket: "j"),
            .join(protocol: 5, slot: "s", circuit: "c", lane: "l", generation: 1, ticket: "j", role: .daemon),
            .ready(circuit: "c", lane: "l", generation: 1), .ping(nonce: 1), .pong(nonce: 1),
            .error(code: "x", message: "y", retryable: false),
        ]
        for c in all { XCTAssertEqual(ShareRelayControl.decode(c.encoded()), c) }
    }
}

// MARK: - Host

@MainActor
final class ShareHostTests: XCTestCase {
    nonisolated static let shareID = "k7f29qd1"
    nonisolated static let slot = "share-slot-1"
    nonisolated static let relayURL = URL(string: "wss://relay.test/v2/relay")!
    let secret = ShareSecret.random()
    var clock: ManualShareClock!
    var relay: FakeRelay!
    var tickets: FakeTickets!
    var source: FakeShareSource!

    override func setUp() async throws {
        clock = ManualShareClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        relay = FakeRelay()
        tickets = FakeTickets(clock: clock)
        source = FakeShareSource()
        source.panes = [SharePane(id: "p1", title: "zsh", kind: .terminal, cols: 80, rows: 24),
                        SharePane(id: "p2", title: "vim", kind: .terminal, cols: 100, rows: 30),
                        SharePane(id: "b1", title: "Docs", kind: .browser, cols: 0, rows: 0)]
        source.activePane = "p1"
        source.snapshots = ["p1": (80, 24, Data("\u{1b}[2Jp1-screen".utf8)),
                            "p2": (100, 30, Data("\u{1b}[2Jp2-screen".utf8))]
    }

    private func makeHost(permission: SharePermission = .view, expiresAt: Date? = nil) -> ShareHost {
        let clock = self.clock!
        return ShareHost(shareID: Self.shareID, slot: Self.slot, secret: secret, permission: permission,
                         expiresAt: expiresAt, source: source, tickets: tickets, sockets: relay,
                         clock: { clock.now }, sleeper: clock)
    }

    /// Starts the host and answers the first register.
    private func startRegistered(_ host: ShareHost) async throws -> FakeSocket {
        await host.start()
        let control = try await relay.socket(0)
        try await shareEventually { control.sentControls.count >= 1 }
        control.feed(.text(ShareRelayControl.registered(leaseSeconds: 30).encoded()))
        try await shareEventually { await host.isRegistered }
        return control
    }

    private func connectViewer(_ control: FakeSocket, circuit: String, label: String = "Safari · iPhone",
                               sendHello: Bool = true) async throws -> FakeViewer {
        let before = relay.count
        control.feed(.text(ShareRelayControl.incoming(circuit: circuit, lane: "lane-\(circuit)", generation: 1,
                                                       joinTicket: "o2.join-\(circuit)").encoded()))
        try await shareEventually { self.relay.count > before }
        let socket = try await relay.socket(before)
        try await shareEventually { !socket.sentControls.isEmpty }
        socket.feed(.text(ShareRelayControl.ready(circuit: circuit, lane: "lane-\(circuit)", generation: 1).encoded()))
        let keys = secret.keys(shareID: Self.shareID)
        let viewer = FakeViewer(socket: socket, cipher: ShareCipher(sendKey: keys.viewerToHost,
                                                                    receiveKey: keys.hostToViewer, circuit: circuit))
        if sendHello {
            viewer.send(.hello(nonce: viewer.nonce, label: label))
            try await shareEventually { viewer.messages().count >= 2 } // welcome + replay
        }
        return viewer
    }

    func testRegistersOnShareSlot() async throws {
        let host = makeHost()
        let control = try await startRegistered(host)
        XCTAssertEqual(control.url, Self.relayURL)
        XCTAssertEqual(control.sentControls.first,
                       .register(protocol: 5, slot: Self.slot, ticket: "ticket-1"))
        XCTAssertEqual(tickets.requested, [Self.shareID])
        await host.stop(reason: .revoked)
    }

    func testReRegistersBeforeTicketExpiry() async throws {
        let host = makeHost()
        let first = try await startRegistered(host)
        clock.advance(by: 90)
        let second = try await relay.socket(1)
        try await shareEventually { second.sentControls.contains(.register(protocol: 5, slot: Self.slot, ticket: "ticket-2")) }
        XCTAssertFalse(first.isClosed, "old control socket stays until the new one is registered")
        try await shareEventually { first.sentControls.contains { if case .ping = $0 { true } else { false } } } // 10 s pings
        second.feed(.text(ShareRelayControl.registered(leaseSeconds: 30).encoded()))
        try await shareEventually { first.isClosed }
        XCTAssertFalse(second.isClosed)
        await host.stop(reason: .revoked)
    }

    func testRelayErrorsBackOff() async throws {
        relay.failOpens = 3
        let host = makeHost()
        await host.start()
        var delays: [TimeInterval] = []
        for _ in 0..<3 {
            try await shareEventually { self.clock.pendingCount == 1 }
            let deadline = try XCTUnwrap(clock.pendingDeadlines.first)
            delays.append(deadline.timeIntervalSince(clock.now))
            clock.advance(to: deadline)
        }
        XCTAssertEqual(delays, [1, 2, 4])
        let control = try await relay.socket(0)
        try await shareEventually { control.sentControls.count == 1 }
        await host.stop(reason: .revoked)
    }

    func testViewerGetsWelcomeAndReplay() async throws {
        let expires = clock.now.addingTimeInterval(3600)
        let host = makeHost(permission: .type, expiresAt: expires)
        let control = try await startRegistered(host)
        let viewer = try await connectViewer(control, circuit: "c1")
        XCTAssertEqual(viewer.socket.sentControls.first,
                       .join(protocol: 5, slot: Self.slot, circuit: "c1", lane: "lane-c1", generation: 1,
                             ticket: "o2.join-c1", role: .daemon))
        let msgs = viewer.messages()
        guard case let .welcome(nonce, perm, exp, panes, active) = msgs[0] else { return XCTFail("\(msgs[0])") }
        XCTAssertEqual(nonce.count, 16)
        XCTAssertEqual(perm, .type)
        XCTAssertEqual(exp, Int(expires.timeIntervalSince1970))
        XCTAssertEqual(panes, source.panes)
        XCTAssertEqual(active, "p1")
        XCTAssertEqual(msgs[1], .replay(pane: "p1", cols: 80, rows: 24, data: Data("\u{1b}[2Jp1-screen".utf8)))
        XCTAssertEqual(source.subscriberCount(pane: "p1"), 1)
        await host.stop(reason: .revoked)
    }

    func testOnlyHelloAcceptedBeforeHello() async throws {
        let host = makeHost(permission: .type)
        let control = try await startRegistered(host)
        let viewer = try await connectViewer(control, circuit: "c1", sendHello: false)
        viewer.send(.input(pane: "p1", data: Data("x".utf8)))
        viewer.send(.select(pane: "p2"))
        viewer.send(.hello(nonce: viewer.nonce, label: "Firefox"))
        try await shareEventually { viewer.messages().count >= 2 }
        let dropped = await host.droppedFrameCount
        XCTAssertEqual(dropped, 2)
        XCTAssertTrue(source.inputs.isEmpty)
        XCTAssertEqual(viewer.messages()[1], .replay(pane: "p1", cols: 80, rows: 24, data: Data("\u{1b}[2Jp1-screen".utf8)))
        await host.stop(reason: .revoked)
    }

    func testCircuitWithoutHelloIsClosedAfter10s() async throws {
        let host = makeHost()
        let control = try await startRegistered(host)
        let viewer = try await connectViewer(control, circuit: "c1", sendHello: false)
        try await shareEventually { self.clock.pendingCount >= 3 } // + hello timer
        clock.advance(by: 9)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(viewer.socket.isClosed)
        clock.advance(by: 1)
        try await shareEventually { viewer.socket.isClosed }
        let viewers = await host.viewers
        XCTAssertTrue(viewers.isEmpty)
        await host.stop(reason: .revoked)
    }

    func testOversizeFrameDroppedBeforeDecrypt() async throws {
        let host = makeHost()
        let control = try await startRegistered(host)
        let viewer = try await connectViewer(control, circuit: "c1")
        viewer.socket.feed(.data(Data(repeating: 0, count: 64 * 1024 + 1)))
        try await shareEventually { await host.droppedFrameCount == 1 }
        await host.stop(reason: .revoked)
    }

    func testViewOnlyDropsInput() async throws {
        let host = makeHost(permission: .view)
        let control = try await startRegistered(host)
        let viewer = try await connectViewer(control, circuit: "c1")
        viewer.send(.input(pane: "p1", data: Data("ls\r".utf8)))
        try await shareEventually { await host.droppedInputCount == 1 }
        XCTAssertTrue(source.inputs.isEmpty)
        await host.stop(reason: .revoked)
    }

    func testTypeShareWritesInputByteExact() async throws {
        let host = makeHost(permission: .type)
        let control = try await startRegistered(host)
        let viewer = try await connectViewer(control, circuit: "c1")
        let bytes = Data("chào\r".utf8)
        viewer.send(.input(pane: "p1", data: bytes))
        try await shareEventually { self.source.inputs.count == 1 }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(source.inputs.count, 1)
        XCTAssertEqual(source.inputs.first?.pane, "p1")
        XCTAssertEqual(source.inputs.first?.bytes, bytes)
        let dropped = await host.droppedInputCount
        XCTAssertEqual(dropped, 0)
        await host.stop(reason: .revoked)
    }

    func testTypeShareDropsOversizeAndNonTerminalInput() async throws {
        let host = makeHost(permission: .type)
        let control = try await startRegistered(host)
        let viewer = try await connectViewer(control, circuit: "c1")
        viewer.send(.input(pane: "p1", data: Data(repeating: 0x61, count: 4 * 1024 + 1)))
        viewer.send(.input(pane: "b1", data: Data("x".utf8)))
        viewer.send(.input(pane: "nope", data: Data("x".utf8)))
        viewer.send(.input(pane: "p1", data: Data(repeating: 0x62, count: 4 * 1024)))
        try await shareEventually { self.source.inputs.count == 1 }
        let dropped = await host.droppedInputCount
        XCTAssertEqual(dropped, 3)
        XCTAssertEqual(source.inputs.first?.bytes.count, 4 * 1024)
        await host.stop(reason: .revoked)
    }

    func testSelectSwitchesStream() async throws {
        let host = makeHost()
        let control = try await startRegistered(host)
        let viewer = try await connectViewer(control, circuit: "c1")
        viewer.send(.select(pane: "p2"))
        try await shareEventually { viewer.messages().count >= 3 }
        XCTAssertEqual(viewer.messages()[2], .replay(pane: "p2", cols: 100, rows: 30, data: Data("\u{1b}[2Jp2-screen".utf8)))
        XCTAssertEqual(source.subscriberCount(pane: "p1"), 0)
        XCTAssertEqual(source.subscriberCount(pane: "p2"), 1)
        source.emit(pane: "p1", Data("from-p1".utf8))
        source.emit(pane: "p2", Data("from-p2".utf8))
        try await shareEventually { viewer.messages().count >= 4 }
        XCTAssertEqual(viewer.messages()[3], .out(pane: "p2", data: Data("from-p2".utf8)))
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(viewer.messages().count, 4)
        await host.stop(reason: .revoked)
    }

    func testOutputIsCoalescedOffMainThread() async throws {
        let host = makeHost()
        let control = try await startRegistered(host)
        let viewer = try await connectViewer(control, circuit: "c1")
        let sinks = source.sinks(pane: "p1")
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                for i in 0..<50 { for sink in sinks { sink(Data("\(i),".utf8)) } }
                done.resume()
            }
        }
        let expected = Data((0..<50).map { "\($0)," }.joined().utf8)
        try await shareEventually { viewer.outBytes(pane: "p1") == expected }
        XCTAssertLessThan(viewer.messages().count - 2, 50, "chunks are coalesced")
        await host.stop(reason: .revoked)
    }

    func testPanesChangeSendsPanesAndSize() async throws {
        let host = makeHost()
        let control = try await startRegistered(host)
        let viewer = try await connectViewer(control, circuit: "c1")
        source.panes[0].cols = 120
        source.onPanesChanged?()
        try await shareEventually { viewer.messages().count >= 4 }
        XCTAssertEqual(viewer.messages()[2], .panes(source.panes, active: "p1"))
        XCTAssertEqual(viewer.messages()[3], .size(pane: "p1", cols: 120, rows: 24))
        await host.stop(reason: .revoked)
    }

    func testExpiryEndsEveryViewer() async throws {
        let host = makeHost(expiresAt: clock.now.addingTimeInterval(60))
        let control = try await startRegistered(host)
        let v1 = try await connectViewer(control, circuit: "c1")
        let v2 = try await connectViewer(control, circuit: "c2")
        clock.advance(by: 60)
        try await shareEventually { v1.socket.isClosed && v2.socket.isClosed && control.isClosed }
        XCTAssertEqual(v1.messages().last, .bye(.expired))
        XCTAssertEqual(v2.messages().last, .bye(.expired))
        XCTAssertEqual(source.subscriberCount(pane: "p1"), 0)
        XCTAssertNil(source.onPanesChanged)
    }

    func testRevokeClosesAllCircuits() async throws {
        let host = makeHost()
        let control = try await startRegistered(host)
        let v1 = try await connectViewer(control, circuit: "c1")
        let v2 = try await connectViewer(control, circuit: "c2")
        let started = ContinuousClock.now
        await host.stop(reason: .revoked)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(1))
        for v in [v1, v2] {
            XCTAssertTrue(v.socket.isClosed)
            XCTAssertEqual(v.messages().last, .bye(.revoked))
            XCTAssertTrue(v.socket.closedAfterLastSend)
        }
        XCTAssertTrue(control.isClosed)
    }

    func testOutputChunksStayUnder48KiB() async throws {
        let host = makeHost()
        let control = try await startRegistered(host)
        let viewer = try await connectViewer(control, circuit: "c1")
        let big = Data((0..<(200 * 1024)).map { UInt8(truncatingIfNeeded: $0 % 251) })
        source.emit(pane: "p1", big)
        try await shareEventually { viewer.outBytes(pane: "p1") == big }
        for frame in viewer.socket.sentFrames {
            XCTAssertLessThanOrEqual(frame.count, 64 * 1024)
            XCTAssertLessThanOrEqual(frame.count - 28, 48 * 1024, "plaintext ≤ 48 KiB")
        }
        XCTAssertGreaterThan(viewer.socket.sentFrames.count, 5)
        await host.stop(reason: .revoked)
    }

    func testViewerListUpdates() async throws {
        let host = makeHost()
        let stream = host.viewerStream
        let control = try await startRegistered(host)
        let long = String(repeating: "L", count: 60)
        let viewer = try await connectViewer(control, circuit: "c1", label: long)
        var viewers = await host.viewers
        XCTAssertEqual(viewers, [ShareViewer(id: "c1", label: String(repeating: "L", count: 40), connectedAt: clock.now)])
        viewer.socket.close() // relay drops the circuit
        try await shareEventually { await host.viewers.isEmpty }
        await host.stop(reason: .revoked)
        var snapshots: [[ShareViewer]] = []
        for await s in stream { snapshots.append(s) }
        XCTAssertEqual(snapshots.map(\.count), [1, 0])
        viewers = await host.viewers
        XCTAssertTrue(viewers.isEmpty)
    }

    // MARK: Fix round 1

    func testSlowViewerBacklogIsBoundedAndResyncsWithReplay() async throws {
        let host = makeHost()
        let control = try await startRegistered(host)
        let viewer = try await connectViewer(control, circuit: "c1")
        viewer.socket.stallDataSends = true
        let piece = Data(repeating: 0x41, count: 64 * 1024)
        var maxBacklog = 0
        for _ in 0..<48 { // 3 MiB against a stalled socket
            source.emit(pane: "p1", piece)
            try await Task.sleep(for: .milliseconds(2))
            maxBacklog = max(maxBacklog, await host.backlogBytes("c1") ?? 0)
        }
        try await shareEventually { await host.isResyncing("c1") }
        XCTAssertLessThanOrEqual(maxBacklog, ShareHost.maxBacklogBytes)
        XCTAssertGreaterThan(maxBacklog, 0)
        viewer.socket.unstall()
        let replay = ShareMessage.replay(pane: "p1", cols: 80, rows: 24, data: Data("\u{1b}[2Jp1-screen".utf8))
        try await shareEventually { viewer.messages().dropFirst(2).contains(replay) }
        XCTAssertLessThan(viewer.outBytes(pane: "p1").count, 48 * piece.count, "backlog was dropped")
        let backlog = await host.backlogBytes("c1")
        XCTAssertEqual(backlog, 0)
        let resyncing = await host.isResyncing("c1")
        XCTAssertFalse(resyncing)
        source.emit(pane: "p1", Data("after".utf8))
        try await shareEventually { viewer.messages().last == .out(pane: "p1", data: Data("after".utf8)) }
        XCTAssertFalse(viewer.socket.isClosed)
        await host.stop(reason: .revoked)
    }

    func testRepeatedResyncsEndCircuit() async throws {
        let host = makeHost()
        let control = try await startRegistered(host)
        let viewer = try await connectViewer(control, circuit: "c1")
        let flood = Data(repeating: 0x42, count: ShareHost.maxBacklogBytes + 1)
        func replays() -> Int { viewer.messages().filter { if case .replay = $0 { true } else { false } }.count }
        for round in 1...3 {
            source.emit(pane: "p1", flood) // overflows the pump buffer -> resync -> replay
            try await shareEventually { replays() == 1 + round }
        }
        XCTAssertFalse(viewer.socket.isClosed)
        source.emit(pane: "p1", flood) // 4th resync within 10 s
        try await shareEventually { viewer.socket.isClosed }
        try await shareEventually { await host.viewers.isEmpty }
        XCTAssertEqual(source.subscriberCount(pane: "p1"), 0)
        await host.stop(reason: .revoked)
    }

    func testOutputPumpIsBoundedAndStartsPaused() async throws {
        let flushes = LockedBox<[ShareOutputPump.Flush]>([])
        let pump = ShareOutputPump(limit: 100, interval: .milliseconds(1)) { flush in flushes.mutate { $0.append(flush) } }
        pump.push(Data(repeating: 1, count: 60))
        try await Task.sleep(for: .milliseconds(15))
        XCTAssertTrue(flushes.value.isEmpty, "paused until resume")
        pump.push(Data(repeating: 2, count: 60)) // 120 > 100: buffer discarded
        XCTAssertEqual(pump.bufferedBytes, 0)
        pump.push(Data(repeating: 3, count: 30))
        XCTAssertLessThanOrEqual(pump.bufferedBytes, 100)
        pump.resume()
        try await shareEventually { !flushes.value.isEmpty }
        XCTAssertEqual(flushes.value, [.overflow])
        pump.push(Data([9]))
        try await shareEventually { flushes.value.count == 2 }
        XCTAssertEqual(flushes.value.last, .data(Data([9])))
        pump.cancel()
    }

    func testSelectUnknownPaneKeepsStream() async throws {
        let host = makeHost()
        let control = try await startRegistered(host)
        let viewer = try await connectViewer(control, circuit: "c1")
        viewer.send(.select(pane: "nope"))
        viewer.send(.select(pane: "p1")) // sentinel: processed after "nope"
        try await shareEventually { viewer.messages().count >= 3 }
        XCTAssertEqual(source.subscriberCount(pane: "p1"), 1)
        source.emit(pane: "p1", Data("still".utf8))
        try await shareEventually { viewer.messages().last == .out(pane: "p1", data: Data("still".utf8)) }
        XCTAssertEqual(viewer.messages().filter { if case .replay = $0 { true } else { false } }.count, 2)
        await host.stop(reason: .revoked)
    }

    func testMissingPongFailsControlAfter25s() async throws {
        let host = makeHost()
        let control = try await startRegistered(host)
        clock.advance(by: 10)
        try await shareEventually { control.sentControls.contains(.ping(nonce: 1)) }
        clock.advance(by: 24)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(control.isClosed)
        clock.advance(by: 1)
        try await shareEventually { control.isClosed }
        let registered = await host.isRegistered
        XCTAssertFalse(registered)
        await host.stop(reason: .revoked)
    }

    func testPongKeepsControl() async throws {
        let host = makeHost()
        let control = try await startRegistered(host)
        control.autoPong = true
        for _ in 0..<6 {
            let pings = control.pingCount
            clock.advance(by: 10)
            try await shareEventually { await host.lastPongNonce == UInt64(pings + 1) }
        }
        XCTAssertFalse(control.isClosed)
        await host.stop(reason: .revoked)
    }

    func testExpiredShareRefusesWelcomeAndInput() async throws {
        let expires = clock.now.addingTimeInterval(60)
        let host = makeHost(permission: .type, expiresAt: expires)
        let control = try await startRegistered(host)
        let typing = try await connectViewer(control, circuit: "c1")
        let late = try await connectViewer(control, circuit: "c2", sendHello: false)
        clock.set(now: expires) // the expiry timer has not run yet
        typing.send(.input(pane: "p1", data: Data("x".utf8)))
        try await shareEventually { await host.droppedInputCount == 1 }
        XCTAssertTrue(source.inputs.isEmpty)
        late.send(.hello(nonce: late.nonce, label: "late"))
        try await shareEventually { late.socket.isClosed }
        XCTAssertEqual(late.messages(), [.bye(.expired)])
        await host.stop(reason: .expired)
    }

    func testViewerSurvivesReRegister() async throws {
        let host = makeHost()
        let first = try await startRegistered(host)
        first.autoPong = true
        let viewer = try await connectViewer(first, circuit: "c1")
        for _ in 0..<9 {
            let pings = first.pingCount
            clock.advance(by: 10)
            try await shareEventually { await host.lastPongNonce == UInt64(pings + 1) }
        }
        let second = try await relay.socket(2) // 0 control, 1 circuit, 2 new control
        try await shareEventually { !second.sentControls.isEmpty }
        second.feed(.text(ShareRelayControl.registered(leaseSeconds: 30).encoded()))
        try await shareEventually { first.isClosed }
        source.emit(pane: "p1", Data("after-rotate".utf8))
        try await shareEventually { viewer.messages().last == .out(pane: "p1", data: Data("after-rotate".utf8)) }
        XCTAssertFalse(viewer.socket.isClosed)
        let viewers = await host.viewers
        XCTAssertEqual(viewers.map(\.id), ["c1"])
        await host.stop(reason: .revoked)
    }

    func testIdleCircuitGetsKeepaliveAt60s() async throws {
        let host = makeHost()
        let control = try await startRegistered(host)
        control.autoPong = true
        let viewer = try await connectViewer(control, circuit: "c1")
        source.emit(pane: "p1", Data("x".utf8))
        try await shareEventually { viewer.messages().count == 3 } // welcome, replay, out (all at t=0)
        clock.advance(by: 59)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(viewer.messages().count, 3, "no ka before 60 s idle")
        clock.advance(by: 1)
        try await shareEventually { viewer.messages().count == 4 }
        XCTAssertEqual(viewer.messages().last, .ka)
        clock.advance(by: 30)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(viewer.messages().count, 4)
        clock.advance(by: 30)
        try await shareEventually { viewer.messages().count == 5 }
        XCTAssertEqual(viewer.messages().last, .ka)
        await host.stop(reason: .revoked)
    }
}

// MARK: - Test doubles

/// Polls `condition` every millisecond for up to 2 s (only a failing test waits that long).
@MainActor
private func shareEventually(_ file: StaticString = #filePath, line: UInt = #line,
                _ condition: @MainActor () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    XCTFail("condition not met within 2 s", file: file, line: line)
    throw CancellationError()
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.withLock { stored } }
    func mutate(_ body: (inout T) -> Void) { lock.withLock { body(&stored) } }
}

/// Virtual time: `sleep(until:)` suspends until `advance` passes the deadline.
final class ManualShareClock: ShareSleeper, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private var waiters: [UUID: (Date, CheckedContinuation<Void, Error>)] = [:]

    init(now: Date) { current = now }

    var now: Date { lock.withLock { current } }
    var pendingCount: Int { lock.withLock { waiters.count } }
    var pendingDeadlines: [Date] { lock.withLock { waiters.values.map(\.0).sorted() } }

    /// Moves time without waking sleepers (a timer that has not run yet).
    func set(now date: Date) { lock.withLock { current = date } }

    func advance(by seconds: TimeInterval) { advance(to: now.addingTimeInterval(seconds)) }

    func advance(to date: Date) {
        let due: [CheckedContinuation<Void, Error>] = lock.withLock {
            current = max(current, date)
            let ready = waiters.filter { $0.value.0 <= current }.sorted { $0.value.0 < $1.value.0 }
            for (id, _) in ready { waiters[id] = nil }
            return ready.map(\.value.1)
        }
        for c in due { c.resume() }
    }

    func sleep(until deadline: Date) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                let resumeNow: Bool = lock.withLock {
                    if Task.isCancelled || deadline <= current { return true }
                    waiters[id] = (deadline, c)
                    return false
                }
                if resumeNow { c.resume() }
            }
            try Task.checkCancellation()
        } onCancel: {
            let c = lock.withLock { waiters.removeValue(forKey: id)?.1 }
            c?.resume(throwing: CancellationError())
        }
    }
}

final class FakeSocket: ShareSocket, @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private var inbound: [ShareSocketMessage] = []
    private var waiter: CheckedContinuation<ShareSocketMessage, Error>?
    private var closed = false
    private var sent: [ShareSocketMessage] = []
    private var sentAtClose = -1
    private var stalled: [CheckedContinuation<Void, Error>] = []
    private var stalling = false
    private var pongs = false

    /// While true, `send(data:)` suspends until `unstall()` or `close()`.
    var stallDataSends: Bool {
        get { lock.withLock { stalling } }
        set { lock.withLock { stalling = newValue } }
    }
    /// Answers every `ping` with a `pong`, as the relay does.
    var autoPong: Bool {
        get { lock.withLock { pongs } }
        set { lock.withLock { pongs = newValue } }
    }
    var pingCount: Int { sentControls.filter { if case .ping = $0 { true } else { false } }.count }

    func unstall() {
        let waiting: [CheckedContinuation<Void, Error>] = lock.withLock {
            stalling = false
            defer { stalled = [] }
            return stalled
        }
        for c in waiting { c.resume() }
    }

    init(url: URL) { self.url = url }

    var isClosed: Bool { lock.withLock { closed } }
    var closedAfterLastSend: Bool { lock.withLock { closed && sentAtClose == sent.count } }
    var sentControls: [ShareRelayControl] {
        lock.withLock { sent }.compactMap { if case .text(let t) = $0 { ShareRelayControl.decode(t) } else { nil } }
    }
    var sentFrames: [Data] { lock.withLock { sent }.compactMap { if case .data(let d) = $0 { d } else { nil } } }

    func feed(_ message: ShareSocketMessage) {
        let w: CheckedContinuation<ShareSocketMessage, Error>? = lock.withLock {
            if closed { return nil }
            if let w = waiter { waiter = nil; return w }
            inbound.append(message)
            return nil
        }
        w?.resume(returning: message)
    }

    func send(text: String) async throws {
        try record(.text(text))
        if autoPong, case .ping(let n)? = ShareRelayControl.decode(text) {
            feed(.text(ShareRelayControl.pong(nonce: n).encoded()))
        }
    }

    func send(data: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            let wait: Bool = lock.withLock {
                guard stalling, !closed else { return false }
                stalled.append(c)
                return true
            }
            if !wait { c.resume() }
        }
        try record(.data(data))
    }

    private func record(_ m: ShareSocketMessage) throws {
        try lock.withLock {
            if closed { throw URLError(.networkConnectionLost) }
            sent.append(m)
        }
    }

    func receive() async throws -> ShareSocketMessage {
        try await withCheckedThrowingContinuation { c in
            let result: Result<ShareSocketMessage, Error>? = lock.withLock {
                if !inbound.isEmpty { return .success(inbound.removeFirst()) }
                if closed { return .failure(URLError(.networkConnectionLost)) }
                waiter = c
                return nil
            }
            if let result { c.resume(with: result) }
        }
    }

    func close() {
        let (w, waiting): (CheckedContinuation<ShareSocketMessage, Error>?, [CheckedContinuation<Void, Error>]) = lock.withLock {
            if !closed { closed = true; sentAtClose = sent.count }
            defer { waiter = nil; stalled = [] }
            return (waiter, stalled)
        }
        w?.resume(throwing: URLError(.networkConnectionLost))
        for c in waiting { c.resume(throwing: URLError(.networkConnectionLost)) }
    }
}

final class FakeRelay: ShareSocketFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var sockets: [FakeSocket] = []
    private var failures = 0
    var failOpens: Int {
        get { lock.withLock { failures } }
        set { lock.withLock { failures = newValue } }
    }
    var count: Int { lock.withLock { sockets.count } }

    func open(_ url: URL) async throws -> any ShareSocket {
        try lock.withLock {
            if failures > 0 { failures -= 1; throw URLError(.cannotConnectToHost) }
            let s = FakeSocket(url: url)
            sockets.append(s)
            return s
        }
    }

    @MainActor
    func socket(_ index: Int) async throws -> FakeSocket {
        try await shareEventually { self.count > index }
        return lock.withLock { sockets[index] }
    }
}

final class FakeTickets: ShareTicketProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []
    private let clock: ManualShareClock
    init(clock: ManualShareClock) { self.clock = clock }
    var requested: [String] { lock.withLock { ids } }

    func hostTicket(shareID: String) async throws -> (ticket: String, relayURL: URL, expiresAt: Date) {
        let n = lock.withLock { ids.append(shareID); return ids.count }
        return ("ticket-\(n)", ShareHostTests.relayURL, clock.now.addingTimeInterval(120))
    }
}

@MainActor
final class FakeShareSource: ShareSource {
    final class Token {}
    private struct Sub { let pane: String; weak var token: Token?; let sink: @Sendable (Data) -> Void }

    var panes: [SharePane] = []
    var activePane: String?
    var snapshots: [String: (Int, Int, Data)] = [:]
    var inputs: [(pane: String, bytes: Data)] = []
    var onPanesChanged: (() -> Void)?
    private var subs: [Sub] = []

    func snapshot(pane: String) -> (cols: Int, rows: Int, vt: Data)? {
        snapshots[pane].map { (cols: $0.0, rows: $0.1, vt: $0.2) }
    }

    func subscribe(pane: String, _ sink: @escaping @Sendable (Data) -> Void) -> AnyObject {
        let t = Token()
        subs.append(Sub(pane: pane, token: t, sink: sink))
        return t
    }

    func input(pane: String, _ bytes: Data) { inputs.append((pane, bytes)) }

    func sinks(pane: String) -> [@Sendable (Data) -> Void] { subs.filter { $0.pane == pane && $0.token != nil }.map(\.sink) }
    func subscriberCount(pane: String) -> Int { sinks(pane: pane).count }
    func emit(pane: String, _ data: Data) { for s in sinks(pane: pane) { s(data) } }
}

/// The browser side of one circuit, decoding what the host sent.
@MainActor
final class FakeViewer {
    let socket: FakeSocket
    let nonce = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
    private var cipher: ShareCipher
    private var decoded: [ShareMessage] = []
    private var consumed = 0

    init(socket: FakeSocket, cipher: ShareCipher) {
        self.socket = socket
        self.cipher = cipher
    }

    func send(_ message: ShareMessage) {
        let frame = try! cipher.seal(message)
        if case .hello(let n, _) = message { cipher.setViewerNonce(n) }
        socket.feed(.data(frame))
    }

    func messages() -> [ShareMessage] {
        let frames = socket.sentFrames
        while consumed < frames.count {
            let m = cipher.open(frames[consumed])
            consumed += 1
            guard let m else { XCTFail("host frame failed to open"); continue }
            if case .welcome(let n, _, _, _, _) = m { cipher.setHostNonce(n) }
            decoded.append(m)
        }
        return decoded
    }

    func outBytes(pane: String) -> Data {
        messages().reduce(into: Data()) { acc, m in if case .out(pane, let d) = m { acc += d } }
    }
}

// MARK: - Fix round 2

/// Holds each select at the host's hook until the test releases its pane.
final class SelectGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var arrivals: [String] = []
    private var open = false

    var arrived: [String] { lock.withLock { arrivals } }

    func enter(_ pane: String) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let pass: Bool = lock.withLock {
                arrivals.append(pane)
                if open { return true }
                waiting[pane, default: []].append(c)
                return false
            }
            if pass { c.resume() }
        }
    }

    func release(_ pane: String) {
        let cs = lock.withLock { waiting.removeValue(forKey: pane) ?? [] }
        for c in cs { c.resume() }
    }

    func openAll() {
        let cs: [CheckedContinuation<Void, Never>] = lock.withLock {
            open = true
            defer { waiting = [:] }
            return waiting.values.flatMap { $0 }
        }
        for c in cs { c.resume() }
    }
}

extension ShareHostTests {
    func testViewerSelectWinsOverInFlightResync() async throws {
        let host = makeHost()
        let control = try await startRegistered(host)
        let viewer = try await connectViewer(control, circuit: "c1")
        let gate = SelectGate()
        await host.setSelectHook { await gate.enter($0) }
        // Internal select first: a pump overflow resyncs p1 and its reselect blocks at the gate.
        source.emit(pane: "p1", Data(repeating: 0x43, count: ShareHost.maxBacklogBytes + 1))
        try await shareEventually { gate.arrived == ["p1"] }
        // Then the viewer selects p2, which also blocks.
        viewer.send(.select(pane: "p2"))
        try await shareEventually { gate.arrived == ["p1", "p2"] }
        // The internal select finishes first; the viewer's request is the latest and must still win.
        gate.release("p1")
        try await Task.sleep(for: .milliseconds(20))
        gate.release("p2")
        gate.openAll()
        let replayP2 = ShareMessage.replay(pane: "p2", cols: 100, rows: 30, data: Data("\u{1b}[2Jp2-screen".utf8))
        try await shareEventually { viewer.messages().contains(replayP2) }
        try await Task.sleep(for: .milliseconds(30))
        let lastReplay = viewer.messages().last { if case .replay = $0 { true } else { false } }
        XCTAssertEqual(lastReplay, replayP2)
        XCTAssertEqual(source.subscriberCount(pane: "p1"), 0)
        XCTAssertEqual(source.subscriberCount(pane: "p2"), 1)
        source.emit(pane: "p2", Data("b".utf8))
        try await shareEventually { viewer.messages().last == .out(pane: "p2", data: Data("b".utf8)) }
        let resyncing = await host.isResyncing("c1")
        XCTAssertFalse(resyncing)
        await host.stop(reason: .revoked)
    }

    func testResyncOnVanishedPaneFallsBackToActive() async throws {
        let host = makeHost()
        let control = try await startRegistered(host)
        let viewer = try await connectViewer(control, circuit: "c1")
        viewer.send(.select(pane: "p2"))
        try await shareEventually { viewer.messages().count >= 3 }
        let gate = SelectGate()
        await host.setSelectHook { await gate.enter($0) }
        source.emit(pane: "p2", Data(repeating: 0x44, count: ShareHost.maxBacklogBytes + 1))
        try await shareEventually { gate.arrived.count == 1 }
        source.panes.remove(at: 1) // p2 closes while the resync is in flight (no panes callback yet)
        gate.openAll()
        let replayP1 = ShareMessage.replay(pane: "p1", cols: 80, rows: 24, data: Data("\u{1b}[2Jp1-screen".utf8))
        try await shareEventually { viewer.messages().last == replayP1 }
        let resyncing = await host.isResyncing("c1")
        XCTAssertFalse(resyncing)
        XCTAssertEqual(source.subscriberCount(pane: "p1"), 1)
        await host.stop(reason: .revoked)
    }

    func testKeepaliveSkipsWhileFramesQueued() async throws {
        let host = makeHost()
        let control = try await startRegistered(host)
        control.autoPong = true
        let viewer = try await connectViewer(control, circuit: "c1")
        viewer.socket.stallDataSends = true
        source.emit(pane: "p1", Data("q".utf8)) // queued behind a stalled socket
        try await shareEventually { (await host.backlogBytes("c1") ?? 0) > 0 }
        clock.advance(by: 60) // 60 s since the last sealed frame, but that frame is still queued
        try await Task.sleep(for: .milliseconds(30))
        viewer.socket.unstall()
        try await shareEventually { viewer.messages().count >= 3 }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(viewer.messages().contains(.ka))
        await host.stop(reason: .revoked)
    }
}
