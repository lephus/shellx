import Foundation
import XCTest

@testable import ShellXAppCore

@MainActor
final class PairingInboxTests: XCTestCase {
    private let link = URL(string: "shellx-link://pair?v=1&m=m1&s=s1&k=k&c=c&n=Mac")!

    func testPairingLinkHeldUntilTaken() {
        let inbox = PairingInbox()
        XCTAssertFalse(inbox.hasLink)

        XCTAssertTrue(inbox.receive(link))

        XCTAssertTrue(inbox.hasLink)
        XCTAssertEqual(inbox.take(), link.absoluteString)
        XCTAssertFalse(inbox.hasLink)
        XCTAssertNil(inbox.take(), "a link opens once")
    }

    func testOtherSchemesIgnored() {
        let inbox = PairingInbox()
        XCTAssertFalse(inbox.receive(URL(string: "https://shellx.pro/pair")!))
        XCTAssertFalse(inbox.receive(URL(string: "shellx://pair")!))
        XCTAssertFalse(inbox.hasLink)
    }

    func testNewerLinkReplacesOlder() {
        let inbox = PairingInbox()
        let newer = URL(string: "shellx-link://pair?v=1&m=m2&s=s2&k=k&c=c&n=Mini")!
        XCTAssertTrue(inbox.receive(link))
        XCTAssertTrue(inbox.receive(newer))
        XCTAssertEqual(inbox.take(), newer.absoluteString)
    }

    /// iOS opens the app for the scheme in any case, so the inbox takes any case; `PairingModel`
    /// lowercases the scheme before parsing (PairingModelTests checks the whole path).
    func testUppercaseSchemeAccepted() {
        let inbox = PairingInbox()
        XCTAssertTrue(inbox.receive(URL(string: "SHELLX-LINK://pair?v=1&m=m1&s=s1&k=k&c=c&n=Mac")!))
        XCTAssertTrue(inbox.hasLink)
    }
}
