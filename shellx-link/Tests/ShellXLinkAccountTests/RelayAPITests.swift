import Foundation
import XCTest

import ShellXLinkRelay

@testable import ShellXLinkAccount

final class RelayAPITests: XCTestCase {
    private let base = URL(string: "https://api.example.test")!
    private let clientKey = Data((0..<32).map { UInt8(0x20 + $0) })

    private func api(_ url: URL? = nil) throws -> RelayAPI {
        try RelayAPI(baseURL: url ?? base, session: StubURLProtocol.session(), clientVersion: "9.9.9")
    }

    func testLoginSendsMobileDevice() async throws {
        StubURLProtocol.install { _ in
            StubResponse(200, ["user_id": "u1", "device_id": "d1", "token": "tok-secret"])
        }
        let session = try await api().login(
            email: "a@b.c", password: "pw-secret", deviceName: "Phu's iPhone", clientKey: clientKey)
        XCTAssertEqual(session.userID, "u1")
        XCTAssertEqual(session.deviceID, "d1")
        XCTAssertEqual(session.token, "tok-secret")
        XCTAssertFalse("\(session)".contains("tok-secret"))
        XCTAssertFalse(String(reflecting: session).contains("tok-secret"))

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/auth/login")
        XCTAssertEqual(request.headers["X-ShellX-Version"], "9.9.9")
        XCTAssertNil(request.headers["Authorization"])
        let body = try XCTUnwrap(request.json)
        XCTAssertEqual(body["email"] as? String, "a@b.c")
        XCTAssertEqual(body["password"] as? String, "pw-secret")
        let device = try XCTUnwrap(body["device"] as? [String: Any])
        XCTAssertEqual(device["kind"] as? String, "mobile")
        XCTAssertEqual(device["platform"] as? String, "ios")
        XCTAssertEqual(device["name"] as? String, "Phu's iPhone")
        XCTAssertEqual(device["public_key"] as? String, "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8")
    }

    func testLoginUsesBase64URLAlphabetForPublicKey() async throws {
        // Standard base64 of this key starts with "+/+/" and ends with "=".
        let key = Data([0xFB, 0xFF, 0xBF] + [UInt8](repeating: 0, count: 29))
        XCTAssertTrue(key.base64EncodedString().hasPrefix("+/+/"))
        StubURLProtocol.install { _ in StubResponse(200, ["user_id": "u", "device_id": "d", "token": "t"]) }
        _ = try await api().login(email: "a@b.c", password: "pw", deviceName: "p", clientKey: key)
        let device = try XCTUnwrap(StubURLProtocol.requests.first?.json?["device"] as? [String: Any])
        let publicKey = try XCTUnwrap(device["public_key"] as? String)
        XCTAssertEqual(publicKey, "-_-_" + String(repeating: "A", count: 39))
        XCTAssertFalse(publicKey.contains("+") || publicKey.contains("/") || publicKey.contains("="))
    }

    func testRedirectIsRefusedAndNotFollowed() async throws {
        StubURLProtocol.install { request in
            request.host == "api.example.test"
                ? StubResponse(307, location: "https://evil.example.test/steal") : StubResponse(200, ["token": "x"])
        }
        do {
            _ = try await api().login(email: "a@b.c", password: "pw-secret", deviceName: "p", clientKey: clientKey)
            XCTFail("expected an error")
        } catch {
            let isHTTP = (error as? RelayAPIError).map {
                if case .http(status: 307, _) = $0 { return true } else { return $0 == .badResponse }
            }
            XCTAssertEqual(isHTTP, true, "\(error)")
        }
        XCTAssertEqual(StubURLProtocol.requests.map(\.host), ["api.example.test"])

        StubURLProtocol.install { request in
            request.host == "api.example.test"
                ? StubResponse(302, location: "https://evil.example.test/steal") : StubResponse(200, ["grants": []])
        }
        do {
            _ = try await api().machines(token: "tok-secret")
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error is RelayAPIError, "\(error)")
        }
        XCTAssertEqual(StubURLProtocol.requests.map(\.host), ["api.example.test"])
    }

    func testCancelPairingPostsDeny() async throws {
        StubURLProtocol.install { _ in StubResponse(204) }
        try await api().cancelPairing(id: "p-1", token: "tok")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v2/phone-pairings/p-1/deny")
        XCTAssertEqual(request.headers["Authorization"], "Bearer tok")
    }

    func testMintChecksSlotClaim() async throws {
        StubURLProtocol.install { _ in
            StubResponse(200, [
                "ticket": stubTicket(slot: "other-slot"), "expires_at_unix": 1_900_000_000,
                "relay_url": "wss://relay.example.test/v2/relay",
            ])
        }
        do {
            _ = try await api().mintConnectTicket(machineID: "m1", expectedSlot: "slot-1", token: "tok")
            XCTFail("expected slotMismatch")
        } catch {
            XCTAssertEqual(error as? RelayAPIError, .slotMismatch)
        }

        StubURLProtocol.install { _ in
            StubResponse(200, [
                "ticket": stubTicket(slot: "slot-1"), "expires_at_unix": 1_900_000_000,
                "relay_url": "wss://relay.example.test/v2/relay",
            ])
        }
        let minted = try await api().mintConnectTicket(machineID: "m1", expectedSlot: "slot-1", token: "tok")
        XCTAssertEqual(minted.relayURL.absoluteString, "wss://relay.example.test/v2/relay")
        XCTAssertEqual(minted.ticket.expiresAtUnix, 1_900_000_000)
        let request = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(request.path, "/v2/relay/tickets")
        XCTAssertEqual(request.headers["Authorization"], "Bearer tok")
        let body = try XCTUnwrap(request.json)
        XCTAssertEqual(body["permission"] as? String, "connect")
        XCTAssertEqual(body["lane"] as? String, "link")
        XCTAssertEqual(body["target_machine_id"] as? String, "m1")
    }

    func testMintRejectsRegisterTicket() async throws {
        StubURLProtocol.install { _ in
            StubResponse(200, [
                "ticket": stubTicket(slot: "slot-1", permission: "register", role: "daemon"),
                "expires_at_unix": 1_900_000_000, "relay_url": "wss://relay.example.test/v2/relay",
            ])
        }
        do {
            _ = try await api().mintConnectTicket(machineID: "m1", expectedSlot: "slot-1", token: "tok")
            XCTFail("expected notConnectTicket")
        } catch {
            XCTAssertEqual(error as? RelayAPIError, .notConnectTicket)
        }
    }

    func testHTTPErrorCodeSurfaced() async throws {
        StubURLProtocol.install { _ in
            StubResponse(403, ["error": ["code": "not_granted", "message": "no"]])
        }
        do {
            _ = try await api().machines(token: "tok")
            XCTFail("expected http error")
        } catch {
            XCTAssertEqual(error as? RelayAPIError, .http(status: 403, code: "not_granted"))
        }
        StubURLProtocol.install { _ in StubResponse(502) }
        do {
            try await api().unpair(grantID: "g1", token: "tok")
            XCTFail("expected http error")
        } catch {
            XCTAssertEqual(error as? RelayAPIError, .http(status: 502, code: "unknown"))
        }
    }

    func testPlainHTTPRefusedForRemoteHost() throws {
        XCTAssertThrowsError(
            try RelayAPI(baseURL: URL(string: "http://api.example.test")!, clientVersion: "1")
        ) { error in
            XCTAssertEqual(error as? RelayError, .insecureTransport(scheme: "http"))
        }
        XCTAssertNoThrow(try RelayAPI(baseURL: URL(string: "http://127.0.0.1:8080")!, clientVersion: "1"))
        XCTAssertNoThrow(try RelayAPI(baseURL: URL(string: "http://localhost:8080")!, clientVersion: "1"))
        XCTAssertNoThrow(try RelayAPI(baseURL: URL(string: "https://api.example.test")!, clientVersion: "1"))
    }

    func testMachinesAndUnpair() async throws {
        StubURLProtocol.install { request in
            if request.method == "DELETE" { return StubResponse(204) }
            return StubResponse(200, [
                "grants": [[
                    "grant_id": "g1", "machine_id": "m1", "name": "Mac", "platform": "macos",
                    "online": true, "link_slot": "slot-1", "fingerprint": "ab:cd",
                ]],
            ])
        }
        let machines = try await api().machines(token: "tok")
        XCTAssertEqual(
            machines,
            [PairedMachineListing(
                grantID: "g1", machineID: "m1", name: "Mac", platform: "macos", online: true,
                linkSlot: "slot-1", fingerprint: "ab:cd")])
        try await api().unpair(grantID: "g1", token: "tok")
        let last = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(last.method, "DELETE")
        XCTAssertEqual(last.path, "/v2/phone-grants/g1")
    }
}
