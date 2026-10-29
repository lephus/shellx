import Foundation
import Testing
@testable import ShellXRemoteCore

private final class Capture: @unchecked Sendable { var method = ""; var body = Data() }
private struct StubCore: ShellXCoreCalling {
    let reply: String
    let capture: Capture
    func call(method: String, json: Data) throws -> Data {
        capture.method = method; capture.body = json
        return Data(reply.utf8)
    }
}
private func client(_ reply: String) -> (ShellXCoreClient, Capture) {
    let c = Capture(); return (ShellXCoreClient(StubCore(reply: reply, capture: c)), c)
}
private func params(_ c: Capture) throws -> [String: JSONValue] { try JSONDecoder().decode([String: JSONValue].self, from: c.body) }

@Test func testNeedsYouSendsTheAgentAndWorkspaceAndReturnsHowManyPhonesGotIt() throws {
    let (core, cap) = client(#"{"ok":{"sent":2}}"#)
    let sent = try core.notifyPhones(.needsYou(requestID: "req-1", agent: "Claude Code", workspaceTitle: "shellx"))
    #expect(sent == 2)
    #expect(cap.method == "notify.phones")
    #expect(try params(cap) == [
        "kind": .string("needs_you"), "request_id": .string("req-1"),
        "agent": .string("Claude Code"), "workspace_title": .string("shellx"),
    ])
}

@Test func testResolvedSendsOnlyTheRequestId() throws {
    let (core, cap) = client(#"{"ok":{"sent":0}}"#)
    #expect(try core.notifyPhones(.resolved(requestID: "req-1")) == 0)
    #expect(try params(cap) == ["kind": .string("resolved"), "request_id": .string("req-1")])
}
