import Foundation
import ShellXLinkAccount
import ShellXLinkCore
import ShellXLinkRelay
import ShellXLinkSession
import XCTest

@testable import ShellXAppCore

final class LinkFailureTests: XCTestCase {
    func testUnauthorizedIsSignedOut() {
        XCTAssertEqual(LinkFailure(RelayAPIError.http(status: 401, code: "unauthorized")), .signedOut)
        XCTAssertEqual(LinkFailure(RelayAPIError.http(status: 401, code: "unknown")), .signedOut)
    }

    func testNotGrantedIsRevoked() {
        XCTAssertEqual(LinkFailure(RelayAPIError.http(status: 403, code: "not_granted")), .revoked)
    }

    func testMachineNotFoundIsRevoked() {
        XCTAssertEqual(LinkFailure(RelayAPIError.http(status: 404, code: "machine_not_found")), .revoked)
    }

    func testUntrustedPeerIsHostKeyChanged() {
        XCTAssertEqual(LinkFailure(NoiseError.untrustedPeer), .hostKeyChanged)
    }

    func testSlotMismatchIsHostKeyChanged() {
        // The relay hands out a ticket for another slot than the one pinned at pairing: a pinning
        // failure like a changed host key, which retrying cannot fix.
        XCTAssertEqual(LinkFailure(RelayAPIError.slotMismatch), .hostKeyChanged)
    }

    func testProtocolMismatchIsNeedsUpdate() {
        XCTAssertEqual(LinkFailure(LinkClientError.protocolMismatch(message: "the host speaks protocol 2")), .needsUpdate)
    }

    func testOtherErrorsAreOffline() {
        let errors: [any Error] = [
            URLError(.notConnectedToInternet),
            URLError(.timedOut),
            RelayError.closed,
            RelayError.server(code: "slot-offline", retryable: true),
            LinkClientError.timedOut,
            LinkClientError.sessionClosed,
            LinkClientError.rejected(code: "busy", message: "later"),
            RelayAPIError.http(status: 500, code: "internal"),
            RelayAPIError.http(status: 403, code: "forbidden"),
            RelayAPIError.badResponse,
            NoiseError.decryptFailed,
            CancellationError(),
        ]
        for error in errors {
            XCTAssertEqual(LinkFailure(error), .offline, "\(error)")
        }
    }
}
