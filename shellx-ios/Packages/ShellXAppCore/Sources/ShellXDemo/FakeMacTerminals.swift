import Foundation
import ShellXAppCore
import ShellXLinkCore
import ShellXLinkSession

/// `FakeMac`'s terminals: a `TerminalViewSource` and a `TerminalCreator` in memory, over the Mac's workspaces.
///
/// A view shows its terminal's fixture (`setFixtures(_:)`), or a fresh `DemoTerminalScreens.prompt(cols:rows:)` at the
/// size asked for. A fixture with a prompt is a tiny shell that echoes typing; one with ticks prints a line every
/// interval while it is viewed. Every call is recorded for tests.
final class FakeMacTerminals: TerminalViewSource, TerminalCreator, @unchecked Sendable {
    private let lock = NSLock()
    private let workspaces: FakeMacWorkspaces
    private var fixtures: [String: DemoTerminalFixture] = [:]
    private var refused: [String: TerminalViewOpenOutcome] = [:]
    private var holding = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var current: [String: FakeMacTerminalView] = [:]
    private var opens: [FakeMac.TerminalViewSize] = []
    private var resizes: [FakeMac.TerminalViewSize] = []
    private var closes: [String] = []
    private var inputs: [String: [[TerminalInputUnit]]] = [:]
    private var snapshotRequests: [String: Int] = [:]
    private var creates: [String] = []
    private var nextCreateOutcome: WorkspaceControlOutcome?

    init(workspaces: FakeMacWorkspaces) {
        self.workspaces = workspaces
    }

    var viewOpens: [FakeMac.TerminalViewSize] { lock.withLock { opens } }
    var viewResizes: [FakeMac.TerminalViewSize] { lock.withLock { resizes } }
    var viewCloses: [String] { lock.withLock { closes } }
    var createCalls: [String] { lock.withLock { creates } }
    func viewInputs(_ terminalId: String) -> [[TerminalInputUnit]] { lock.withLock { inputs[terminalId] ?? [] } }
    func viewSnapshotRequests(_ terminalId: String) -> Int { lock.withLock { snapshotRequests[terminalId] ?? 0 } }

    func setFixtures(_ fixtures: [String: DemoTerminalFixture]) {
        lock.withLock { self.fixtures = fixtures }
    }

    func refuse(_ terminalId: String, with outcome: TerminalViewOpenOutcome) {
        lock.withLock { refused[terminalId] = outcome }
    }

    func hold() {
        lock.withLock { holding = true }
    }

    func release() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            holding = false
            defer { held = [] }
            return held
        }
        for continuation in waiting { continuation.resume() }
    }

    func emit(_ terminalId: String, _ event: TerminalViewEvent) {
        let view = lock.withLock { current[terminalId] }
        view?.enqueue(event)
    }

    func setNextCreateOutcome(_ outcome: WorkspaceControlOutcome) {
        lock.withLock { nextCreateOutcome = outcome }
    }

    // MARK: - TerminalViewSource

    func openView(terminalId: String, cols: Int, rows: Int) async -> TerminalViewOpenResult {
        lock.withLock { opens.append(FakeMac.TerminalViewSize(terminalId: terminalId, cols: cols, rows: rows)) }
        await waitWhileHeld()
        if let outcome = lock.withLock({ refused[terminalId] }) { return .notOpened(outcome) }
        guard workspaces.listsTerminal(terminalId) else { return .notOpened(.notFound) }
        let fixture = lock.withLock { fixtures[terminalId] } ?? DemoTerminalScreens.prompt(cols: cols, rows: rows)
        let view = FakeMacTerminalView(terminalId: terminalId, fixture: fixture, recorder: self)
        lock.withLock { current[terminalId] = view }
        view.startTicks()
        return .opened(view)
    }

    // MARK: - TerminalCreator

    func createTerminal(workspaceId: String) async -> (outcome: WorkspaceControlOutcome, terminalId: String?) {
        let forced = lock.withLock { () -> WorkspaceControlOutcome? in
            creates.append(workspaceId)
            defer { nextCreateOutcome = nil }
            return nextCreateOutcome
        }
        if let forced, forced != .ok { return (forced, nil) }
        guard let id = workspaces.addTerminal(to: workspaceId) else { return (.notFound, nil) }
        return (.ok, id)
    }

    // MARK: - What views report

    fileprivate func recordInput(_ terminalId: String, _ units: [TerminalInputUnit]) {
        lock.withLock { inputs[terminalId, default: []].append(units) }
    }

    fileprivate func recordResize(_ terminalId: String, cols: Int, rows: Int) {
        lock.withLock { resizes.append(FakeMac.TerminalViewSize(terminalId: terminalId, cols: cols, rows: rows)) }
    }

    fileprivate func recordSnapshotRequest(_ terminalId: String) {
        lock.withLock { snapshotRequests[terminalId, default: 0] += 1 }
    }

    fileprivate func recordClose(_ view: FakeMacTerminalView) {
        lock.withLock {
            closes.append(view.terminalId)
            if current[view.terminalId] === view { current[view.terminalId] = nil }
        }
    }

    private func waitWhileHeld() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let pass = lock.withLock { () -> Bool in
                guard holding else { return true }
                held.append(continuation)
                return false
            }
            if pass { continuation.resume() }
        }
    }
}

/// One view of a fake terminal: its fixture's content, changed by typing (a fixture with a prompt) and ticks.
final class FakeMacTerminalView: TerminalView, @unchecked Sendable {
    let terminalId: String

    private let lock = NSLock()
    private let fixture: DemoTerminalFixture
    private let recorder: FakeMacTerminals
    private var history: [[TerminalRun]]
    /// Exactly `fixture.rows` rows.
    private var screen: [[TerminalRun]]
    private var cursor: TerminalCursor
    /// What was typed after the prompt on the cursor row.
    private var typed = ""
    private var queued: [TerminalViewEvent] = []
    private var needsSnapshot = true
    private var dirty = false
    /// Rows that scrolled off the top since the last frame.
    private var scrolled = 0
    private var closed = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var ticker: Task<Void, Never>?

    init(terminalId: String, fixture: DemoTerminalFixture, recorder: FakeMacTerminals) {
        self.terminalId = terminalId
        self.fixture = fixture
        self.recorder = recorder
        history = fixture.alt ? [] : fixture.history
        let rows = max(1, fixture.rows)
        screen = Array(fixture.screen.prefix(rows)) + Array(repeating: [], count: max(0, rows - fixture.screen.count))
        cursor = fixture.cursor
    }

    /// Starts printing the fixture's ticks; stopped by `close()`.
    func startTicks() {
        guard let interval = fixture.tickInterval, !fixture.ticks.isEmpty else { return }
        let task = Task { [weak self] in
            var n = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.change { $0.printLine(n) }
                n += 1
            }
        }
        lock.withLock {
            if closed { task.cancel() } else { ticker = task }
        }
    }

    /// An emitted frame or end, returned before anything else.
    func enqueue(_ event: TerminalViewEvent) {
        change { view in view.queued.append(event) }
    }

    // MARK: - TerminalView

    func nextFrame() async -> TerminalViewEvent {
        while true {
            if Task.isCancelled { return .ended(.failed) }
            let event = lock.withLock { () -> TerminalViewEvent? in
                if closed { return .ended(.failed) }
                if !queued.isEmpty { return queued.removeFirst() }
                if needsSnapshot {
                    needsSnapshot = false
                    dirty = false
                    scrolled = 0
                    return .frame(snapshotLocked())
                }
                if dirty {
                    dirty = false
                    defer { scrolled = 0 }
                    return .frame(deltaLocked())
                }
                return nil
            }
            if let event { return event }
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    let ready = lock.withLock { () -> Bool in
                        if closed || !queued.isEmpty || needsSnapshot || dirty || Task.isCancelled { return true }
                        waiter = continuation
                        return false
                    }
                    if ready { continuation.resume() }
                }
            } onCancel: {
                let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                    defer { waiter = nil }
                    return waiter
                }
                waiting?.resume()
            }
        }
    }

    func requestSnapshot() async {
        recorder.recordSnapshotRequest(terminalId)
        change { $0.needsSnapshot = true }
    }

    func input(_ units: [TerminalInputUnit]) async {
        recorder.recordInput(terminalId, units)
        guard fixture.prompt != nil else { return }
        change { view in
            for unit in units { view.apply(unit) }
        }
    }

    func resize(cols: Int, rows: Int) async {
        recorder.recordResize(terminalId, cols: cols, rows: rows)
    }

    func close() async {
        let (task, waiting) = lock.withLock { () -> (Task<Void, Never>?, CheckedContinuation<Void, Never>?) in
            closed = true
            defer {
                ticker = nil
                waiter = nil
            }
            return (ticker, waiter)
        }
        task?.cancel()
        waiting?.resume()
        recorder.recordClose(self)
    }

    // MARK: - Content (called with the lock held, through `change`)

    /// Runs `body` with the lock held, then wakes a waiting `nextFrame()`.
    private func change(_ body: (FakeMacTerminalView) -> Void) {
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            body(self)
            defer { waiter = nil }
            return waiter
        }
        waiting?.resume()
    }

    private func apply(_ unit: TerminalInputUnit) {
        switch unit {
        case let .text(text):
            typeText(text)
        case let .paste(text):
            var line = ""
            for character in text {
                if character == "\n" || character == "\r\n" || character == "\r" {
                    typeText(line)
                    line = ""
                    newPrompt()
                } else {
                    line.append(character)
                }
            }
            typeText(line)
        case let .key(.enter, mods) where mods.isEmpty:
            newPrompt()
        case let .key(.backspace, mods) where mods.isEmpty:
            guard !typed.isEmpty else { return }
            typed.removeLast()
            redrawPromptRow()
        case let .key(.letter(letter), mods) where mods == [.ctrl] && letter == "c":
            typeText("^C")
            newPrompt()
        case let .key(.letter(letter), mods) where mods == [.ctrl] && letter == "l":
            screen = [[]] + Array(repeating: [], count: screen.count - 1)
            cursor.y = 0
            typed = ""
            redrawPromptRow()
        default:
            break
        }
    }

    private func typeText(_ text: String) {
        guard !text.isEmpty else { return }
        typed += text
        redrawPromptRow()
    }

    /// The cursor row becomes the prompt and what was typed after it; the cursor follows the text.
    private func redrawPromptRow() {
        guard let prompt = fixture.prompt else { return }
        screen[cursor.y] = prompt + (typed.isEmpty ? [] : [TerminalRun(text: typed)])
        cursor.x = min(DemoTerminalScreens.columns(prompt) + typed.unicodeScalars.count, max(0, fixture.cols - 1))
        dirty = true
    }

    /// Enter: the row stays, a new prompt row starts under it.
    private func newPrompt() {
        lineFeed()
        typed = ""
        redrawPromptRow()
    }

    /// Prints tick `n` at the cursor row, then moves down a row.
    fileprivate func printLine(_ n: Int) {
        screen[cursor.y] = fixture.ticks[n % fixture.ticks.count]
        cursor.x = 0
        lineFeed()
        dirty = true
    }

    /// The cursor moves down a row; at the bottom row the screen scrolls one row (into history on the main screen).
    private func lineFeed() {
        if cursor.y < screen.count - 1 {
            cursor.y += 1
        } else {
            let top = screen.removeFirst()
            screen.append([])
            if !fixture.alt {
                history.append(top)
                scrolled += 1
            }
        }
        dirty = true
    }

    private func snapshotLocked() -> TerminalGridFrame {
        var content = fixture
        content.history = history
        content.screen = screen
        content.cursor = cursor
        return content.snapshot
    }

    /// Every screen row as a line; rows that scrolled past the whole screen go along as history rows.
    private func deltaLocked() -> TerminalGridFrame {
        let rows = screen.count
        let carried = min(max(0, scrolled - rows), history.count)
        var lines: [TerminalLine] = history.suffix(carried).enumerated().map { index, runs in
            TerminalLine(y: index - carried, runs: runs)
        }
        lines += screen.enumerated().map { y, runs in TerminalLine(y: y, runs: runs) }
        return TerminalGridFrame(
            head: TerminalFrameHead(
                kind: .delta, cols: fixture.cols, rows: rows, alt: fixture.alt, cursor: cursor, history: carried,
                scroll: fixture.alt ? 0 : scrolled),
            styles: fixture.styles, lines: lines)
    }
}
