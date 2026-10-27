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

private let key = Data(repeating: 7, count: 32)
private let proof = Data(repeating: 9, count: 32)

@Test func testPendingDecodesKeysAndProof() throws {
    let (core, cap) = client(#"{"ok":{"pairings":[{"pairing_id":"p1","device_name":"iPhone","platform":"ios","client_key_b64":"\#(key.base64EncodedString())","proof_b64":"\#(proof.base64EncodedString())","created_at_unix":100}]}}"#)
    let pending = try core.pendingPhonePairings()
    #expect(cap.method == "phones.pending")
    #expect(pending == [PhonePairingRequest(id: "p1", deviceName: "iPhone", platform: "ios", clientKey: key, proof: proof, createdAt: Date(timeIntervalSince1970: 100))])
    #expect(!"\(pending[0])".contains(proof.base64EncodedString()))
}

@Test func testBadKeyLengthIsBadResponse() {
    let short = Data(repeating: 1, count: 31).base64EncodedString()
    let (core, _) = client(#"{"ok":{"pairings":[{"pairing_id":"p1","device_name":"iPhone","platform":"ios","client_key_b64":"\#(short)","proof_b64":"\#(proof.base64EncodedString())","created_at_unix":100}]}}"#)
    #expect(throws: ShellXCoreError.self) { try core.pendingPhonePairings() }
    do { _ = try core.pendingPhonePairings() } catch let e as ShellXCoreError { #expect(e.code == "bad_response") } catch { Issue.record("wrong error") }
    let (core2, _) = client(#"{"ok":{"grants":[{"grant_id":"g1","device_id":"d1","device_name":"iPhone","platform":"ios","client_key_b64":"!!","created_at_unix":1,"last_seen_unix":null}]}}"#)
    do { _ = try core2.pairedPhones(); Issue.record("expected throw") } catch let e as ShellXCoreError { #expect(e.code == "bad_response") } catch { Issue.record("wrong error") }
}

@Test func pairedPhonesDecodesLastSeen() throws {
    let (core, cap) = client(#"{"ok":{"grants":[{"grant_id":"g1","device_id":"d1","device_name":"iPhone","platform":"ios","client_key_b64":"\#(key.base64EncodedString())","created_at_unix":10,"last_seen_unix":20},{"grant_id":"g2","device_id":"d2","device_name":"iPad","platform":"ios","client_key_b64":"\#(key.base64EncodedString())","created_at_unix":11,"last_seen_unix":null}]}}"#)
    let phones = try core.pairedPhones()
    #expect(cap.method == "phones.grants")
    #expect(phones.map(\.grantID) == ["g1", "g2"])
    #expect(phones[0] == PairedPhone(grantID: "g1", deviceID: "d1", deviceName: "iPhone", platform: "ios", clientKey: key, createdAt: Date(timeIntervalSince1970: 10), lastSeen: Date(timeIntervalSince1970: 20)))
    #expect(phones[1].lastSeen == nil)
}

@Test func approveDenyRevokeSendTheirIDs() throws {
    let (core, cap) = client(#"{"ok":{}}"#)
    try core.approvePhonePairing("p1")
    #expect(cap.method == "phones.approve"); #expect(try params(cap) == ["pairing_id": .string("p1")])
    try core.denyPhonePairing("p2")
    #expect(cap.method == "phones.deny"); #expect(try params(cap) == ["pairing_id": .string("p2")])
    try core.revokePhone(grantID: "g3")
    #expect(cap.method == "phones.revoke"); #expect(try params(cap) == ["grant_id": .string("g3")])
}

@Test func phoneErrorsKeepTheServerCode() {
    let (core, _) = client(#"{"error":{"code":"pairing_expired","message":"m"}}"#)
    #expect(throws: ShellXCoreError(code: "pairing_expired", message: "m")) { try core.approvePhonePairing("p1") }
}
