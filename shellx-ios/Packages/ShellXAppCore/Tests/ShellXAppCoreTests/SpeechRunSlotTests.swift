import Foundation
import XCTest

@testable import ShellXAppCore

/// The microphone holds one dictation at a time. The newest start wins: a start that a newer one
/// overtook, or whose run was cancelled while it started, never takes the microphone and never tears
/// down the run that holds it.
final class SpeechRunSlotTests: XCTestCase {
    /// Records what each run's handlers were asked to do.
    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [String] = []

        var all: [String] { lock.withLock { events } }

        func add(_ event: String) {
            lock.withLock { events.append(event) }
        }

        func handlers(_ name: String) -> SpeechRunSlot.Handlers {
            SpeechRunSlot.Handlers(
                finish: { self.add("finish \(name)"); return "text \(name)" },
                teardown: { self.add("teardown \(name)") })
        }
    }

    private func refused(_ claim: SpeechRunSlot.Claim) -> Bool {
        if case .refused = claim { return true }
        return false
    }

    private func granted(_ claim: SpeechRunSlot.Claim) -> SpeechRunSlot.Handlers?? {
        if case let .granted(replaced) = claim { return .some(replaced) }
        return nil
    }

    func testClaimTakesTheMicAndHandsBackTheRunItReplaces() async {
        let slot = SpeechRunSlot()
        let log = Log()
        let first = SpeechRunID()
        let second = SpeechRunID()
        slot.begin(first)
        XCTAssertNotNil(granted(slot.claim(first, log.handlers("first"))))
        XCTAssertTrue(slot.isActive(first))

        slot.begin(second)
        let replaced = granted(slot.claim(second, log.handlers("second")))
        XCTAssertTrue(slot.isActive(second))
        XCTAssertFalse(slot.isActive(first))
        await replaced??.teardown()
        XCTAssertEqual(log.all, ["teardown first"], "the new run tears down the one it replaces")
    }

    func testStaleStartFinishingSecondIsRefused() {
        let slot = SpeechRunSlot()
        let log = Log()
        let stale = SpeechRunID()
        let newer = SpeechRunID()
        slot.begin(stale)
        slot.begin(newer)
        XCTAssertNotNil(granted(slot.claim(newer, log.handlers("newer"))))
        XCTAssertTrue(refused(slot.claim(stale, log.handlers("stale"))), "an overtaken start never takes over")
        XCTAssertTrue(slot.isActive(newer))
        XCTAssertTrue(log.all.isEmpty, "and tears nothing down")
    }

    func testBeginningAgainNeverMovesNewestBack() {
        // The router begins every press at its entry; an inner transcriber (or a fallback retry)
        // begins the same run again later. That must not make an older run the newest again.
        let slot = SpeechRunSlot()
        let log = Log()
        let stale = SpeechRunID()
        let newer = SpeechRunID()
        slot.begin(stale)
        slot.begin(newer)
        slot.begin(stale)
        XCTAssertTrue(refused(slot.claim(stale, log.handlers("stale"))))
        XCTAssertNotNil(granted(slot.claim(newer, log.handlers("newer"))), "the newer press still gets the mic")
        XCTAssertTrue(slot.isActive(newer))
    }

    func testRunCancelledWhileStartingIsRefused() async {
        let slot = SpeechRunSlot()
        let log = Log()
        let active = SpeechRunID()
        slot.begin(active)
        _ = slot.claim(active, log.handlers("active"))

        let tap = SpeechRunID()
        slot.begin(tap)
        let handlers = slot.cancel(tap)
        XCTAssertNil(handlers, "nothing to tear down yet")
        XCTAssertTrue(refused(slot.claim(tap, log.handlers("tap"))))
        XCTAssertTrue(slot.isActive(active), "the run that holds the mic keeps it")

        // A cancel that arrives before its start began counts too.
        let early = SpeechRunID()
        _ = slot.cancel(early)
        slot.begin(early)
        XCTAssertTrue(refused(slot.claim(early, log.handlers("early"))))
        XCTAssertTrue(log.all.isEmpty)
    }

    func testCancelTearsDownOnlyTheRunItNames() async {
        let slot = SpeechRunSlot()
        let log = Log()
        let run = SpeechRunID()
        slot.begin(run)
        _ = slot.claim(run, log.handlers("run"))
        XCTAssertNil(slot.cancel(SpeechRunID()))
        XCTAssertTrue(slot.isActive(run))
        await slot.cancel(run)?.teardown()
        XCTAssertFalse(slot.isActive(run))
        XCTAssertEqual(log.all, ["teardown run"])
        XCTAssertNil(slot.cancel(run), "a second cancel finds nothing")
    }

    func testFinishAndEndTakeTheActiveRunOnly() async {
        let slot = SpeechRunSlot()
        let log = Log()
        let run = SpeechRunID()
        slot.begin(run)
        _ = slot.claim(run, log.handlers("run"))
        XCTAssertNil(slot.takeForFinish(SpeechRunID()))
        let text = await slot.takeForFinish(run)?.finish()
        XCTAssertEqual(text, "text run")
        XCTAssertFalse(slot.isActive(run), "a finishing run no longer holds the slot")

        let ending = SpeechRunID()
        slot.begin(ending)
        _ = slot.claim(ending, log.handlers("ending"))
        XCTAssertFalse(slot.ended(SpeechRunID()))
        XCTAssertTrue(slot.ended(ending), "it ended by itself while it held the mic")
        XCTAssertFalse(slot.ended(ending))
        XCTAssertNil(slot.active)
    }
}
