import Foundation
import XCTest

@testable import ShellXAppCore

final class MachineLinkStateTests: XCTestCase {
    /// A Mac that removed this iPhone, or whose key changed, cannot take messages until it is paired
    /// again: it is not offered as the default.
    func testCanBeDefault() {
        let usable: [MachineLinkState] = [.connecting, .online, .reconnecting, .offline(since: Date()), .needsUpdate]
        for state in usable { XCTAssertTrue(state.canBeDefault, "\(state)") }
        XCTAssertFalse(MachineLinkState.revoked.canBeDefault)
        XCTAssertFalse(MachineLinkState.hostKeyChanged.canBeDefault)
    }
}
