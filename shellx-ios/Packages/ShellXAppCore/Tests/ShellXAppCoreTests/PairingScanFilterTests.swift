import Foundation
import XCTest

@testable import ShellXAppCore

final class PairingScanFilterTests: XCTestCase {
    private let code = "shellx-link://pair?v=1&m=m1&s=s1&k=k&c=c&n=Mac"

    func testShellXCodeAccepted() {
        var filter = PairingScanFilter()
        XCTAssertEqual(filter.accept(code), .pairing(code))
        // Any shellx-link code goes on to the parser, which tells a damaged one apart.
        XCTAssertEqual(filter.accept("SHELLX-LINK://pair?v=9"), .pairing("SHELLX-LINK://pair?v=9"))
        XCTAssertEqual(filter.accept(" \(code)\n"), .pairing(code), "blanks around the code are dropped")
    }

    func testOtherCodesReportedAndScanningContinues() {
        var filter = PairingScanFilter()
        XCTAssertEqual(filter.accept("https://shellx.pro"), .notShellX)
        XCTAssertEqual(filter.accept("WIFI:S:home;T:WPA;P:secret;;"), .notShellX)
        XCTAssertEqual(filter.accept(code), .pairing(code), "a ShellX code after other codes still pairs")
    }

    func testSameCodeIgnoredUntilAnotherSeen() {
        var filter = PairingScanFilter()
        XCTAssertEqual(filter.accept("https://shellx.pro"), .notShellX)
        // The camera reports a code in view many times a second.
        XCTAssertEqual(filter.accept("https://shellx.pro"), .ignored)
        XCTAssertEqual(filter.accept(code), .pairing(code))
        XCTAssertEqual(filter.accept(code), .ignored)
        XCTAssertEqual(filter.accept("https://shellx.pro"), .notShellX)
    }

    func testIsPairingText() {
        XCTAssertTrue(PairingScanFilter.isPairingText(code))
        XCTAssertTrue(PairingScanFilter.isPairingText("\n\(code) "))
        XCTAssertFalse(PairingScanFilter.isPairingText(""))
        XCTAssertFalse(PairingScanFilter.isPairingText("shellx-linkpair"))
        XCTAssertFalse(PairingScanFilter.isPairingText("see shellx-link://pair?v=1"))
    }
}

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
}
