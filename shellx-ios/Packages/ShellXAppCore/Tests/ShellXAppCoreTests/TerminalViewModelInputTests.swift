import Foundation
import ShellXLinkCore
import ShellXLinkSession
import XCTest

@testable import ShellXAppCore

/// `TerminalViewModel`'s typing, paste, scrolling and resizing (rules R10-R12), against a `ScriptedTerminalLink`.
@MainActor
final class TerminalViewModelInputTests: XCTestCase {
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

    func testTypingSendsCommittedTextOnly() async {
        let link = ScriptedTerminalLink(); let model = makeModel(link); await live(model, link)
        model.setMarkedText("v"); model.setMarkedText("vi"); model.setMarkedText("việ")
        XCTAssertEqual(model.typing.markedText, "việ")
        try? await Task.sleep(for: .milliseconds(50)); XCTAssertEqual(link.inputs, [])
        model.insertText("việt")
        let sent = await eventually { link.inputs == [[.text("việt")]] }
        XCTAssertTrue(sent)
    }
    func testBackspaceWhileComposingSendsNothing() async {
        let link = ScriptedTerminalLink(); let model = makeModel(link); await live(model, link)
        model.setMarkedText("việ"); model.deleteBackward()
        XCTAssertEqual(model.typing.markedText, "vi")
        model.unmarkText(); model.deleteBackward()
        let sent = await eventually { link.inputs == [[.text("vi")], [.key(.backspace, mods: [])]] }
        XCTAssertTrue(sent)
    }
    func testTheKeyBarAndTheCtrlLatch() async {
        let link = ScriptedTerminalLink(); let model = makeModel(link); await live(model, link)
        model.toggleCtrl(); XCTAssertTrue(model.typing.ctrlLatched)
        model.insertText("c"); model.press(.escape)
        let sent = await eventually { link.inputs == [[.key(.letter("c"), mods: [.ctrl])], [.key(.escape, mods: [])]] }
        XCTAssertTrue(sent)
    }
    func testInputTypedWhileOpeningGoesAfterTheOpen() async {
        let link = ScriptedTerminalLink(); let gate = Gate(); link.openGate = gate
        let model = makeModel(link)
        model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
        _ = await eventually { link.opens == ["t1"] }
        model.insertText("ls")
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(link.calls, [.open("t1", cols: 50, rows: 20)])
        gate.open()
        let ordered = await eventually { link.calls == [.open("t1", cols: 50, rows: 20), .input("t1", [.text("ls")])] }
        XCTAssertTrue(ordered)
    }
    func testInputAfterASwitchGoesToTheNewTerminal() async {   // Review Focus 1
        let link = ScriptedTerminalLink(); let model = makeModel(link); await live(model, link)
        model.show("t2"); model.insertText("x")
        let sent = await eventually { link.calls.last == .input("t2", [.text("x")]) }
        XCTAssertTrue(sent); XCTAssertFalse(link.calls.contains(.input("t1", [.text("x")])))
    }
    func testNothingIsTypedWithoutAView() async {
        let link = ScriptedTerminalLink(); link.online = false
        let model = makeModel(link)
        model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
        _ = await eventually { model.phase == .offline }
        model.insertText("x"); model.paste("y"); model.press(.enter)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(link.inputs, [])
    }
    func testPasteGoesInPasteSizedMessages() async {
        let link = ScriptedTerminalLink(); let model = makeModel(link); await live(model, link)
        model.paste(String(repeating: "a", count: 20_000))
        let sent = await eventually { link.inputs.count == 2 }
        XCTAssertTrue(sent)
        XCTAssertEqual(link.inputs, [[.paste(String(repeating: "a", count: 16_384))], [.paste(String(repeating: "a", count: 3_616))]])
    }
    func testAPasteOverTheLimitIsRefused() async {
        let link = ScriptedTerminalLink(); let model = makeModel(link); await live(model, link)
        model.paste(String(repeating: "a", count: TerminalInputBatcher.maxPasteBytes + 1))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(link.inputs, [], "nothing of it is sent")
        XCTAssertEqual(model.pasteTooLarge, 1); XCTAssertEqual(model.sentInputs, 0)
    }
    func testScrollOnTheAlternateScreenIsSummed() async {
        let link = ScriptedTerminalLink(); let sleeper = ManualSleeper(); let model = makeModel(link, sleeper: sleeper)
        await live(model, link, alt: true)
        model.scroll(lines: 1); model.scroll(lines: 1); model.scroll(lines: 1)
        XCTAssertEqual(link.inputs, [])
        _ = await eventually { sleeper.waiting.contains(TerminalViewModel.scrollCoalescing) }
        sleeper.release { $0 == TerminalViewModel.scrollCoalescing }
        let sent = await eventually { link.inputs == [[.scroll(lines: 3)]] }
        XCTAssertTrue(sent)
    }
    func testScrollOnTheMainScreenSendsNothing() async {
        let link = ScriptedTerminalLink(); let sleeper = ManualSleeper(); let model = makeModel(link, sleeper: sleeper)
        await live(model, link)
        model.scroll(lines: 3); sleeper.release()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(link.inputs, [])
    }
    func testGridChangesSendOneResizeWithTheLatestSize() async {   // Review Focus 3
        let link = ScriptedTerminalLink(); let sleeper = ManualSleeper(); let model = makeModel(link, sleeper: sleeper)
        await live(model, link)
        model.setPhoneGrid(cols: 50, rows: 10); model.setPhoneGrid(cols: 40, rows: 18); model.setPhoneGrid(cols: 50, rows: 12)
        let resizes = { link.calls.filter { if case .resize = $0 { return true }; return false } }
        XCTAssertEqual(resizes(), [])
        _ = await eventually { sleeper.waiting.contains(TerminalViewModel.resizeDelay) }
        sleeper.release { $0 == TerminalViewModel.resizeDelay }
        let one = await eventually { resizes() == [.resize("t1", cols: 50, rows: 12)] }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(one); XCTAssertEqual(resizes().count, 1)
    }
    func testResizeDuringTheOpenFollowsIt() async {   // Review Focus 3
        let link = ScriptedTerminalLink(); let gate = Gate(); link.openGate = gate
        let sleeper = ManualSleeper(); let model = makeModel(link, sleeper: sleeper)
        model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
        _ = await eventually { link.opens == ["t1"] }
        model.setPhoneGrid(cols: 50, rows: 12)
        _ = await eventually { sleeper.waiting.contains(TerminalViewModel.resizeDelay) }
        sleeper.release { $0 == TerminalViewModel.resizeDelay }
        gate.open()
        let ordered = await eventually { link.calls == [.open("t1", cols: 50, rows: 20), .resize("t1", cols: 50, rows: 12)] }
        XCTAssertTrue(ordered)
    }
    func testTheSameSizeSendsNoResize() async {
        let link = ScriptedTerminalLink(); let sleeper = ManualSleeper(); let model = makeModel(link, sleeper: sleeper)
        await live(model, link)
        model.setPhoneGrid(cols: 50, rows: 20); sleeper.release()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(link.calls.contains { if case .resize = $0 { return true }; return false })
    }
    func testEchoIsMeasuredFromTypingToTheNextFrame() async {
        let link = ScriptedTerminalLink(); let model = makeModel(link); await live(model, link)
        model.insertText("a")
        _ = await eventually { link.inputs.count == 1 }
        emit(link, .frame(terminalId: "t1", part: deltaPart(revision: 2, cols: 50, rows: 20, replacing: [0: "$ a"])))
        let measured = await eventually { link.latencies.filter { $0 == .terminalKeyEcho }.count == 1 }
        XCTAssertTrue(measured)
        emit(link, .frame(terminalId: "t1", part: deltaPart(revision: 3, cols: 50, rows: 20, replacing: [1: "x"])))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(link.latencies.filter { $0 == .terminalKeyEcho }.count, 1, "one echo per keystroke")
    }
    func testAnEchoThatNeverComesIsDropped() async {
        let link = ScriptedTerminalLink(); let sleeper = ManualSleeper(); let model = makeModel(link, sleeper: sleeper)
        await live(model, link)
        model.insertText("a")
        _ = await eventually { sleeper.waiting.contains(TerminalViewModel.echoTimeout) }
        sleeper.release { $0 == TerminalViewModel.echoTimeout }
        try? await Task.sleep(for: .milliseconds(20))
        emit(link, .frame(terminalId: "t1", part: deltaPart(revision: 2, cols: 50, rows: 20, replacing: [0: "late"])))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(link.latencies.contains(.terminalKeyEcho))
    }
}
