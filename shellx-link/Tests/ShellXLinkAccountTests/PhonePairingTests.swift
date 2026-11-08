import Foundation
import XCTest

import ShellXLinkCore

@testable import ShellXLinkAccount

final class PhonePairingTests: XCTestCase {
    private let clientKey = Data((0..<32).map { UInt8(0x20 + $0) })
    private let hostKey = Data((0..<32).map { UInt8(0x40 + $0) })
    private let machineID = "6f1c2b7e-0d4a-4c1e-9a53-3b8e5d2f7a10"

    private func api() throws -> RelayAPI {
        try RelayAPI(
            baseURL: URL(string: "https://api.example.test")!, session: StubURLProtocol.session(),
            clientVersion: "1")
    }

    private func offer() -> PairingOffer {
        PairingOffer.make(machineID: machineID, linkSlot: "slot-1", hostKey: hostKey, machineName: "Mac")
    }

    /// Serves POST /v2/phone-pairings and polls that answer `pending` twice, then `final`.
    private func install(final: @escaping @Sendable () -> StubResponse) {
        let polls = PollCounter()
        StubURLProtocol.install { request in
            if request.method == "POST" { return StubResponse(201, ["pairing_id": "p-1"]) }
            return polls.next() < 2 ? StubResponse(200, ["status": "pending"]) : final()
        }
    }

    private func approved(machineID: String? = nil, slot: String = "slot-1") -> StubResponse {
        StubResponse(200, [
            "status": "approved",
            "machine": ["machine_id": machineID ?? self.machineID, "name": "Relay Name", "link_slot": slot],
        ])
    }

    func testPairPollsUntilApproved() async throws {
        let response = approved()
        install { response }
        let offer = offer()
        let machine = try await PhonePairing.pair(
            offerURI: offer.uri, clientKey: clientKey, api: api(), token: "tok", pollInterval: .milliseconds(5))
        XCTAssertEqual(machine.machineID, machineID)
        XCTAssertEqual(machine.linkSlot, "slot-1")
        XCTAssertEqual(machine.hostKey, hostKey)

        let post = try XCTUnwrap(StubURLProtocol.requests.first { $0.method == "POST" })
        XCTAssertEqual(post.path, "/v2/phone-pairings")
        let body = try XCTUnwrap(post.json)
        XCTAssertEqual(body["machine_id"] as? String, machineID)
        XCTAssertEqual(body["client_key_b64"] as? String, clientKey.base64EncodedString())
        XCTAssertEqual(body["proof_b64"] as? String, offer.proof(clientKey: clientKey).base64EncodedString())
        let gets = StubURLProtocol.requests.filter { $0.method == "GET" }
        XCTAssertEqual(gets.count, 3)
        XCTAssertEqual(gets.first?.path, "/v2/phone-pairings/p-1")
    }

    func testPairDeniedThrows() async throws {
        install { StubResponse(200, ["status": "denied"]) }
        do {
            _ = try await PhonePairing.pair(
                offerURI: offer().uri, clientKey: clientKey, api: api(), token: "tok", pollInterval: .milliseconds(5))
            XCTFail("expected denied")
        } catch {
            XCTAssertEqual(error as? PhonePairingError, .denied)
        }
    }

    func testPairExpiredThrows() async throws {
        install { StubResponse(200, ["status": "expired"]) }
        do {
            _ = try await PhonePairing.pair(
                offerURI: offer().uri, clientKey: clientKey, api: api(), token: "tok", pollInterval: .milliseconds(5))
            XCTFail("expected expired")
        } catch {
            XCTAssertEqual(error as? PhonePairingError, .expired)
        }
    }

    func testHostKeyComesFromOfferNotRelay() async throws {
        // Even if the relay offered a key, the stored host key is the one in the QR offer.
        let response = StubResponse(200, [
            "status": "approved",
            "machine": [
                "machine_id": machineID, "name": "Relay Name", "link_slot": "slot-1",
                "host_key": "AAAA", "fingerprint": "ff",
            ],
        ])
        install { response }
        let machine = try await PhonePairing.pair(
            offerURI: offer().uri, clientKey: clientKey, api: api(), token: "tok", pollInterval: .milliseconds(5))
        XCTAssertEqual(machine.hostKey, hostKey)
        XCTAssertEqual(machine.name, "Mac")
    }

    func testApprovedSlotMismatchThrows() async throws {
        let response = approved(slot: "evil-slot")
        install { response }
        do {
            _ = try await PhonePairing.pair(
                offerURI: offer().uri, clientKey: clientKey, api: api(), token: "tok", pollInterval: .milliseconds(5))
            XCTFail("expected badResponse")
        } catch {
            XCTAssertEqual(error as? RelayAPIError, .badResponse)
        }
    }

    func testApprovedMachineMismatchThrows() async throws {
        let response = approved(machineID: "00000000-0000-4000-8000-000000000000")
        install { response }
        do {
            _ = try await PhonePairing.pair(
                offerURI: offer().uri, clientKey: clientKey, api: api(), token: "tok", pollInterval: .milliseconds(5))
            XCTFail("expected badResponse")
        } catch {
            XCTAssertEqual(error as? RelayAPIError, .badResponse)
        }
    }

    private var denyCalls: [StubRequest] {
        StubURLProtocol.requests.filter { $0.method == "POST" && $0.path.hasSuffix("/deny") }
    }

    func testMismatchedApprovalCancelsPairingOnce() async throws {
        let response = approved(slot: "evil-slot")
        install { response }
        do {
            _ = try await PhonePairing.pair(
                offerURI: offer().uri, clientKey: clientKey, api: api(), token: "tok", pollInterval: .milliseconds(5))
            XCTFail("expected badResponse")
        } catch {
            XCTAssertEqual(error as? RelayAPIError, .badResponse)
        }
        XCTAssertEqual(denyCalls.map(\.path), ["/v2/phone-pairings/p-1/deny"])
    }

    func testClientSideTimeoutExpiresAndCancels() async throws {
        StubURLProtocol.install { request in
            request.method == "POST" ? StubResponse(201, ["pairing_id": "p-1"]) : StubResponse(200, ["status": "pending"])
        }
        do {
            _ = try await PhonePairing.pair(
                offerURI: offer().uri, clientKey: clientKey, api: api(), token: "tok",
                pollInterval: .milliseconds(5), timeout: .milliseconds(60))
            XCTFail("expected expired")
        } catch {
            XCTAssertEqual(error as? PhonePairingError, .expired)
        }
        XCTAssertEqual(denyCalls.count, 1)
    }

    func testCancellationCancelsPairing() async throws {
        StubURLProtocol.install { request in
            request.method == "POST" ? StubResponse(201, ["pairing_id": "p-1"]) : StubResponse(200, ["status": "pending"])
        }
        let api = try api()
        let uri = offer().uri
        let key = clientKey
        let task = Task {
            try await PhonePairing.pair(
                offerURI: uri, clientKey: key, api: api, token: "tok", pollInterval: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(80))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled, "\(error)")
        }
        XCTAssertEqual(denyCalls.count, 1)
    }

    func testServerDenyDoesNotCallDenyAgain() async throws {
        install { StubResponse(200, ["status": "denied"]) }
        _ = try? await PhonePairing.pair(
            offerURI: offer().uri, clientKey: clientKey, api: api(), token: "tok", pollInterval: .milliseconds(5))
        XCTAssertTrue(denyCalls.isEmpty)
    }

    func testTransientPollErrorsAreRetried() async throws {
        let polls = PollCounter()
        let response = approved()
        StubURLProtocol.install { request in
            if request.method == "POST" { return StubResponse(201, ["pairing_id": "p-1"]) }
            switch polls.next() {
            case 0: return StubResponse(503, ["error": ["code": "relay_v2_unavailable", "message": "x"]])
            case 1: return StubResponse(502)
            default: return response
            }
        }
        let machine = try await PhonePairing.pair(
            offerURI: offer().uri, clientKey: clientKey, api: api(), token: "tok", pollInterval: .milliseconds(5))
        XCTAssertEqual(machine.machineID, machineID)
        XCTAssertTrue(denyCalls.isEmpty)
    }

    func testClientErrorWhilePollingAborts() async throws {
        StubURLProtocol.install { request in
            request.method == "POST"
                ? StubResponse(201, ["pairing_id": "p-1"])
                : StubResponse(404, ["error": ["code": "pairing_not_found", "message": "x"]])
        }
        do {
            _ = try await PhonePairing.pair(
                offerURI: offer().uri, clientKey: clientKey, api: api(), token: "tok", pollInterval: .milliseconds(5))
            XCTFail("expected http error")
        } catch {
            XCTAssertEqual(error as? RelayAPIError, .http(status: 404, code: "pairing_not_found"))
        }
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.method == "GET" }.count, 1)
    }

    func testPairReportsTheRequestIdBeforeItPolls() async throws {
        let response = approved()
        install { response }
        let reported = Reported()
        _ = try await PhonePairing.pair(
            offerURI: offer().uri, clientKey: clientKey, api: api(), token: "tok", pollInterval: .milliseconds(5),
            onRequested: { id in reported.set(id, requestsSoFar: StubURLProtocol.requests.count) })
        XCTAssertEqual(reported.id, "p-1")
        XCTAssertEqual(reported.requestsSoFar, 1, "reported after the POST, before the first poll")
    }

    func testBadOfferNeverReachesRelay() async throws {
        StubURLProtocol.install { _ in StubResponse(500) }
        do {
            _ = try await PhonePairing.pair(
                offerURI: "https://example.com", clientKey: clientKey, api: api(), token: "tok")
            XCTFail("expected badURI")
        } catch {
            XCTAssertEqual(error as? PairingOfferError, .badURI)
        }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }
}

private final class Reported: @unchecked Sendable {
    private let lock = NSLock()
    private var values: (id: String?, requestsSoFar: Int?) = (nil, nil)
    var id: String? { lock.withLock { values.id } }
    var requestsSoFar: Int? { lock.withLock { values.requestsSoFar } }
    func set(_ id: String, requestsSoFar: Int) { lock.withLock { values = (id, requestsSoFar) } }
}
