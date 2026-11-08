import Foundation
import ShellXLinkCore
import ShellXLinkSession

@testable import ShellXAppCore

/// Reads `pushes` as they come: every push, and the screen of the newest view of `terminalId` (a fresh 2A
/// `TerminalFrameAssembler` and `TerminalScreen` at each `.opened(terminalId)`; frames of other terminals ignored).
final class TerminalPushReader: @unchecked Sendable {
    private let lock = NSLock()
    private let terminalId: String
    private var received: [TerminalViewPush] = []
    private var assembler = TerminalFrameAssembler()
    private var current = TerminalScreen()
    private var task: Task<Void, Never>?

    init(_ pushes: AsyncStream<TerminalViewPush>, terminalId: String) {
        self.terminalId = terminalId
        task = Task { [weak self] in
            for await push in pushes {
                guard let self else { return }
                self.take(push)
            }
        }
    }

    deinit {
        task?.cancel()
    }

    var pushes: [TerminalViewPush] { lock.withLock { received } }
    var screen: TerminalScreen { lock.withLock { current } }

    private func take(_ push: TerminalViewPush) {
        lock.withLock {
            received.append(push)
            switch push {
            case let .opened(id) where id == terminalId:
                assembler = TerminalFrameAssembler()
                current = TerminalScreen()
            case let .frame(id, part) where id == terminalId:
                if let frame = assembler.receive(part).frame { current.apply(frame) }
            default:
                break
            }
        }
    }
}

/// Keeps every element of `stream` as it arrives.
final class Collector<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [Element] = []
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<Element>) {
        task = Task { [weak self] in
            for await element in stream {
                guard let self else { return }
                self.lock.withLock { self.kept.append(element) }
            }
        }
    }

    deinit {
        task?.cancel()
    }

    var items: [Element] { lock.withLock { kept } }
}

/// A `TerminalLink` the test drives: it records every call, answers each open from `openAnswers` (then `.outcome(.ok)`),
/// after `openGate` when one is set, and hands `emit(_:)` to every stream `terminalEvents()` returned.
@MainActor final class ScriptedTerminalLink: TerminalLink {
    enum Call: Equatable {
        case open(String, cols: Int, rows: Int), close(String), input(String, [TerminalInputUnit])
        case resize(String, cols: Int, rows: Int), resync(String)
    }

    /// In order.
    var calls: [Call] = []
    var online = true
    var supportsViews = true
    var openAnswers: [TerminalOpenResult] = []
    var openGate: Gate?
    /// Every `recordLatency` call, in order.
    var samples: [(metric: LatencyMetric, duration: Duration)] = []
    private var subscribers: [UUID: AsyncStream<TerminalHubEvent>.Continuation] = [:]

    var latencies: [LatencyMetric] { samples.map(\.metric) }
    /// How many `terminalEvents()` streams are still read: 1 once a model's `run()` has started.
    var subscriberCount: Int { subscribers.count }
    /// The terminal ids of the open calls.
    var opens: [String] {
        calls.compactMap { if case let .open(id, _, _) = $0 { return id } else { return nil } }
    }
    /// The units of the input calls.
    var inputs: [[TerminalInputUnit]] {
        calls.compactMap { if case let .input(_, units) = $0 { return units } else { return nil } }
    }

    func emit(_ event: TerminalHubEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }

    func terminalEvents() -> AsyncStream<TerminalHubEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: TerminalHubEvent.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[id] = nil }
        }
        return stream
    }

    func isOnline(_ machineID: String) -> Bool { online }
    func supportsTerminalView(_ machineID: String) -> Bool { supportsViews }

    func openTerminalView(machineID: String, terminalId: String, cols: Int, rows: Int) async -> TerminalOpenResult {
        calls.append(.open(terminalId, cols: cols, rows: rows))
        if let openGate { await openGate.wait() }
        return openAnswers.isEmpty ? .outcome(.ok) : openAnswers.removeFirst()
    }

    func closeTerminalView(machineID: String, terminalId: String) async { calls.append(.close(terminalId)) }

    func sendTerminalInput(machineID: String, terminalId: String, units: [TerminalInputUnit]) async {
        calls.append(.input(terminalId, units))
    }

    func resizeTerminalView(machineID: String, terminalId: String, cols: Int, rows: Int) async {
        calls.append(.resize(terminalId, cols: cols, rows: rows))
    }

    func resyncTerminalView(machineID: String, terminalId: String) async { calls.append(.resync(terminalId)) }

    func recordLatency(_ metric: LatencyMetric, _ duration: Duration) { samples.append((metric, duration)) }
}

/// fg #d0d0d0, bg #101010, colors[i] = grey i.
let testPalette = TerminalPalette(
    fg: "#d0d0d0", bg: "#101010", colors: (0..<256).map { String(format: "#%02x%02x%02x", $0, $0, $0) })

private func textLine(_ y: Int, _ text: String) -> TerminalLine {
    TerminalLine(y: y, runs: text.isEmpty ? [] : [TerminalRun(x: 0, text: text)])
}

/// History lines at y = -lines.count ... -1, oldest first.
private func historyLines(_ lines: [String]) -> [TerminalLine] {
    lines.enumerated().map { textLine($0.offset - lines.count, $0.element) }
}

/// One whole frame in one part (part 0 of 1). Snapshot head: cursor (0, 0), `testPalette`, `history` = history.count;
/// history rows at y = -history.count ... -1, then `text[i]` at y = i.
func snapshotPart(
    revision: Int, cols: Int = 20, rows: Int = 2, text: [String], history: [String] = [], alt: Bool = false
) -> TerminalFramePart {
    let head = TerminalFrameHead(
        kind: .snapshot, cols: cols, rows: rows, alt: alt, cursor: TerminalCursor(x: 0, y: 0), palette: testPalette,
        history: history.count)
    let lines = historyLines(history) + text.enumerated().map { textLine($0.offset, $0.element) }
    return TerminalFramePart(revision: revision, head: head, lines: lines)
}

/// A delta in one part. Head: cursor (0, 0), `scroll`, `history` = history.count; `replacing[y]` at y.
func deltaPart(
    revision: Int, cols: Int = 20, rows: Int = 2, replacing: [Int: String], scroll: Int = 0, history: [String] = [],
    alt: Bool = false
) -> TerminalFramePart {
    let head = TerminalFrameHead(
        kind: .delta, cols: cols, rows: rows, alt: alt, cursor: TerminalCursor(x: 0, y: 0), history: history.count,
        scroll: scroll)
    let lines = historyLines(history) + replacing.keys.sorted().map { textLine($0, replacing[$0] ?? "") }
    return TerminalFramePart(revision: revision, head: head, lines: lines)
}

/// Older history rows in one part: `lines` (oldest first) go above the oldest row held.
func historyPart(revision: Int, cols: Int = 20, rows: Int = 2, lines: [String]) -> TerminalFramePart {
    let head = TerminalFrameHead(kind: .history, cols: cols, rows: rows, history: lines.count)
    return TerminalFramePart(revision: revision, head: head, lines: historyLines(lines))
}

/// A `now` the test moves by hand, for `TerminalViewModel(now:)`: `base + offset` under a lock.
final class SteppedNow: @unchecked Sendable {
    private let lock = NSLock()
    private let base = ContinuousClock.now
    private var offset: Duration = .zero

    var now: @Sendable () -> ContinuousClock.Instant {
        { [self] in lock.withLock { base + offset } }
    }

    func advance(by duration: Duration) {
        lock.withLock { offset += duration }
    }
}
