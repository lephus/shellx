import Foundation
import Testing
@testable import ShellXRemoteCore

@Suite("Core client: email sign-in") struct ShellXCoreClientEmailTests {
    /// The last call's method and params. Written and read on the test's own thread only (the stub core is called
    /// synchronously), so the unchecked conformance is safe.
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

    private func params(_ c: Capture) throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: c.body)
    }

    @Test func beginSendsTheAddressAndLocaleAndReturnsTheChallenge() throws {
        let (core, cap) = client(#"{"ok":{"challenge_id":"ch1","expires_in":600,"resend_in":60,"email":"foo@bar.com"}}"#)
        let challenge = try core.beginEmailSignIn(email: "Foo@Bar.com", locale: "vi")
        #expect(cap.method == "auth.email.begin")
        #expect(try params(cap) == ["email": .string("Foo@Bar.com"), "locale": .string("vi")])
        #expect(challenge == EmailCodeChallenge(challengeID: "ch1", email: "foo@bar.com", expiresIn: 600, resendIn: 60))
    }

    @Test func beginRefusesAReplyWithoutAChallenge() throws {
        let (core, _) = client(#"{"ok":{"challenge_id":"","expires_in":600,"resend_in":60,"email":"foo@bar.com"}}"#)
        do {
            _ = try core.beginEmailSignIn(email: "foo@bar.com", locale: "en")
            Issue.record("expected a throw")
        } catch let e as ShellXCoreError {
            #expect(e.code == "bad_response")
        }
    }

    @Test func finishSendsTheChallengeAndCodeAndReturnsTheAccount() throws {
        let (core, cap) = client(#"{"ok":{"user_id":"u1","device_id":"d1","device_public_key_b64":"AAAA","fingerprint":"ff","email":"foo@bar.com","auth_method":"email"}}"#)
        let result = try core.finishEmailSignIn(challengeID: "ch1", code: "004217")
        #expect(cap.method == "auth.email.finish")
        #expect(try params(cap) == ["challenge_id": .string("ch1"), "code": .string("004217")])
        #expect(result == GoogleSignInResult(userID: "u1", deviceID: "d1", email: "foo@bar.com", authMethod: "email"))
    }

    @Test func emailCallsKeepTheCoreErrorCode() throws {
        let (core, _) = client(#"{"error":{"code":"switch_from_signed_in_device","message":"x"}}"#)
        do {
            _ = try core.finishEmailSignIn(challengeID: "ch1", code: "004217")
            Issue.record("expected a throw")
        } catch let e as ShellXCoreError {
            #expect(e.code == "switch_from_signed_in_device")
        }
        do {
            _ = try core.beginEmailSignIn(email: "foo@bar.com", locale: "en")
            Issue.record("expected a throw")
        } catch let e as ShellXCoreError {
            #expect(e.code == "switch_from_signed_in_device")
        }
    }

    @Test func signInMethodKindsFollowTheProvider() throws {
        let (core, _) = client(#"{"ok":{"identities":[{"identity_id":"e1","provider":"email","email":"foo@bar.com"},{"identity_id":"g1","provider":"google","email":"g@x"},{"identity_id":"a1","provider":"apple"},{"identity_id":"t1","provider":"test"}]}}"#)
        let methods = try core.signInMethods()
        #expect(methods.map(\.kind) == [.email, .google, .apple, .google])
        #expect(!methods[0].isApple)
    }
}
