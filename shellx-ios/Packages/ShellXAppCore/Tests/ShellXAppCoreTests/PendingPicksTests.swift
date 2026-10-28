import Foundation
import XCTest

@testable import ShellXAppCore

/// Photos and files still being read for the composer (finding I3, ruling R15): each holds a place until it is
/// read, in the order picked, and each can be cancelled, which frees its place at once even when its read never
/// ends.
@MainActor
final class PendingPicksTests: XCTestCase {
    private func attachment(_ name: String) -> OutgoingAttachment {
        OutgoingAttachment(kind: .file, name: name, data: Data(name.utf8))
    }

    /// A read the test ends by hand; it ignores cancellation, like a coordinated file read that hangs.
    private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private(set) var entered = false

        func wait() async {
            entered = true
            await withCheckedContinuation { continuation = $0 }
        }

        func open() {
            continuation?.resume()
            continuation = nil
        }
    }

    func testPicksArriveInTheOrderPicked() async {
        let picks = PendingPicks()
        var added: [String] = []
        picks.read([
            { self.attachment("a.txt") },
            {
                try await Task.sleep(for: .milliseconds(20))
                return self.attachment("b.txt")
            },
            { self.attachment("c.txt") },
        ]) { result in
            if case let .success(attachment) = result { added.append(attachment.name) }
        }
        XCTAssertEqual(picks.count, 3, "each pick holds a place from the moment the picker closes")

        let done = await eventually { picks.count == 0 }
        XCTAssertTrue(done)
        XCTAssertEqual(added, ["a.txt", "b.txt", "c.txt"])
    }

    func testAPickThatCannotBeReadSaysWhy() async {
        struct Unreadable: Error {}
        let picks = PendingPicks()
        var failures = 0
        picks.read([{ throw Unreadable() }]) { result in
            if case .failure = result { failures += 1 }
        }
        let done = await eventually { picks.count == 0 }
        XCTAssertTrue(done)
        XCTAssertEqual(failures, 1)
    }

    /// The way out of a read that never ends: its ✕ frees the composer at once, the next pick goes on, and what
    /// the hung read returns later is dropped.
    func testAHungPickIsCancelledAtOnce() async {
        let picks = PendingPicks()
        let hung = Gate()
        var added: [String] = []
        let ids = picks.read([
            {
                await hung.wait()
                return self.attachment("late.txt")
            },
            { self.attachment("next.txt") },
        ]) { result in
            if case let .success(attachment) = result { added.append(attachment.name) }
        }
        let started = await eventually { hung.entered }
        XCTAssertTrue(started)
        XCTAssertEqual(picks.ids, ids)

        picks.cancel(ids[0])
        XCTAssertEqual(picks.ids, [ids[1]], "the cancelled pick's place is gone before its read ends")

        let next = await eventually { picks.count == 0 }
        XCTAssertTrue(next, "the pick after the hung one was read")
        XCTAssertEqual(added, ["next.txt"])

        hung.open()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(added, ["next.txt"], "a cancelled pick's late result is dropped")
    }

    func testAPickCancelledBeforeItsTurnIsNeverRead() async {
        let picks = PendingPicks()
        let first = Gate()
        var calls: [String] = []
        var added: [String] = []
        let ids = picks.read([
            {
                calls.append("first")
                await first.wait()
                return self.attachment("first.txt")
            },
            {
                calls.append("second")
                return self.attachment("second.txt")
            },
            {
                calls.append("third")
                return self.attachment("third.txt")
            },
        ]) { result in
            if case let .success(attachment) = result { added.append(attachment.name) }
        }
        let started = await eventually { first.entered }
        XCTAssertTrue(started)

        picks.cancel(ids[1])
        XCTAssertEqual(picks.count, 2)
        first.open()

        let done = await eventually { picks.count == 0 }
        XCTAssertTrue(done)
        XCTAssertEqual(calls, ["first", "third"])
        XCTAssertEqual(added, ["first.txt", "third.txt"])
    }

    /// Cancelling a pick cancels its read's task, so a read that does watch for it (a photo load) stops.
    func testCancellingAPickCancelsItsRead() async {
        let picks = PendingPicks()
        var sawCancellation = false
        var entered = false
        let ids = picks.read([
            {
                entered = true
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    sawCancellation = true
                    throw error
                }
                return self.attachment("never.txt")
            },
        ]) { _ in XCTFail("a cancelled pick reports nothing") }
        let started = await eventually { entered }
        XCTAssertTrue(started)

        picks.cancel(ids[0])
        XCTAssertEqual(picks.count, 0)
        let stopped = await eventually { sawCancellation }
        XCTAssertTrue(stopped)
    }

    func testCancellingAnUnknownPickDoesNothing() {
        let picks = PendingPicks()
        picks.cancel(UUID())
        XCTAssertEqual(picks.count, 0)
    }
}
