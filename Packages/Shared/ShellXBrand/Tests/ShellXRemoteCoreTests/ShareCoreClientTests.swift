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

@Test func createShareSendsOnlyTheFourKeys() throws {
    let (core, cap) = client(#"{"ok":{"id":"k7f29qd1","slot":"s","expires_at_unix":1000,"claim_until_unix":null}}"#)
    let s = try core.createShare(permission: .type, lifetime: .untilQuit, oneTime: true, access: "A")
    #expect(cap.method == "shares.create")
    let p = try params(cap)
    #expect(Set(p.keys) == ["permission", "lifetime", "one_time", "access"])
    #expect(p["permission"] == .string("type")); #expect(p["lifetime"] == .string("until_quit")); #expect(p["one_time"] == .bool(true))
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
