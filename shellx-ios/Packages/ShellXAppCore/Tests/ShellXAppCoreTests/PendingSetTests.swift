import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

final class PendingSetTests: XCTestCase {
    func testOldRevisionIgnored() {
        var set = PendingSet()
        set.reset(revision: 5, items: [pendingItem("a")])

        XCTAssertEqual(set.apply(revision: 5, added: [pendingItem("b")], resolved: ["a"]), .ignored)
        XCTAssertEqual(set.apply(revision: 2, added: [pendingItem("c")], resolved: []), .ignored)
        XCTAssertEqual(set.revision, 5)
        XCTAssertEqual(set.items.map(\.requestId), ["a"])
    }

    func testNextRevisionApplied() {
        var set = PendingSet()
        set.reset(revision: 5, items: [pendingItem("a", createdAtMs: 1), pendingItem("b", createdAtMs: 2)])

        XCTAssertEqual(set.apply(revision: 6, added: [pendingItem("c", createdAtMs: 3)], resolved: ["a"]), .applied)
        XCTAssertEqual(set.revision, 6)
        XCTAssertEqual(set.items.map(\.requestId), ["b", "c"])

        // An item added again under the same id replaces the old one.
        var changed = pendingItem("b", createdAtMs: 2)
        changed.toolInputPreview = "rm -rf build"
        XCTAssertEqual(set.apply(revision: 7, added: [changed], resolved: []), .applied)
        XCTAssertEqual(set.items.map(\.requestId), ["b", "c"])
        XCTAssertEqual(set.items.first?.toolInputPreview, "rm -rf build")
    }

    func testGapReported() {
        var set = PendingSet()
        set.reset(revision: 5, items: [pendingItem("a")])

        XCTAssertEqual(set.apply(revision: 7, added: [pendingItem("b")], resolved: ["a"]), .gap)
        // A gap changes nothing: the caller resyncs from a snapshot.
        XCTAssertEqual(set.revision, 5)
        XCTAssertEqual(set.items.map(\.requestId), ["a"])
    }

    func testItemsSortedByCreation() {
        var set = PendingSet()
        set.reset(revision: 1, items: [
            pendingItem("c", createdAtMs: 30), pendingItem("a", createdAtMs: 10), pendingItem("b", createdAtMs: 20),
        ])
        XCTAssertEqual(set.items.map(\.requestId), ["a", "b", "c"])

        XCTAssertEqual(set.apply(revision: 2, added: [pendingItem("d", createdAtMs: 15)], resolved: []), .applied)
        XCTAssertEqual(set.items.map(\.requestId), ["a", "d", "b", "c"])
    }
}
