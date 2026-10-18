import Foundation
import Testing
@testable import ShellXRemoteCore

private let t0 = Date(timeIntervalSince1970: 1000)
private let home = URL(fileURLWithPath: "/Users/phu")
private let tmp = URL(fileURLWithPath: "/var/folders/ab/cdefghijklmnop_qrstuvwx0000gn/T")

@Test func sha256KnownVectors() {
    #expect(SHA256Pure.hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(SHA256Pure.hex(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    let long = Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)
    #expect(SHA256Pure.hex(long) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
}

@Test func pathsAreDistinctPerBundleAndFitSunPath() {
    let rel = RemotePaths(bundleID: "pro.shellx.desktop", home: home, temporaryDirectory: tmp)
    let dev = RemotePaths(bundleID: "pro.shellx.desktop.debug.l5", home: home, temporaryDirectory: tmp)
    let relAll = [rel.coreStateDir, rel.daemonStateDir, rel.clientStateDir, rel.muxSocket, rel.bridgeSocket, rel.adminSocket, rel.linkSocket]
    let devAll = [dev.coreStateDir, dev.daemonStateDir, dev.clientStateDir, dev.muxSocket, dev.bridgeSocket, dev.adminSocket, dev.linkSocket]
    #expect(Set(relAll).isDisjoint(with: devAll)); #expect(rel.session != dev.session)
    for s in [rel.muxSocket, rel.bridgeSocket, rel.adminSocket, rel.linkSocket, rel.clientSocket(for: "m_" + String(repeating: "x", count: 40))] {
        #expect(s.path.utf8.count < 104)
    }
}

@Test func pathsUseExactLayout() {
    let p = RemotePaths(bundleID: "pro.shellx.desktop", home: home, temporaryDirectory: tmp)
    let h = SHA256Pure.hex(Data("pro.shellx.desktop".utf8)).prefix(8)
    #expect(p.stateRoot.path == "/Users/phu/Library/Application Support/ShellX/remote/pro.shellx.desktop")
    #expect(p.coreStateDir.path == p.stateRoot.path + "/core")
    #expect(p.daemonStateDir.path == p.stateRoot.path + "/daemon")
    #expect(p.clientStateDir.path == p.stateRoot.path + "/client")
    #expect(p.socketDir.path == tmp.path + "/sx-" + h)
    #expect(p.muxSocket.path == p.socketDir.path + "/mux.sock")
    #expect(p.bridgeSocket.lastPathComponent == "bridge.sock")
    #expect(p.adminSocket.lastPathComponent == "admin.sock")
    #expect(p.linkSocket.lastPathComponent == "link.sock")
    #expect(p.session == "shellx-" + h)
    let mh = SHA256Pure.hex(Data("m_1".utf8)).prefix(8)
    #expect(p.clientSocket(for: "m_1").path == p.socketDir.path + "/c-" + mh + ".sock")
    #expect(p.connectTicketName(for: "m_1") == "connect-" + mh + ".ticket")
}

@Test func backoffSchedule() {
    #expect((0...7).map { ReconnectBackoff.delay(attempt: $0) } == [1, 2, 4, 8, 16, 30, 30, 30])
    #expect(ReconnectBackoff.delay(attempt: 3, jitter: 0.5) == 4)
    #expect(ReconnectBackoff.delay(attempt: 5000) == 30)
}

@Test func linkExitSchedulesRetryAndMintsBeforeEachSpawn() {
    var m = LinkStateMachine()
    #expect(m.handle(.start, now: t0) == [.publish(.connecting), .mintTicket, .spawn])
    #expect(m.handle(.exited(status: 1), now: t0) == [.publish(.reconnecting(attempt: 1, retryAt: t0 + 1)), .scheduleRetry(at: t0 + 1)])
    #expect(m.handle(.retryDue, now: t0 + 1) == [.mintTicket, .spawn])
    _ = m.handle(.exited(status: 1), now: t0 + 1)
    #expect(m.state == .reconnecting(attempt: 2, retryAt: t0 + 3))
    _ = m.handle(.connected(localSocket: "/s"), now: t0 + 4)
    #expect(m.state == .connected(localSocket: "/s"))
    _ = m.handle(.exited(status: 1), now: t0 + 9)
    #expect(m.state == .reconnecting(attempt: 1, retryAt: t0 + 10))
}

@Test func offlineMachineStopsRetriesUntilOnline() {
    var m = LinkStateMachine()
    _ = m.handle(.start, now: t0)
    _ = m.handle(.exited(status: 1), now: t0)
    let seen = t0 - 30
    #expect(m.handle(.machineOffline(lastSeen: seen), now: t0) == [.kill, .publish(.offline(lastSeen: seen))])
    #expect(m.handle(.retryDue, now: t0 + 1) == [])
    #expect(m.handle(.exited(status: 1), now: t0 + 1) == [])
    #expect(m.state == .offline(lastSeen: seen))
    #expect(m.handle(.machineOnline, now: t0 + 5) == [.publish(.connecting), .mintTicket, .spawn])
}

@Test func unauthorizedMintFailsWithoutRetry() {
    var m = LinkStateMachine()
    _ = m.handle(.start, now: t0)
    let a = m.handle(.mintFailed(code: "unauthorized"), now: t0)
    #expect(a == [.publish(.failed(code: "unauthorized"))])
    #expect(m.state == .failed(code: "unauthorized"))
    #expect(m.handle(.retryDue, now: t0 + 1) == [])
    var n = LinkStateMachine()
    _ = n.handle(.start, now: t0)
    #expect(n.handle(.mintFailed(code: "network"), now: t0) == [.publish(.reconnecting(attempt: 1, retryAt: t0 + 1)), .scheduleRetry(at: t0 + 1)])
    for code in ["forbidden", "not_logged_in"] {
        var k = LinkStateMachine(); _ = k.handle(.start, now: t0)
        #expect(k.handle(.mintFailed(code: code), now: t0) == [.publish(.failed(code: code))])
    }
}

@Test func stopKillsAndIdles() {
    var m = LinkStateMachine()
    #expect(m.handle(.stop, now: t0) == [])
    _ = m.handle(.start, now: t0)
    #expect(m.handle(.stop, now: t0) == [.kill, .publish(.idle)])
    #expect(m.state == .idle)
}

@Test func ticketRefreshAtHalfLifeMinOneSecond() {
    #expect(TicketSchedule.nextRefresh(expiresAt: t0 + 120, now: t0) == 60)
    #expect(TicketSchedule.nextRefresh(expiresAt: t0 + 2, now: t0) == 1)
    #expect(TicketSchedule.nextRefresh(expiresAt: t0 - 5, now: t0) == 1)
}

@Test func decoderKeepsSplitUTF8ByteExact() throws {
    let bytes = Data("tiếng Việt\r".utf8); var d = BridgeFrameDecoder()
    let enc = BridgeFrame(type: .input, payload: bytes).encoded()
    var out: [BridgeFrame] = []; for b in enc { out += try d.feed(Data([b])) }
    #expect(out == [BridgeFrame(type: .input, payload: bytes)])
    #expect(Array(bytes) == [0x74,0x69,0xe1,0xba,0xbf,0x6e,0x67,0x20,0x56,0x69,0xe1,0xbb,0x87,0x74,0x0d])
}

@Test func frameWireFormatAndSize() throws {
    let f = BridgeFrame(type: .output, payload: Data([1, 2, 3]))
    #expect(Array(f.encoded()) == [0x4F, 0, 0, 0, 3, 1, 2, 3])
    #expect(Array(BridgeFrame.size(cols: 94, rows: 37).encoded()) == [0x53, 0, 0, 0, 4, 0, 94, 0, 37])
    var d = BridgeFrameDecoder()
    let two = f.encoded() + BridgeFrame(type: .exit, payload: Data()).encoded()
    #expect(try d.feed(two).count == 2)
}

@Test func decoderRejectsOversizeAndUnknownType() {
    var d = BridgeFrameDecoder()
    #expect(throws: BridgeFrameError.self) { try d.feed(Data([0x49, 0x01, 0x00, 0x00, 0x01])) }   // 16 MiB + 1
    var u = BridgeFrameDecoder()
    #expect(throws: BridgeFrameError.self) { try u.feed(Data([0x5A, 0, 0, 0, 0])) }
    var ok = BridgeFrameDecoder()
    #expect((try? ok.feed(Data([0x49, 0x01, 0x00, 0x00, 0x00]))) != nil)                     // exactly 16 MiB is legal
}

private func b64url(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
private func fixtureInvite(version: Int = 1, fingerprint: String? = nil, route: String = "relay+wss://relay.shellx.pro/v2/relay", slot: String = "slot-abc") -> String {
    let key = Data(repeating: 7, count: 32)
    let fp = fingerprint ?? b64url(Data(SHA256Pure.digest(key).prefix(16)))
    let json = """
    {"version":\(version),"id":"inv_123","secret":"S3CRET-SECRET-VALUE","daemon_public_key":"\(b64url(key))","daemon_fingerprint":"\(fp)","daemon_name":"B","expires_at_unix":4102444800,"route_hints":["\(route)"],"relay_access":[{"route":"\(route)","slot":"\(slot)","ticket":"TICKET-VALUE"}],"approval_required":true}
    """
    return "cmux://enroll/" + b64url(Data(json.utf8))
}

@Test func inviteSummaryNeverExposesSecret() throws {
    let s = try InviteURI.summary(of: fixtureInvite())
    #expect(s.invitationID == "inv_123"); #expect(s.relayRoute == "relay+wss://relay.shellx.pro/v2/relay")
    #expect(s.relaySlot == "slot-abc")
    #expect(s.daemonFingerprint == b64url(Data(SHA256Pure.digest(Data(repeating: 7, count: 32)).prefix(16))))
    let text = String(describing: s) + String(reflecting: s)
    #expect(!text.contains("S3CRET")); #expect(!text.contains("TICKET-VALUE"))
}

@Test func inviteRejectsMalformed() {
    for bad in ["https://x", "cmux://enroll/!!!", fixtureInvite(version: 2), fixtureInvite(fingerprint: "AAAA"),
                fixtureInvite(route: "wss://relay.shellx.pro"), fixtureInvite(slot: "")] {
        #expect(throws: InviteError.self) { try InviteURI.summary(of: bad) }
    }
}

@Test func gateApprovesOnlyIssuedInvitationOnce() {
    var g = ApprovalGate(); g.expect(invitationID: "inv1", pairingID: "p1", now: t0)
    #expect(g.decide(pendingInvitationID: "inv1", now: t0 + 5) == .approve(pairingID: "p1"))
    #expect(g.decide(pendingInvitationID: "inv1", now: t0 + 6) == .deny)
}
@Test func gateDeniesUnknownInvitation() { var g = ApprovalGate(); #expect(g.decide(pendingInvitationID: "x", now: t0) == .deny) }
@Test func gateExpiresAfter300s() {
    var g = ApprovalGate(); g.expect(invitationID: "a", pairingID: "p", now: t0)
    #expect(g.decide(pendingInvitationID: "a", now: t0 + 301) == .deny)
    g.expect(invitationID: "b", pairingID: "q", now: t0)
    #expect(g.decide(pendingInvitationID: "b", now: t0 + 299) == .approve(pairingID: "q"))
}

@Test func relayRouteMapping() throws {
    #expect(try RelayRoute.cmuxRoute(from: "wss://relay.shellx.pro/v2/relay") == "relay+wss://relay.shellx.pro/v2/relay")
    #expect(try RelayRoute.cmuxRoute(from: "ws://127.0.0.1:8787/v2/relay") == "relay+ws://127.0.0.1:8787/v2/relay")
    #expect(throws: (any Error).self) { try RelayRoute.cmuxRoute(from: "https://x") }
    #expect(throws: (any Error).self) { try RelayRoute.cmuxRoute(from: "wss://") }
}

private let P = RemotePaths(bundleID: "pro.shellx.desktop", home: home, temporaryDirectory: tmp)
private let ticket = URL(fileURLWithPath: "/t/tk.ticket")
private let route = "relay+wss://relay.shellx.pro/v2/relay"

@Test func serverStartArgv() {
    #expect(RemoteCommandLine.serverStart(paths: P, route: route, slot: "sl", ticketFile: ticket) == [
        "server", "start", "--session", P.session, "--socket", P.muxSocket.path, "--headless", "--ephemeral",
        "--remote-state-dir", P.daemonStateDir.path, "--remote-admin-socket", P.adminSocket.path,
        "--remote-link-socket", P.linkSocket.path, "--relay", route, "--relay-slot", "sl",
        "--relay-ticket-file", "/t/tk.ticket"])
    #expect(RemoteCommandLine.serverStop(paths: P) == ["server", "stop", "--session", P.session, "--socket", P.muxSocket.path, "--force"])
}

@Test func enrollArgv() {
    let tail = ["--session", P.session, "--state-dir", P.daemonStateDir.path, "--admin-socket", P.adminSocket.path]
    #expect(RemoteCommandLine.enrollStatus(paths: P) == ["remote", "enroll", "status"] + tail + ["--json"])
    #expect(RemoteCommandLine.enrollPending(paths: P) == ["remote", "enroll", "pending"] + tail + ["--json"])
    #expect(RemoteCommandLine.enrollApprove(paths: P, invitationID: "inv") == ["remote", "enroll", "approve", "inv"] + tail)
    #expect(RemoteCommandLine.enrollDeny(paths: P, invitationID: "inv") == ["remote", "enroll", "deny", "inv"] + tail)
    #expect(RemoteCommandLine.enrollCreate(paths: P, route: route, slot: "sl", ticketFile: ticket, ttlSeconds: 300)
            == ["remote", "enroll", "create"] + tail + ["--advertise", route, "--relay-route", route, "--relay-slot", "sl", "--relay-ticket-file", "/t/tk.ticket", "--ttl", "300"])
}

@Test func connectArgv() {
    let base = ["remote", "connect", route, "--relay-slot", "sl", "--relay-ticket-file", "/t/tk.ticket",
                "--state-dir", P.clientStateDir.path, "--local-socket", P.clientSocket(for: "m_1").path,
                "--headless", "--json", "--exit-with-parent", "--device-name", "Mac"]
    #expect(RemoteCommandLine.connect(paths: P, machine: "m_1", route: route, slot: "sl", ticketFile: ticket, inviteFile: nil, deviceName: "Mac") == base)
    #expect(RemoteCommandLine.connect(paths: P, machine: "m_1", route: route, slot: "sl", ticketFile: ticket, inviteFile: URL(fileURLWithPath: "/t/i"), deviceName: "Mac") == base + ["--invite-file", "/t/i"])
}

@Test func attachWrapperQuotesAndLoops() {
    let c = RemoteCommandLine.attachShellCommand(clientPath: "/App/cmux tui", socketPath: "/tmp/a b/c.sock", terminalID: "term_1")
    #expect(c.contains("attach")); #expect(c.contains("--terminal")); #expect(c.contains("'term_1'"))
    #expect(c.contains("reconnecting")); #expect(c.contains("đang kết nối lại… / reconnecting…"))
    #expect(c.contains("phiên đã kết thúc / session ended"))
    #expect(c.contains("'/tmp/a b/c.sock'")); #expect(c.contains("'/App/cmux tui'"))
    let evil = RemoteCommandLine.attachShellCommand(clientPath: "/c", socketPath: "/s", terminalID: "x'; rm -rf ~; '")
    #expect(evil.contains(#"'x'\''; rm -rf ~; '\'''"#))
}

private struct FakeCore: ShellXCoreCalling {
    let reply: String
    var capture: (@Sendable (String, Data) -> Void)? = nil
    func call(method: String, json: Data) throws -> Data { capture?(method, json); return Data(reply.utf8) }
}
private struct Machines: Decodable, Equatable { let n: Int }

@Test func coreClientMapsErrorEnvelope() {
    let c = ShellXCoreClient(FakeCore(reply: #"{"error":{"code":"fingerprint_mismatch","message":"m"}}"#))
    #expect(throws: ShellXCoreError(code: "fingerprint_mismatch", message: "m")) { try c.call("pair.approve", [:], as: Machines.self) }
}

@Test func coreClientDecodesOkAndEncodesParams() throws {
    final class Box: @unchecked Sendable { var method = ""; var body = Data() }
    let box = Box()
    let c = ShellXCoreClient(FakeCore(reply: #"{"ok":{"n":3}}"#, capture: { box.method = $0; box.body = $1 }))
    let r = try c.call("machines.list", ["a": .string("x"), "b": .number(2), "c": .bool(true), "d": .null, "e": .array([.string("y")])], as: Machines.self)
    #expect(r == Machines(n: 3)); #expect(box.method == "machines.list")
    let obj = try JSONDecoder().decode([String: JSONValue].self, from: box.body)
    #expect(obj["a"] == .string("x")); #expect(obj["b"] == .number(2)); #expect(obj["c"] == .bool(true)); #expect(obj["d"] == .null)
    #expect(obj["e"] == .array([.string("y")]))
    #expect(throws: ShellXCoreError.self) { try ShellXCoreClient(FakeCore(reply: "garbage")).call("x", as: Machines.self) }
}

@Test func displayFormats() {
    #expect(PairingDisplay.code("123456") == "123 456"); #expect(PairingDisplay.fingerprint("a1b2c3d4e5f60718") == "a1b2 c3d4 e5f6 0718")
}

@Test func pairingRequestExpiresAfter300s() {
    let r = PairingRequest(id: "p", fromMachineID: "m", requesterName: "n", code: "123456", fingerprint: "ab", suspicious: false, firstSeen: t0)
    #expect(r.expiresAt == t0 + 300)
}
