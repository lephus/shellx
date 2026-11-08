import Foundation
import ShellXLinkCore
import ShellXLinkSession
import XCTest

@testable import ShellXAppCore

/// `TerminalViewModel`'s lifecycle and frames (rules R1-R9 and the first grid of R11), against a `ScriptedTerminalLink`.
@MainActor
final class TerminalViewModelTests: XCTestCase {
    private var runs: [Task<Void, Never>] = []

    override func tearDown() async throws {
        for run in runs { run.cancel() }
        runs = []
        try await super.tearDown()
    }

    /// A model of Mac `m1` whose `run()` runs until the test ends.
    private func makeModel(
        _ link: ScriptedTerminalLink, sleeper: ManualSleeper = ManualSleeper(),
        maxHistoryRows: Int = TerminalScreen.defaultMaxHistoryRows,
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) -> TerminalViewModel {
        let model = TerminalViewModel(
            machineID: "m1", link: link, maxHistoryRows: maxHistoryRows, sleep: sleeper.sleep, now: now)
        runs.append(Task { await model.run() })
        return model
    }

    /// Shows `id` at 50 × 20 and brings it live with a first snapshot of `text`.
    private func live(
        _ model: TerminalViewModel, _ link: ScriptedTerminalLink, _ id: String = "t1", text: [String] = ["$"],
        alt: Bool = false, file: StaticString = #filePath, line: UInt = #line
    ) async {
        model.setPhoneGrid(cols: 50, rows: 20)
        model.show(id)
        _ = await eventually { link.opens.last == id }
        emit(link, .opened(terminalId: id))
        emit(link, .frame(terminalId: id, part: snapshotPart(revision: 1, cols: 50, rows: 20, text: text, alt: alt)))
        let isLive = await eventually { model.phase == .live }
        XCTAssertTrue(isLive, "\(model.phase) \(link.calls)", file: file, line: line)
    }

    private func emit(_ link: ScriptedTerminalLink, _ push: TerminalViewPush) {
        link.emit(.push(machineID: "m1", push))
    }

    func testOpensTheTerminalShownAtThePhoneSize() async {
        let link = ScriptedTerminalLink(); let model = makeModel(link)
        model.show("t1")
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(link.calls, [], "no open before the phone's size is known")
        model.setPhoneGrid(cols: 50, rows: 20)
        let opened = await eventually { link.calls == [.open("t1", cols: 50, rows: 20)] }
        XCTAssertTrue(opened); XCTAssertEqual(model.phase, .connecting)
    }

    func testTheFirstSnapshotGoesLiveAndIsMeasured() async {
        let link = ScriptedTerminalLink(); let model = makeModel(link)
        await live(model, link, text: ["$ ls"])
        XCTAssertEqual(model.screen.screenText().first, "$ ls"); XCTAssertEqual(model.snapshots, 1); XCTAssertEqual(model.topShift, 0)
        XCTAssertEqual(link.latencies.filter { $0 == .terminalFirstScreen }.count, 1)
        XCTAssertTrue(link.latencies.contains(.terminalFrameApply))
    }

    func testFramesBeforeOpenedAndOfOtherTerminalsOrMacsAreIgnored() async {
        let link = ScriptedTerminalLink(); let model = makeModel(link)
        model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
        _ = await eventually { link.opens == ["t1"] }
        emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 1, text: ["early"])))
        emit(link, .opened(terminalId: "t1"))
        link.emit(.push(machineID: "m2", .frame(terminalId: "t1", part: snapshotPart(revision: 1, text: ["other mac"]))))
        emit(link, .frame(terminalId: "t2", part: snapshotPart(revision: 1, text: ["other terminal"])))
        emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 1, text: ["mine"])))
        let shown = await eventually { model.phase == .live }
        XCTAssertTrue(shown); XCTAssertEqual(model.screen.screenText().first, "mine")
    }

    func testFastSwitchesNeverShowAnotherTerminalsFrames() async {   // Review Focus 1
        let link = ScriptedTerminalLink(); let model = makeModel(link)
        _ = await eventually { link.subscriberCount == 1 }   // run() has started: both shows reach the Mac
        model.setPhoneGrid(cols: 50, rows: 20); model.show("t1"); model.show("t2")
        let ordered = await eventually {
            link.calls == [.open("t1", cols: 50, rows: 20), .close("t1"), .open("t2", cols: 50, rows: 20)]
        }
        XCTAssertTrue(ordered, "\(link.calls)")
        emit(link, .opened(terminalId: "t1")); emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 1, text: ["one"])))
        emit(link, .opened(terminalId: "t2")); emit(link, .frame(terminalId: "t2", part: snapshotPart(revision: 1, text: ["two"])))
        emit(link, .frame(terminalId: "t1", part: deltaPart(revision: 2, replacing: [0: "late one"])))
        _ = await eventually { model.phase == .live }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.screen.screenText().first, "two")
    }

    func testTheLoadingStateLastsUntilTheFirstSnapshot() async {   // contracts §17: the Mac may wait 500 ms for the size
        let link = ScriptedTerminalLink(); let clock = SteppedNow()
        let model = makeModel(link, now: clock.now)
        model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
        _ = await eventually { link.opens == ["t1"] }
        emit(link, .opened(terminalId: "t1"))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.phase, .connecting, "answered and opened, but no screen yet: still loading")
        clock.advance(by: .milliseconds(600))
        emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 1, cols: 50, rows: 20, text: ["$"])))
        _ = await eventually { model.phase == .live }
        XCTAssertEqual(link.samples.first { $0.metric == .terminalFirstScreen }?.duration, .milliseconds(600),
                       "measured from the swipe, the Mac's wait included")
    }

    func testAGridWiderThanThePhoneCanAskForIsShown() async {   // Review Focus 5, contracts §17
        let link = ScriptedTerminalLink(); let model = makeModel(link)
        model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
        _ = await eventually { link.opens == ["t1"] }
        emit(link, .opened(terminalId: "t1"))
        emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 1, cols: 320, rows: 130, text: [String(repeating: "x", count: 320)])))
        let shown = await eventually { model.phase == .live }
        XCTAssertTrue(shown)
        XCTAssertEqual(model.screen.cols, 320); XCTAssertEqual(model.screen.rows, 130)
        XCTAssertFalse(link.calls.contains(.resync("t1")))
    }

    func testShowingNothingClosesTheView() async {
        let link = ScriptedTerminalLink(); let model = makeModel(link)
        await live(model, link)
        model.show(nil)
        let closed = await eventually { link.calls.last == .close("t1") }
        XCTAssertTrue(closed)
    }

    func testLeavingTheScreenClosesTheView() async {
        let link = ScriptedTerminalLink()
        let model = TerminalViewModel(machineID: "m1", link: link, sleep: ManualSleeper().sleep)
        let run = Task { await model.run() }
        await live(model, link)
        run.cancel()
        let closed = await eventually { link.calls.last == .close("t1") }
        XCTAssertTrue(closed, "the close still goes out after run() ends")
    }

    func testARestartedRunKeepsTheViewOpen() async {
        let link = ScriptedTerminalLink()
        let model = TerminalViewModel(machineID: "m1", link: link, sleep: ManualSleeper().sleep)
        let first = Task { await model.run() }
        await live(model, link)
        first.cancel()
        let second = Task { await model.run() }
        addTeardownBlock { second.cancel() }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(link.calls, [.open("t1", cols: 50, rows: 20)], "SwiftUI restarting the page's task neither closes nor reopens")
    }

    func testBackgroundClosesAndForegroundReopens() async {
        let link = ScriptedTerminalLink(); let model = makeModel(link)
        await live(model, link)
        model.suspend()
        let closed = await eventually { link.calls.last == .close("t1") }
        XCTAssertTrue(closed); XCTAssertEqual(model.screen.screenText().first, "$", "the screen stays")
        model.resume()
        let reopened = await eventually { link.opens == ["t1", "t1"] }
        XCTAssertTrue(reopened)
    }

    func testBackgroundDuringTheOpenClosesAfterIt() async {   // Review Focus 4
        let link = ScriptedTerminalLink(); let gate = Gate(); link.openGate = gate
        let model = makeModel(link)
        model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
        _ = await eventually { link.opens == ["t1"] }
        model.suspend(); gate.open()
        let ordered = await eventually { link.calls == [.open("t1", cols: 50, rows: 20), .close("t1")] }
        XCTAssertTrue(ordered)
        emit(link, .opened(terminalId: "t1")); emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 1, text: ["$"])))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertNotEqual(model.phase, .live)
    }

    func testAGapAsksForOneResyncThenTakesTheSnapshot() async {
        let link = ScriptedTerminalLink(); let model = makeModel(link)
        await live(model, link)
        emit(link, .frame(terminalId: "t1", part: deltaPart(revision: 3, cols: 50, rows: 20, replacing: [0: "three"])))
        emit(link, .frame(terminalId: "t1", part: deltaPart(revision: 4, cols: 50, rows: 20, replacing: [0: "four"])))
        let asked = await eventually { link.calls.filter { $0 == .resync("t1") }.count == 1 }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(asked); XCTAssertEqual(link.calls.filter { $0 == .resync("t1") }.count, 1)
        emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 5, cols: 50, rows: 20, text: ["fresh"])))
        let fresh = await eventually { model.screen.screenText().first == "fresh" }
        XCTAssertTrue(fresh)
    }

    func testMacOfflineKeepsTheScreenAndReopensOnceOnline() async {   // Review Focus 4
        let link = ScriptedTerminalLink(); let model = makeModel(link)
        await live(model, link, text: ["$ ls"])
        link.online = false; link.emit(.state(machineID: "m1", .reconnecting))
        let offline = await eventually { model.phase == .offline }
        XCTAssertTrue(offline); XCTAssertEqual(model.screen.screenText().first, "$ ls")
        XCTAssertFalse(link.calls.contains(.close("t1")), "the session is gone: nothing to close")
        link.online = true; link.emit(.state(machineID: "m1", .online))
        let reopened = await eventually { link.opens == ["t1", "t1"] }
        XCTAssertTrue(reopened)
        emit(link, .opened(terminalId: "t1"))
        emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 1, cols: 50, rows: 20, text: ["back"])))
        let back = await eventually { model.phase == .live && model.screen.screenText().first == "back" }
        XCTAssertTrue(back, "revision 1 again: a fresh assembler takes it")
        XCTAssertFalse(link.calls.contains(.resync("t1")))
    }

    func testOpenOutcomesThatStop() async {
        let link = ScriptedTerminalLink(); link.openAnswers = [.outcome(.notFound), .outcome(.refused)]
        let model = makeModel(link)
        model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
        let gone = await eventually { model.phase == .unavailable(.gone) }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(gone); XCTAssertEqual(link.opens, ["t1"], "a terminal that is gone is not asked for again")
        model.show("t2")
        let refused = await eventually { model.phase == .unavailable(.refused) }
        XCTAssertTrue(refused)
    }

    func testAFailedOpenIsRetriedOnceThenOffersTryAgain() async {
        let link = ScriptedTerminalLink(); link.openAnswers = [.outcome(.failed), .noAnswer]
        let sleeper = ManualSleeper(); let model = makeModel(link, sleeper: sleeper)
        model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
        _ = await eventually { sleeper.waiting.contains(TerminalViewModel.failedRetryDelay) }
        sleeper.release { $0 == TerminalViewModel.failedRetryDelay }
        let failed = await eventually { link.opens.count == 2 && model.phase == .unavailable(.failed) }
        XCTAssertTrue(failed)
        model.retry()
        let again = await eventually { link.opens.count == 3 }
        XCTAssertTrue(again)
    }

    func testBusyIsRetriedFiveTimes() async {
        let link = ScriptedTerminalLink(); link.openAnswers = Array(repeating: .outcome(.busy), count: 6)
        let sleeper = ManualSleeper(); let model = makeModel(link, sleeper: sleeper)
        model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
        for _ in 0..<5 {
            _ = await eventually { sleeper.waiting.contains(TerminalViewModel.busyRetryDelay) }
            sleeper.release { $0 == TerminalViewModel.busyRetryDelay }
        }
        let failed = await eventually { link.opens.count == 6 && model.phase == .unavailable(.failed) }
        XCTAssertTrue(failed, "\(link.opens.count) \(model.phase)")
    }

    func testEndedViews() async {
        let link = ScriptedTerminalLink(); let model = makeModel(link)
        await live(model, link)
        emit(link, .ended(terminalId: "t1", reason: .notOpen))
        let reopened = await eventually { link.opens == ["t1", "t1"] }
        XCTAssertTrue(reopened)
        emit(link, .opened(terminalId: "t1")); emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 1, text: ["$"])))
        _ = await eventually { model.phase == .live }
        emit(link, .ended(terminalId: "t1", reason: .gone))
        let gone = await eventually { model.phase == .unavailable(.gone) }
        XCTAssertTrue(gone)
        await live(model, link, "t2")
        emit(link, .ended(terminalId: "t2", reason: .refused))
        let refused = await eventually { model.phase == .unavailable(.refused) }
        XCTAssertTrue(refused)
    }

    func testNotOpenBeforeOpenedIsIgnored() async {
        let link = ScriptedTerminalLink(); let gate = Gate(); link.openGate = gate
        let model = makeModel(link)
        model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
        _ = await eventually { link.opens == ["t1"] }
        emit(link, .ended(terminalId: "t1", reason: .notOpen))
        gate.open()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(link.opens, ["t1"])
    }

    func testAMacWithoutTerminalViewsOrOfflineOpensNothing() async {
        let old = ScriptedTerminalLink(); old.supportsViews = false
        let model = makeModel(old)
        model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
        let unsupported = await eventually { model.phase == .unsupported }
        XCTAssertTrue(unsupported); XCTAssertEqual(old.calls, [])
        let away = ScriptedTerminalLink(); away.online = false; away.supportsViews = false
        let other = makeModel(away)
        other.setPhoneGrid(cols: 50, rows: 20); other.show("t1")
        let offline = await eventually { other.phase == .offline }
        XCTAssertTrue(offline, "a Mac never seen online is not called too old")
    }

    func testTopShiftFollowsRowsAddedAboveAndDroppedFromTheTop() async {
        let link = ScriptedTerminalLink(); let model = makeModel(link, maxHistoryRows: 5)
        model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
        _ = await eventually { link.opens == ["t1"] }
        emit(link, .opened(terminalId: "t1"))
        emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 1, cols: 10, rows: 2, text: ["a", "b"], history: ["h1", "h2"])))
        _ = await eventually { model.snapshots == 1 }
        emit(link, .frame(terminalId: "t1", part: historyPart(revision: 2, cols: 10, rows: 2, lines: ["h-2", "h-1", "h0"])))
        let grown = await eventually { model.topShift == 3 && model.screen.historyRows.count == 5 }
        XCTAssertTrue(grown)
        emit(link, .frame(terminalId: "t1", part: deltaPart(revision: 3, cols: 10, rows: 2, replacing: [0: "c", 1: "d"], scroll: 2)))
        let dropped = await eventually { model.topShift == 1 }
        XCTAssertTrue(dropped, "two rows dropped from the top")
        emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 4, cols: 10, rows: 2, text: ["e"])))
        let reset = await eventually { model.snapshots == 2 && model.topShift == 0 }
        XCTAssertTrue(reset)
    }
    func testATimedOutOpenIsClosedOnTheMac() async {   // the Mac may have opened the view although its answer never came
        let link = ScriptedTerminalLink(); link.openAnswers = [.noAnswer]
        let sleeper = ManualSleeper(); let model = makeModel(link, sleeper: sleeper)
        model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
        let closed = await eventually { link.calls == [.open("t1", cols: 50, rows: 20), .close("t1")] }
        XCTAssertTrue(closed, "\(link.calls)")
        _ = await eventually { sleeper.waiting.contains(TerminalViewModel.failedRetryDelay) }
        XCTAssertEqual(link.opens, ["t1"], "the retry waits")
        sleeper.release { $0 == TerminalViewModel.failedRetryDelay }
        let again = await eventually {
            link.calls == [.open("t1", cols: 50, rows: 20), .close("t1"), .open("t1", cols: 50, rows: 20)]
        }
        XCTAssertTrue(again, "\(link.calls)")
        XCTAssertEqual(model.phase, .connecting)
    }

    func testANoAnswerWhileOfflineSendsNoClose() async {   // the session is gone, like R8
        let link = ScriptedTerminalLink(); let gate = Gate(); link.openGate = gate; link.openAnswers = [.noAnswer]
        let model = makeModel(link)
        model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
        _ = await eventually { link.opens == ["t1"] }
        link.online = false; gate.open()
        let offline = await eventually { model.phase == .offline }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(offline)
        XCTAssertEqual(link.calls, [.open("t1", cols: 50, rows: 20)], "nothing to close")
        link.online = true; link.emit(.state(machineID: "m1", .online))
        let reopened = await eventually {
            link.calls == [.open("t1", cols: 50, rows: 20), .open("t1", cols: 50, rows: 20)]
        }
        XCTAssertTrue(reopened, "\(link.calls)")
    }
}
