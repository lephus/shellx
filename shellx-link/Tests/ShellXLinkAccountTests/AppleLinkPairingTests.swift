import Foundation
import ShellXLinkCore
import XCTest
@testable import ShellXLinkAccount

final class AppleLinkPairingTests: XCTestCase {
    private let clientKey = Data((0..<32).map { UInt8(0x20 + $0) })
    private let hostKey = Data((0..<32).map { UInt8(0x40 + $0) })
    private let machineID = "6f1c2b7e-0d4a-4c1e-9a53-3b8e5d2f7a10"
    private func api() throws -> RelayAPI {
        try RelayAPI(baseURL: URL(string: "https://api.example.test")!, session: StubURLProtocol.session(), clientVersion: "1")
    }
    private func offer() -> PairingOffer { PairingOffer.make(machineID: machineID, linkSlot: "slot-1", hostKey: hostKey, machineName: "Mac") }
    /// The link request answers p-1; the status answers `pending` twice, then `final`.
    private func install(final: @escaping @Sendable () -> StubResponse) {
        let polls = PollCounter()
        StubURLProtocol.install { request in
            if request.path == "/v1/auth/apple/link" { return StubResponse(201, ["pairing_id": "p-1"]) }
            return polls.next() < 2 ? StubResponse(200, ["status": "pending"]) : final()
        }
    }
    private func approved(machineID: String? = nil, slot: String = "slot-1") -> StubResponse {
        StubResponse(200, [
            "status": "approved",
            "session": ["user_id": "u1", "device_id": "d1", "token": "tok-secret", "email": "owner@example.com"],
            "machine": ["machine_id": machineID ?? self.machineID, "name": "Relay Name", "link_slot": slot],
        ])
    }
    private func link(timeout: Duration = .seconds(5)) async throws -> AppleLinkApproval {
        try await AppleLinkPairing.link(
            offerURI: offer().uri, linkToken: "link-secret", clientKey: clientKey, api: api(),
            pollInterval: .milliseconds(5), timeout: timeout)
    }

    func testLinkPollsUntilApprovedAndKeepsTheOffersHostKey() async throws {
        let response = approved()
        install { response }
        let approval = try await link()
        XCTAssertEqual(approval.signIn, AccountSignIn(session: AccountSession(userID: "u1", deviceID: "d1", token: "tok-secret"), email: "owner@example.com"))
        XCTAssertEqual(approval.machine, PairedMachine(machineID: machineID, name: "Mac", linkSlot: "slot-1", hostKey: hostKey))
        let polls = StubURLProtocol.requests.filter { $0.path == "/v1/auth/apple/link/status" }
        XCTAssertEqual(polls.count, 3)
        XCTAssertEqual(polls.first?.json?["link_token"] as? String, "link-secret")
        XCTAssertEqual(polls.first?.json?["pairing_id"] as? String, "p-1")
        XCTAssertTrue(StubURLProtocol.requests.allSatisfy { $0.headers["Authorization"] == nil })
    }

    func testDeniedAndExpiredThrow() async throws {
        for (status, expected) in [("denied", PhonePairingError.denied), ("expired", .expired)] {
            install { StubResponse(200, ["status": status]) }
            do { _ = try await link(); XCTFail(status) } catch { XCTAssertEqual(error as? PhonePairingError, expected) }
        }
    }

    func testApprovalForAnotherMacOrSlotIsRefused() async throws {
        for response in [approved(machineID: "other"), approved(slot: "slot-2")] {
            install { response }
            do { _ = try await link(); XCTFail() } catch { XCTAssertEqual(error as? RelayAPIError, .badResponse) }
        }
    }

    func testRefusedLinkTokenStopsAtOnce() async throws {
        StubURLProtocol.install { request in
            request.path == "/v1/auth/apple/link" ? StubResponse(201, ["pairing_id": "p-1"])
                : StubResponse(401, ["error": ["code": "invalid_credentials", "message": "x"]])
        }
        do { _ = try await link(); XCTFail() } catch {
            XCTAssertEqual(error as? RelayAPIError, .http(status: 401, code: "invalid_credentials"))
        }
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.path == "/v1/auth/apple/link/status" }.count, 1)
    }

    func testTransientErrorsKeepPolling() async throws {
        let response = approved()
        let polls = PollCounter()
        StubURLProtocol.install { request in
            if request.path == "/v1/auth/apple/link" { return StubResponse(201, ["pairing_id": "p-1"]) }
            return polls.next() == 0 ? StubResponse(503) : response
        }
        let approval = try await link()
        XCTAssertEqual(approval.machine.machineID, machineID)
    }

    func testDeadlineExpires() async throws {
        install { StubResponse(200, ["status": "pending"]) }
        do { _ = try await link(timeout: .milliseconds(30)); XCTFail() } catch { XCTAssertEqual(error as? PhonePairingError, .expired) }
    }

    func testBadOfferNeverReachesTheRelay() async throws {
        StubURLProtocol.install { _ in StubResponse(500) }
        do {
            _ = try await AppleLinkPairing.link(offerURI: "shellx-link://pair?v=1", linkToken: "l", clientKey: clientKey, api: api())
            XCTFail()
        } catch { XCTAssertTrue(error is PairingOfferError, "\(error)") }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }
}
