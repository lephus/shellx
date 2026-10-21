import Foundation
import Testing
@testable import ShellXRemoteCore

private final class Capture: @unchecked Sendable { var method = ""; var body = Data(); var onMain = true }
private struct StubCore: ShellXCoreCalling {
    let reply: String
    let capture: Capture
    func call(method: String, json: Data) throws -> Data {
        capture.method = method; capture.body = json; capture.onMain = Thread.isMainThread
        return Data(reply.utf8)
    }
}
private func client(_ reply: String) -> (ShellXCoreClient, Capture) {
    let c = Capture(); return (ShellXCoreClient(StubCore(reply: reply, capture: c)), c)
}
private func params(_ c: Capture) throws -> [String: JSONValue] { try JSONDecoder().decode([String: JSONValue].self, from: c.body) }

@Test func createShareSendsOnlyTheFiveKeys() throws {
    let (core, cap) = client(#"{"ok":{"id":"k7f29qd1","slot":"s","expires_at_unix":1000,"claim_until_unix":null}}"#)
    let s = try core.createShare(id: "k7f2-9qd1", permission: .type, lifetime: .untilQuit, oneTime: true, access: "A")
    #expect(cap.method == "shares.create")
    let p = try params(cap)
    #expect(Set(p.keys) == ["id", "permission", "lifetime", "one_time", "access"])
    #expect(p["id"] == .string("k7f29qd1")); #expect(p["permission"] == .string("type")); #expect(p["lifetime"] == .string("until_quit")); #expect(p["one_time"] == .bool(true))
    #expect(s == ShellXCreatedShare(id: "k7f29qd1", slot: "s", expiresAtUnix: 1000, claimUntilUnix: nil))
}

@Test func listSharesDecodes() throws {
    let (core, cap) = client(#"{"ok":{"shares":[{"id":"k7f29qd1","permission":"view","lifetime":"15m","expires_at_unix":5,"revoked":true}]}}"#)
    let l = try core.listShares()
    #expect(cap.method == "shares.list")
    #expect(l == [ShellXShareSummary(id: "k7f29qd1", permission: .view, lifetime: .fifteenMinutes, expiresAtUnix: 5, revoked: true)])
}

@Test func revokeAndHostTicketStripTheDisplayDash() throws {
    let (core, cap) = client(#"{"ok":{}}"#)
    try core.revokeShare(id: "k7f2-9qd1")
    #expect(cap.method == "shares.revoke"); #expect(try params(cap)["id"] == .string("k7f29qd1"))
    let (core2, cap2) = client(#"{"ok":{"ticket":"v2.x.y","expires_at_unix":120,"relay_url":"wss://relay.test/v2/relay"}}"#)
    let t = try core2.hostShareTicket(id: "k7f2-9qd1")
    #expect(cap2.method == "shares.host_ticket"); #expect(try params(cap2)["id"] == .string("k7f29qd1"))
    #expect(t.ticket == "v2.x.y"); #expect(t.relayURL.absoluteString == "wss://relay.test/v2/relay"); #expect(t.expiresAt == Date(timeIntervalSince1970: 120))
}

@Test func shareErrorsKeepTheApiCode() {
    let (core, _) = client(#"{"error":{"code":"share_revoked","message":"m"}}"#)
    #expect(throws: ShellXCoreError(code: "share_revoked", message: "m")) { try core.hostShareTicket(id: "k7f29qd1") }
}

@Test @MainActor func ticketProviderLeavesTheMainThread() async throws {
    let (core, cap) = client(#"{"ok":{"ticket":"v2.x.y","expires_at_unix":7,"relay_url":"wss://r.test/v2/relay"}}"#)
    let t = try await ShellXCoreShareTickets(core: core).hostTicket(shareID: "k7f2-9qd1")
    #expect(t.ticket == "v2.x.y"); #expect(!cap.onMain)
}

@Test func shareIDRandomUsesTheAlphabetAndLength() {
    let alphabet = Set(ShareID.alphabet)
    #expect(alphabet.count == 32); #expect(!alphabet.contains("i") && !alphabet.contains("l") && !alphabet.contains("o") && !alphabet.contains("u"))
    var seen = Set<Character>()
    var ids = Set<String>()
    for _ in 0..<500 {
        let id = ShareID.random()
        #expect(id.count == 8); #expect(id.allSatisfy { alphabet.contains($0) })
        seen.formUnion(id); ids.insert(id)
    }
    #expect(seen == alphabet) // 4000 draws cover all 32 symbols (miss chance ~1e-54)
    #expect(ids.count > 495)
}

@Test func shareIDDisplayFormat() {
    #expect(ShareID.display("k7f29qd1") == "k7f2-9qd1")
    #expect(ShareID.display("k7f2-9qd1") == "k7f2-9qd1")
    #expect(ShareID.display("abc") == "abc")
}

private final class Scripted: @unchecked Sendable {
    var calls: [[String: JSONValue]] = []
    var takenIDs: Set<String>
    init(taken: Set<String>) { takenIDs = taken }
}
private struct TakenIDCore: ShellXCoreCalling {
    let script: Scripted
    func call(method: String, json: Data) throws -> Data {
        let p = try JSONDecoder().decode([String: JSONValue].self, from: json)
        script.calls.append(p)
        guard case .string(let id)? = p["id"] else { return Data(#"{"error":{"code":"invalid_params","message":"id"}}"#.utf8) }
        if script.takenIDs.contains(id) { return Data(#"{"error":{"code":"share_id_taken","message":"taken"}}"#.utf8) }
        return Data(#"{"ok":{"id":"\#(id)","slot":"s","expires_at_unix":9,"claim_until_unix":null}}"#.utf8)
    }
}

@Test func createShareRetryingIDDrawsAFreshIDAndRederivesAccess() throws {
    let script = Scripted(taken: ["aaaaaaaa", "bbbbbbbb"])
    let core = ShellXCoreClient(TakenIDCore(script: script))
    var queue = ["aaaaaaaa", "bbbbbbbb", "cccccccc"]
    let secret = ShareSecret.random()
    let r = try core.createShareRetryingID(permission: .view, lifetime: .oneHour, oneTime: false, secret: secret, makeID: { queue.removeFirst() })
    #expect(r.share.id == "cccccccc"); #expect(r.secret == secret)
    #expect(script.calls.count == 3)
    for (call, id) in zip(script.calls, ["aaaaaaaa", "bbbbbbbb", "cccccccc"]) {
        #expect(call["id"] == .string(id))
        #expect(call["access"] == .string(secret.keys(shareID: id).access)) // access follows the id
    }
    #expect(Set(["aaaaaaaa", "bbbbbbbb", "cccccccc"].map { secret.keys(shareID: $0).access }).count == 3)
}

@Test func createShareRetryingIDGivesUpAfterThreeAttempts() {
    let script = Scripted(taken: ["aaaaaaaa", "bbbbbbbb", "cccccccc", "dddddddd"])
    let core = ShellXCoreClient(TakenIDCore(script: script))
    var queue = ["aaaaaaaa", "bbbbbbbb", "cccccccc", "dddddddd"]
    #expect(throws: ShellXCoreError(code: "share_id_taken", message: "taken")) {
        try core.createShareRetryingID(permission: .view, lifetime: .oneHour, oneTime: false, makeID: { queue.removeFirst() })
    }
    #expect(script.calls.count == 3)
}

private final class CallCount: @unchecked Sendable { var n = 0 }
private struct CountingErrorCore: ShellXCoreCalling {
    let count: CallCount
    func call(method: String, json: Data) throws -> Data {
        count.n += 1
        return Data(#"{"error":{"code":"share_limit","message":"m"}}"#.utf8)
    }
}

@Test func createShareRetryingIDDoesNotRetryOtherErrors() {
    let count = CallCount()
    let core = ShellXCoreClient(CountingErrorCore(count: count))
    #expect(throws: ShellXCoreError(code: "share_limit", message: "m")) {
        try core.createShareRetryingID(permission: .view, lifetime: .oneHour, oneTime: false)
    }
    #expect(count.n == 1)
}
