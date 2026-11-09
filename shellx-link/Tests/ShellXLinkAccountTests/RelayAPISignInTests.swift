import Foundation
import ShellXLinkCore
import XCTest
@testable import ShellXLinkAccount

final class RelayAPISignInTests: XCTestCase {
    private let clientKey = Data((0..<32).map { UInt8(0x20 + $0) })
    private static let reply: [String: String] = ["user_id": "u1", "device_id": "d1", "token": "tok-secret", "email": "g@example.com"]
    private let signIn = AccountSignIn(session: AccountSession(userID: "u1", deviceID: "d1", token: "tok-secret"), email: "g@example.com")
    private func api() throws -> RelayAPI {
        try RelayAPI(baseURL: URL(string: "https://api.example.test")!, session: StubURLProtocol.session(), clientVersion: "9.9.9")
    }

    func testNoncePostsAnEmptyObjectWithoutToken() async throws {
        let nonce = String(repeating: "aB3_-", count: 8) + "xyz"   // 43 base64url characters
        StubURLProtocol.install { _ in StubResponse(201, ["nonce": nonce, "expires_in": 600]) }
        let got = try await api().nonce()
        XCTAssertEqual(got, nonce)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/auth/nonce")
        XCTAssertNil(request.headers["Authorization"])
        XCTAssertEqual(request.json?.count, 0)
    }

    func testNonceOutsideBase64URLIsRefused() async throws {
        for bad in ["", "has space", "slash/es", String(repeating: "a", count: 129)] {
            StubURLProtocol.install { _ in StubResponse(201, ["nonce": bad, "expires_in": 600]) }
            do { _ = try await api().nonce(); XCTFail("accepted \(bad)") } catch {
                XCTAssertEqual(error as? RelayAPIError, .badResponse)
            }
        }
    }

    func testGoogleSignInSendsTokenNonceAndMobileDevice() async throws {
        StubURLProtocol.install { _ in StubResponse(200, Self.reply) }
        let got = try await api().signInWithGoogle(idToken: "id-secret", nonce: "n-1", deviceName: "Phu's iPhone", clientKey: clientKey)
        XCTAssertEqual(got, signIn)
        XCTAssertFalse("\(got)".contains("tok-secret"))
        XCTAssertFalse(String(reflecting: got).contains("g@example.com"))
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.path, "/v1/auth/google")
        XCTAssertNil(request.headers["Authorization"])
        let body = try XCTUnwrap(request.json)
        XCTAssertEqual(body["id_token"] as? String, "id-secret")
        XCTAssertEqual(body["nonce"] as? String, "n-1")
        let device = try XCTUnwrap(body["device"] as? [String: Any])
        XCTAssertEqual(device["kind"] as? String, "mobile")
        XCTAssertEqual(device["platform"] as? String, "ios")
        XCTAssertEqual(device["name"] as? String, "Phu's iPhone")
        XCTAssertEqual(device["public_key"] as? String, "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8")
    }

    func testGoogleSignInKeepsTheRelayErrorCode() async throws {
        for (status, code) in [(409, "switch_from_signed_in_device"), (401, "invalid_credentials")] {
            StubURLProtocol.install { _ in StubResponse(status, ["error": ["code": code, "message": "x"]]) }
            do { _ = try await api().signInWithGoogle(idToken: "i", nonce: "n", deviceName: "p", clientKey: clientKey); XCTFail() } catch {
                XCTAssertEqual(error as? RelayAPIError, .http(status: status, code: code))
            }
        }
    }

    func testLinkGoogleSendsTheBearerAndNoDevice() async throws {
        StubURLProtocol.install { _ in StubResponse(200, Self.reply) }
        let got = try await api().linkGoogle(idToken: "id-secret", nonce: "n-1", token: "tok-old")
        XCTAssertEqual(got, signIn)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.path, "/v1/auth/google/link")
        XCTAssertEqual(request.headers["Authorization"], "Bearer tok-old")
        XCTAssertEqual(Set(try XCTUnwrap(request.json).keys), ["id_token", "nonce"])
    }

    func testAppleSignInSignedInOrLinkRequired() async throws {
        StubURLProtocol.install { _ in StubResponse(200, Self.reply) }
        let signedIn = try await api().signInWithApple(
            identityToken: "apple-secret", authorizationCode: "code-secret", nonce: "n-1", deviceName: "p", clientKey: clientKey)
        XCTAssertEqual(signedIn, .signedIn(signIn))
        let body = try XCTUnwrap(StubURLProtocol.requests.first?.json)
        XCTAssertEqual(body["identity_token"] as? String, "apple-secret")
        XCTAssertEqual(body["authorization_code"] as? String, "code-secret")
        XCTAssertEqual(body["nonce"] as? String, "n-1")
        XCTAssertEqual((body["device"] as? [String: Any])?["platform"] as? String, "ios")
        XCTAssertEqual(StubURLProtocol.requests.first?.path, "/v1/auth/apple")

        StubURLProtocol.install { _ in StubResponse(202, ["status": "link_required", "link_token": "link-secret", "expires_in": 600]) }
        let link = try await api().signInWithApple(
            identityToken: "a", authorizationCode: "c", nonce: "n", deviceName: "p", clientKey: clientKey)
        XCTAssertEqual(link, .linkRequired(linkToken: "link-secret", expiresIn: 600))
    }

    func testAppleSignInWithAnOddReplyIsABadResponse() async throws {
        for reply: [String: Any] in [["status": "weird"], ["status": "link_required", "expires_in": 600]] {
            let response = StubResponse(202, reply)   // StubResponse is Sendable; the dictionary is not
            StubURLProtocol.install { _ in response }
            do { _ = try await api().signInWithApple(identityToken: "a", authorizationCode: "c", nonce: "n", deviceName: "p", clientKey: clientKey); XCTFail() } catch {
                XCTAssertEqual(error as? RelayAPIError, .badResponse)
            }
        }
    }

    func testRequestAppleLinkSendsTheProofWithoutToken() async throws {
        let offer = PairingOffer.make(
            machineID: "6f1c2b7e-0d4a-4c1e-9a53-3b8e5d2f7a10", linkSlot: "slot-1",
            hostKey: Data((0..<32).map { UInt8(0x40 + $0) }), machineName: "Mac")
        StubURLProtocol.install { _ in StubResponse(201, ["pairing_id": "p-1"]) }
        let id = try await api().requestAppleLink(linkToken: "link-secret", offer: offer, clientKey: clientKey)
        XCTAssertEqual(id, "p-1")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.path, "/v1/auth/apple/link")
        XCTAssertNil(request.headers["Authorization"])
        let body = try XCTUnwrap(request.json)
        XCTAssertEqual(body["link_token"] as? String, "link-secret")
        XCTAssertEqual(body["machine_id"] as? String, offer.machineID)
        XCTAssertEqual(body["client_key_b64"] as? String, clientKey.base64EncodedString())
        XCTAssertEqual(body["proof_b64"] as? String, offer.proof(clientKey: clientKey).base64EncodedString())

        StubURLProtocol.install { _ in StubResponse(201, ["pairing_id": "../x"]) }
        do { _ = try await api().requestAppleLink(linkToken: "l", offer: offer, clientKey: clientKey); XCTFail() } catch {
            XCTAssertEqual(error as? RelayAPIError, .badResponse)
        }
    }

    func testAppleLinkStatusReadsEveryState() async throws {
        for (status, expected) in [("pending", AppleLinkStatus.pending), ("denied", .denied), ("expired", .expired)] {
            StubURLProtocol.install { _ in StubResponse(200, ["status": status]) }
            let got = try await api().appleLinkStatus(linkToken: "link-secret", pairingID: "p-1")
            XCTAssertEqual(got, expected)
        }
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.path, "/v1/auth/apple/link/status")
        XCTAssertEqual(request.json?["link_token"] as? String, "link-secret")
        XCTAssertEqual(request.json?["pairing_id"] as? String, "p-1")

        StubURLProtocol.install { _ in
            StubResponse(200, ["status": "approved", "session": Self.reply, "machine": ["machine_id": "m1", "name": "Mac", "link_slot": "slot-1"]])
        }
        let approved = try await api().appleLinkStatus(linkToken: "l", pairingID: "p-1")
        XCTAssertEqual(approved, .approved(signIn, machineID: "m1", name: "Mac", linkSlot: "slot-1"))

        for reply: [String: Any] in [["status": "approved", "machine": ["machine_id": "m1", "name": "Mac", "link_slot": "s"]], ["status": "later"]] {
            let response = StubResponse(200, reply)
            StubURLProtocol.install { _ in response }
            do { _ = try await api().appleLinkStatus(linkToken: "l", pairingID: "p-1"); XCTFail() } catch {
                XCTAssertEqual(error as? RelayAPIError, .badResponse)
            }
        }
    }

    func testDeleteAccountSendsAFreshTokenWithTheBearer() async throws {
        StubURLProtocol.install { _ in StubResponse(204) }
        try await api().deleteAccount(idToken: "fresh-id", nonce: "n-2", token: "tok")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "DELETE")
        XCTAssertEqual(request.path, "/v1/account")
        XCTAssertEqual(request.headers["Authorization"], "Bearer tok")
        XCTAssertEqual(request.json?["id_token"] as? String, "fresh-id")
        XCTAssertEqual(request.json?["nonce"] as? String, "n-2")

        StubURLProtocol.install { _ in StubResponse(401, ["error": ["code": "reauth_required", "message": "x"]]) }
        do { try await api().deleteAccount(idToken: "old", nonce: "n", token: "tok"); XCTFail() } catch {
            XCTAssertEqual(error as? RelayAPIError, .http(status: 401, code: "reauth_required"))
        }
    }
}
