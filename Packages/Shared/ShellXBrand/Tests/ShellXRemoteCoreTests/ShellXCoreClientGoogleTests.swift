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

@Test func beginSendsThePurposeAndReturnsTheURL() throws {
    let (core, cap) = client(#"{"ok":{"flow_id":"f1","auth_url":"https://accounts.google.com/o/oauth2/v2/auth?client_id=x"}}"#)
    let start = try core.beginGoogleSignIn(purpose: .link)
    #expect(cap.method == "auth.google.begin")
    #expect(try params(cap) == ["purpose": .string("link")])
    #expect(start.flowID == "f1")
    #expect(start.authURL.scheme == "https")
}

@Test func beginRefusesANonHTTPSURL() {
    let (core, _) = client(#"{"ok":{"flow_id":"f1","auth_url":"http://evil.test/x"}}"#)
    do { _ = try core.beginGoogleSignIn(purpose: .signIn); Issue.record("expected throw") }
    catch let e as ShellXCoreError { #expect(e.code == "bad_response") }
    catch { Issue.record("wrong error") }
}

@Test func finishReturnsTheGoogleAccount() throws {
    let (core, cap) = client(#"{"ok":{"user_id":"u1","device_id":"d1","device_public_key_b64":"AAAA","fingerprint":"ff","email":"g@shellx.test","auth_method":"google"}}"#)
    let r = try core.finishGoogleSignIn(flowID: "f1")
    #expect(cap.method == "auth.google.finish")
    #expect(try params(cap) == ["flow_id": .string("f1")])
    #expect(r == GoogleSignInResult(userID: "u1", deviceID: "d1", email: "g@shellx.test", authMethod: "google"))
}

@Test func cancelAndRemoveSendTheirIDs() throws {
    let (core, cap) = client(#"{"ok":{}}"#)
    try core.cancelGoogleSignIn(flowID: "f9")
    #expect(cap.method == "auth.google.cancel"); #expect(try params(cap) == ["flow_id": .string("f9")])
    try core.removeSignInMethod(id: "a1")
    #expect(cap.method == "account.identities.remove"); #expect(try params(cap) == ["identity_id": .string("a1")])
}

@Test func signInMethodsDecodeTheRelayItems() throws {
    let (core, cap) = client(#"{"ok":{"identities":[{"identity_id":"a1","provider":"apple","email":"x@privaterelay.appleid.com","is_private_email":true,"linked_via_device_name":"Phu's iPhone","created_at_unix":100},{"identity_id":"g1","provider":"google","email":"g@shellx.test","is_private_email":false,"linked_via_device_name":null,"created_at_unix":50}]}}"#)
    let methods = try core.signInMethods()
    #expect(cap.method == "account.identities.list")
    #expect(methods.map(\.id) == ["a1", "g1"])
    #expect(methods[0].isApple && methods[0].isPrivateEmail)
    #expect(methods[0].linkedViaDeviceName == "Phu's iPhone")
    #expect(methods[0].createdAt == Date(timeIntervalSince1970: 100))
    #expect(!methods[1].isApple && methods[1].linkedViaDeviceName == nil)
}
