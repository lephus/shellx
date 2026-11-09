import Foundation
import ShellXLinkCore
import ShellXLinkRelay
import ShellXLinkSession

/// A `TerminalCreator` that logs its calls and answers what the test says.
final class FakeTerminalCreator: TerminalCreator, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    private var result: (outcome: WorkspaceControlOutcome, terminalId: String?) = (.ok, "t-new")
    private var gate: Gate?

    var calls: [String] { lock.withLock { _calls } }

    func setCreate(_ outcome: WorkspaceControlOutcome, terminalId: String?) {
        lock.withLock { result = (outcome, terminalId) }
    }

    /// Later calls wait for `gate` after they are logged.
    func hold(until gate: Gate) {
        lock.withLock { self.gate = gate }
    }

    func createTerminal(workspaceId: String) async -> (outcome: WorkspaceControlOutcome, terminalId: String?) {
        let (answer, gate) = lock.withLock { () -> ((outcome: WorkspaceControlOutcome, terminalId: String?), Gate?) in
            _calls.append(workspaceId)
            return (result, self.gate)
        }
        await gate?.wait()
        return answer
    }
}

// MARK: - Views

final class FakeTerminalViewSource: TerminalViewSource, @unchecked Sendable {
    struct Open: Equatable {
        let terminalId: String
        let cols: Int
        let rows: Int
    }

    private let lock = NSLock()
    private var _opens: [Open] = []
    private var _views: [FakeTerminalView] = []
    private var refusals: [String: TerminalViewOpenOutcome] = [:]
    private var prepares: [String: @Sendable (FakeTerminalView, Int) -> Void] = [:]
    private var counts: [String: Int] = [:]

    var opens: [Open] { lock.withLock { _opens } }
    /// In open order.
    var views: [FakeTerminalView] { lock.withLock { _views } }

    func refuse(_ terminalId: String, with outcome: TerminalViewOpenOutcome) {
        lock.withLock { refusals[terminalId] = outcome }
    }

    /// Runs on each new view of `terminalId` (with its 1-based count for that id) before the host gets it.
    func onOpen(_ terminalId: String, _ prepare: @escaping @Sendable (FakeTerminalView, Int) -> Void) {
        lock.withLock { prepares[terminalId] = prepare }
    }

    func openView(terminalId: String, cols: Int, rows: Int) async -> TerminalViewOpenResult {
        let (refusal, prepare, count) = lock.withLock { () -> (TerminalViewOpenOutcome?, (@Sendable (FakeTerminalView, Int) -> Void)?, Int) in
            _opens.append(Open(terminalId: terminalId, cols: cols, rows: rows))
            counts[terminalId, default: 0] += 1
            return (refusals[terminalId], prepares[terminalId], counts[terminalId] ?? 1)
        }
        if let refusal { return .notOpened(refusal) }
        let view = FakeTerminalView()
        prepare?(view, count)
        lock.withLock { _views.append(view) }
        return .opened(view)
    }
}

final class FakeTerminalView: TerminalView, @unchecked Sendable {
    enum Call: Equatable {
        case input([TerminalInputUnit])
        case resize(cols: Int, rows: Int)
        case close
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var _snapshotRequests = 0
    private var _nextFrameCalls = 0
    private var running = 0
    private var _maxConcurrent = 0
    private var _inputsStarted = 0
    private var queue: [TerminalViewEvent] = []
    private var produce: (@Sendable (Int) -> TerminalViewEvent?)?
    private var produced = 0
    private var snapshotAnswer: (gate: Gate?, events: @Sendable () -> [TerminalViewEvent])?
    private var inputGate: Gate?
    private var closed = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var signalled = false

    var calls: [Call] { lock.withLock { _calls } }
    var snapshotRequests: Int { lock.withLock { _snapshotRequests } }
    var nextFrameCalls: Int { lock.withLock { _nextFrameCalls } }
    var maxConcurrentNextFrameCalls: Int { lock.withLock { _maxConcurrent } }
    /// `input` calls entered, held or not.
    var inputsStarted: Int { lock.withLock { _inputsStarted } }

    /// Queued for `nextFrame()`.
    func emit(_ events: TerminalViewEvent...) {
        lock.withLock { queue += events }
        signal()
    }

    /// With nothing queued, `nextFrame()` returns `produce(n)` (n = 1, 2, ... per produced event); nil means wait.
    func produceOnDemand(_ produce: @escaping @Sendable (Int) -> TerminalViewEvent?) {
        lock.withLock { self.produce = produce }
        signal()
    }

    /// `requestSnapshot()` also queues these events; with a `gate`, `nextFrame()` hands them out only once it is open.
    func answerSnapshotRequests(after gate: Gate? = nil, with events: @escaping @Sendable () -> [TerminalViewEvent]) {
        lock.withLock { snapshotAnswer = (gate, events) }
    }

    /// Every later `input` and `resize` waits for `gate` before it is logged in `calls`.
    func holdInput(until gate: Gate) {
        lock.withLock { inputGate = gate }
    }

    func nextFrame() async -> TerminalViewEvent {
        lock.withLock {
            _nextFrameCalls += 1
            running += 1
            _maxConcurrent = max(_maxConcurrent, running)
        }
        defer { lock.withLock { running -= 1 } }
        while true {
            if Task.isCancelled || lock.withLock({ closed }) { return .ended(.failed) }
            if let event = takeReady() { return event }
            await waitForSignal()
        }
    }

    private func takeReady() -> TerminalViewEvent? {
        lock.withLock {
            if !queue.isEmpty { return queue.removeFirst() }
            if let produce {
                let next = produced + 1
                if let event = produce(next) {
                    produced = next
                    return event
                }
            }
            return nil
        }
    }

    func requestSnapshot() async {
        let answer = lock.withLock { () -> (gate: Gate?, events: @Sendable () -> [TerminalViewEvent])? in
            _snapshotRequests += 1
            return snapshotAnswer
        }
        guard let answer else { return }
        let events = answer.events()
        if let gate = answer.gate {
            Task {
                await gate.wait()
                self.lock.withLock { self.queue += events }
                self.signal()
            }
        } else {
            lock.withLock { queue += events }
            signal()
        }
    }

    func input(_ units: [TerminalInputUnit]) async {
        let gate = lock.withLock { () -> Gate? in
            _inputsStarted += 1
            return inputGate
        }
        await gate?.wait()
        lock.withLock { _calls.append(.input(units)) }
    }

    func resize(cols: Int, rows: Int) async {
        let gate = lock.withLock { inputGate }
        await gate?.wait()
        lock.withLock { _calls.append(.resize(cols: cols, rows: rows)) }
    }

    func close() async {
        lock.withLock {
            _calls.append(.close)
            closed = true
        }
        signal()
    }

    private func signal() {
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            if let waiter {
                self.waiter = nil
                return waiter
            }
            signalled = true
            return nil
        }
        waiting?.resume()
    }

    private func waitForSignal() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let immediately = lock.withLock { () -> Bool in
                    if signalled {
                        signalled = false
                        return true
                    }
                    waiter = continuation
                    return false
                }
                if immediately { continuation.resume() }
            }
        } onCancel: {
            signal()
        }
    }
}

// MARK: - Frames

let testPalette = TerminalPalette(
    fg: "#d0d0d0", bg: "#101010", cursor: nil, colors: (0..<256).map { String(format: "#%02x%02x%02x", $0, $0, $0) })

/// Screen row i is `text[i]` (narrow), history rows oldest first, cursor (0,0); `palette` `testPalette`.
func snapshotFrame(cols: Int, rows: Int, text: [String], history: [String] = [], alt: Bool = false) -> TerminalGridFrame {
    var lines: [TerminalLine] = []
    for (i, row) in history.enumerated() where !row.isEmpty {
        lines.append(TerminalLine(y: i - history.count, runs: [TerminalRun(text: row)]))
    }
    for (i, row) in text.enumerated() where !row.isEmpty { lines.append(TerminalLine(y: i, runs: [TerminalRun(text: row)])) }
    let head = TerminalFrameHead(
        kind: .snapshot, cols: cols, rows: rows, alt: alt, cursor: TerminalCursor(x: 0, y: 0), palette: testPalette,
        history: alt ? 0 : history.count)
    return TerminalGridFrame(head: head, lines: lines)
}

/// Replaces the given rows; `history` rows ride at y -history.count ... -1.
func deltaFrame(
    cols: Int, rows: Int, replacing: [Int: String], scroll: Int = 0, history: [String] = [], alt: Bool = false
) -> TerminalGridFrame {
    var lines: [TerminalLine] = []
    for (i, row) in history.enumerated() { lines.append(TerminalLine(y: i - history.count, runs: row.isEmpty ? [] : [TerminalRun(text: row)])) }
    for y in replacing.keys.sorted() {
        let row = replacing[y] ?? ""
        lines.append(TerminalLine(y: y, runs: row.isEmpty ? [] : [TerminalRun(text: row)]))
    }
    let head = TerminalFrameHead(
        kind: .delta, cols: cols, rows: rows, alt: alt, cursor: TerminalCursor(x: 0, y: 0), history: history.count, scroll: scroll)
    return TerminalGridFrame(head: head, lines: lines)
}

// MARK: - A slow network

/// Wraps the host's end of a circuit: after `pause(afterSends:)` lets that many sends through, later ones wait for
/// `resume()`. `receive` and `close` pass through.
final class PausableCircuit: RelayCircuit, @unchecked Sendable {
    private let inner: any RelayCircuit
    private let lock = NSLock()
    /// Nil: not paused. Otherwise how many sends may still pass.
    private var allowance: Int?
    private var held: [CheckedContinuation<Void, Never>] = []

    init(_ inner: any RelayCircuit) {
        self.inner = inner
    }

    var sendsWaiting: Int { lock.withLock { held.count } }

    func pause(afterSends n: Int) {
        lock.withLock { allowance = n }
    }

    func resume() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            allowance = nil
            defer { held = [] }
            return held
        }
        for continuation in pending { continuation.resume() }
    }

    func send(_ data: Data) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let passes = lock.withLock { () -> Bool in
                guard let remaining = allowance else { return true }
                if remaining > 0 {
                    allowance = remaining - 1
                    return true
                }
                held.append(continuation)
                return false
            }
            if passes { continuation.resume() }
        }
        try await inner.send(data)
    }

    func receive() async throws -> Data { try await inner.receive() }

    func close() async { await inner.close() }
}

final class PausableBox: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: PausableCircuit?

    /// For `connect(rig, wrap: box.wrap)`.
    func wrap(_ inner: any RelayCircuit) -> any RelayCircuit {
        let circuit = PausableCircuit(inner)
        lock.withLock { kept = circuit }
        return circuit
    }

    var circuit: PausableCircuit { lock.withLock { kept! } }
}
