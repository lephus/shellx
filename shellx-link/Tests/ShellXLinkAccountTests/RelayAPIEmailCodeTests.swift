import Foundation
import ShellXLinkCore
import XCTest
@testable import ShellXLinkAccount

/// The relay calls of sign-in with an emailed code: `POST /v1/auth/email/code`, `POST /v1/auth/email/verify` and
/// `DELETE /v1/account` with a code.
final class RelayAPIEmailCodeTests: XCTestCase {
    private let clientKey = Data((0..<32).map { UInt8(0x20 + $0) })
    private let id = String(repeating: "aB3_-", count: 8) + "xyz"   // 43 base64url characters
    private func api() throws -> RelayAPI {
        try RelayAPI(baseURL: URL(string: "https://api.example.test")!, session: StubURLProtocol.session(), clientVersion: "9.9.9")
    }
    private static func refusal(_ status: Int, _ code: String) -> StubResponse {
        StubResponse(status, ["error": ["code": code, "message": "x"]])
    }

    func testRequestEmailCodePostsTheEmailAndTheLocaleWithoutToken() async throws {
        let id = id
        StubURLProtocol.install { _ in
            StubResponse(202, ["challenge_id": id, "expires_in": 600, "resend_in": 60, "email": "phu@example.com"])
        }
        let got = try await api().requestEmailCode(email: " Phu@Example.com ", locale: "vi")
        XCTAssertEqual(got, EmailChallenge(challengeID: id, expiresIn: 600, resendIn: 60, email: "phu@example.com"))
        XCTAssertFalse("\(got)".contains(id))
        XCTAssertFalse(String(reflecting: got).contains("phu@example.com"))
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/auth/email/code")
        XCTAssertNil(request.headers["Authorization"])
        // Sent as given: the relay normalizes.
        XCTAssertEqual(request.json as? [String: String], ["email": " Phu@Example.com ", "locale": "vi"])
    }

    func testAChallengeTheApiDoesNotDocumentIsRefused() async throws {
        let valid: [String: Any] = ["challenge_id": id, "expires_in": 600, "resend_in": 60, "email": "phu@example.com"]
        let changes: [(String, Any?)] = [
            ("challenge_id", nil), ("challenge_id", "has space"), ("challenge_id", String(repeating: "a", count: 129)),
            ("expires_in", 0), ("resend_in", -1), ("email", ""),
        ]
        for (field, value) in changes {
            var reply = valid
            reply[field] = value
            let response = StubResponse(202, reply)   // StubResponse is Sendable; the dictionary is not
            StubURLProtocol.install { _ in response }
            do { _ = try await api().requestEmailCode(email: "phu@example.com", locale: "en"); XCTFail("accepted \(field)") } catch {
                XCTAssertEqual(error as? RelayAPIError, .badResponse, field)
            }
        }
    }

    func testTheCodeRequestKeepsEveryRelayErrorCode() async throws {
        let refusals = [
            (400, "invalid_email"), (400, "disposable_email"), (429, "rate_limited"), (503, "email_sign_in_disabled"),
            (502, "email_send_failed"), (404, "not_found"),
        ]
        for (status, code) in refusals {
            StubURLProtocol.install { _ in Self.refusal(status, code) }
            do { _ = try await api().requestEmailCode(email: "phu@example.com", locale: "en"); XCTFail(code) } catch {
                XCTAssertEqual(error as? RelayAPIError, .http(status: status, code: code))
            }
        }
    }

    func testSignInWithEmailCodeSendsTheChallengeTheCodeAndTheMobileDevice() async throws {
        StubURLProtocol.install { _ in
            StubResponse(200, ["user_id": "u1", "device_id": "d1", "token": "tok-secret", "email": "phu@example.com"])
        }
        let got = try await api().signInWithEmailCode(challengeID: id, code: "012345", deviceName: "Phu's iPhone", clientKey: clientKey)
        XCTAssertEqual(
            got, AccountSignIn(session: AccountSession(userID: "u1", deviceID: "d1", token: "tok-secret"), email: "phu@example.com"))
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/auth/email/verify")
        XCTAssertNil(request.headers["Authorization"])
        let json = try XCTUnwrap(request.json)
        XCTAssertEqual(Set(json.keys), ["challenge_id", "code", "device"])
        XCTAssertEqual(json["challenge_id"] as? String, id)
        XCTAssertEqual(json["code"] as? String, "012345")   // a string: the leading zero stays
        XCTAssertEqual(
            json["device"] as? [String: String],
            ["kind": "mobile", "platform": "ios", "name": "Phu's iPhone", "public_key": "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8"])

        let refusals = [
            (401, "invalid_code"), (410, "code_expired"), (409, "switch_from_signed_in_device"), (400, "invalid_device"),
            (429, "rate_limited"),
        ]
        for (status, code) in refusals {
            StubURLProtocol.install { _ in Self.refusal(status, code) }
            do { _ = try await api().signInWithEmailCode(challengeID: id, code: "012345", deviceName: "p", clientKey: clientKey); XCTFail(code) } catch {
                XCTAssertEqual(error as? RelayAPIError, .http(status: status, code: code))
            }
        }

        StubURLProtocol.install { _ in StubResponse(200, ["user_id": "u1", "device_id": "d1", "token": "tok-secret"]) }
        do { _ = try await api().signInWithEmailCode(challengeID: id, code: "012345", deviceName: "p", clientKey: clientKey); XCTFail() } catch {
            XCTAssertEqual(error as? RelayAPIError, .badResponse)
        }
    }

    func testDeleteAccountByCodeSendsTheBearerTheChallengeAndTheCode() async throws {
        StubURLProtocol.install { _ in StubResponse(204) }
        try await api().deleteAccount(challengeID: id, code: "123456", token: "tok")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "DELETE")
        XCTAssertEqual(request.path, "/v1/account")
        XCTAssertEqual(request.headers["Authorization"], "Bearer tok")
        XCTAssertEqual(request.json as? [String: String], ["challenge_id": id, "code": "123456"])

        for (status, code) in [(401, "invalid_code"), (410, "code_expired"), (401, "reauth_required")] {
            StubURLProtocol.install { _ in Self.refusal(status, code) }
            do { try await api().deleteAccount(challengeID: id, code: "123456", token: "tok"); XCTFail(code) } catch {
                XCTAssertEqual(error as? RelayAPIError, .http(status: status, code: code))
            }
        }
    }
}
