import Foundation
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class ShellXAutomationsOpenQueueTests: XCTestCase {
    private func link(_ string: String) -> ShellXAutomationsURL {
        ShellXAutomationsURL(URL(string: string)!)!
    }

    func testLinkBeforeStartIsReplayedOnceAfterStart() {
        let queue = ShellXAutomationsOpenQueue()
        var opened: [String?] = []

        queue.submit(link("shellx://automations/abc"), isReady: false) { opened.append($0) }
        XCTAssertEqual(opened, [])
        queue.flush(isReady: false) { opened.append($0) }
        XCTAssertEqual(opened, [])

        queue.flush(isReady: true) { opened.append($0) }
        queue.flush(isReady: true) { opened.append($0) }
        XCTAssertEqual(opened, ["abc"])
        XCTAssertFalse(queue.hasPending)
    }

    func testNewestWaitingLinkWins() {
        let queue = ShellXAutomationsOpenQueue()
        var opened: [String?] = []
        queue.submit(link("shellx://automations/first"), isReady: false) { opened.append($0) }
        queue.submit(link("shellx://automations"), isReady: false) { opened.append($0) }

        queue.flush(isReady: true) { opened.append($0) }
        XCTAssertEqual(opened, [nil])
    }

    func testLinkWhenReadyOpensAtOnce() {
        let queue = ShellXAutomationsOpenQueue()
        var opened: [String?] = []
        queue.submit(link("shellx://automations/abc"), isReady: true) { opened.append($0) }
        XCTAssertEqual(opened, ["abc"])
        XCTAssertFalse(queue.hasPending)
    }
}
