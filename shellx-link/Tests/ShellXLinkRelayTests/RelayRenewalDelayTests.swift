import Foundation
@testable import ShellXLinkRelay
import XCTest

/// When a host opens its next registration: from the ticket's own lifetime (the server's `expires_at - issued_at`),
/// never from the Mac's wall clock against the server's expiry, which a skewed clock turns into a renewal every
/// second (and a ticket mint each time) or into a gap.
final class RelayRenewalDelayTests: XCTestCase {
    private let lead = Duration.seconds(20)

    /// A 120 s ticket issued at 1 000 by the server, read by a Mac whose clock is off by `skew` seconds.
    private func delay(skew: Double) -> Duration {
        RelayHostRegistration.renewDelay(
            issuedAtUnix: 1_000, expiresAtUnix: 1_120, renewLead: lead, now: Date(timeIntervalSince1970: 1_000 + skew))
    }

    func testMacClockAheadStillRenewsLeadBeforeExpiry() {
        // Ahead by 100 s or more: the old delay collapsed to 1 s, a mint and register about once per second.
        for skew in [100.0, 101, 200, 3_600] {
            XCTAssertEqual(delay(skew: skew), .seconds(100), "Mac clock ahead by \(skew) s")
        }
    }

    func testMacClockBehindStillRenewsBeforeExpiry() {
        // Behind by more than the lead: the old delay outlived the ticket, so every renewal lost make-before-break.
        for skew in [-21.0, -300, -3_600] {
            XCTAssertEqual(delay(skew: skew), .seconds(100), "Mac clock behind by \(-skew) s")
        }
    }

    func testSyncedClockKeepsTheLeadAndTheHalfLifeFloor() {
        XCTAssertEqual(delay(skew: 0), .seconds(100))
        // A short ticket renews at half its life rather than `renewLead` before its end.
        XCTAssertEqual(
            RelayHostRegistration.renewDelay(
                issuedAtUnix: 1_000, expiresAtUnix: 1_030, renewLead: lead, now: Date(timeIntervalSince1970: 5_000)),
            .seconds(15))
        // Never sooner than 1 s, even for a ticket that is already over.
        XCTAssertEqual(
            RelayHostRegistration.renewDelay(
                issuedAtUnix: 1_000, expiresAtUnix: 1_000, renewLead: lead, now: Date(timeIntervalSince1970: 1_000)),
            .seconds(1))
    }

    func testWithoutIssuedAtTheExpiryIsComparedWithTheLocalClock() {
        XCTAssertEqual(
            RelayHostRegistration.renewDelay(
                issuedAtUnix: nil, expiresAtUnix: 1_120, renewLead: lead, now: Date(timeIntervalSince1970: 1_000)),
            .seconds(100))
        XCTAssertEqual(
            RelayHostRegistration.renewDelay(
                issuedAtUnix: nil, expiresAtUnix: 1_120, renewLead: lead, now: Date(timeIntervalSince1970: 1_060)),
            .seconds(40))
    }
}
