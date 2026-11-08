import Foundation
import ShellXLinkCore

/// Pulls frames from one `TerminalView`, numbers them, splits them into parts and sends them (PROTOCOL.md 11.4, 11.8).
///
/// Two tasks: a puller that asks the view for its next frame only when the mailbox (one slot) is empty, so the host
/// holds at most one frame it has not begun to send, and a sender that numbers, splits and sends in order. The sender
/// also sends the history fill that follows a snapshot, one history frame at a time and only while the mailbox is
/// empty, so a fill never holds up a delta.
actor TerminalViewPump {
    private let terminalId: String
    private let view: any TerminalView
    private let channel: SecureChannel
    private let onEnded: @Sendable () async -> Void

    private var puller: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var revision = 0
    /// True until a snapshot is sent, and after a gap: frames that are not snapshots are dropped meanwhile.
    private var waitingForSnapshot = true
    private var snapshotRequested = false
    /// The size and screen of the last snapshot sent: deltas must have them.
    private var shape: (cols: Int, rows: Int, alt: Bool)?
    private var fill: Fill?

    // The mailbox and its two waiters.
    private var mailbox: TerminalViewEvent?
    private var senderWaiter: CheckedContinuation<TerminalViewEvent?, Never>?
    private var pullerWaiter: CheckedContinuation<Bool, Never>?
    private var stopped = false

    /// What is left of the history of the last snapshot, to send as history frames.
    private struct Fill {
        let cols: Int
        let rows: Int
        /// Capture rows are counted from the newest: row d is at y = -d. `next` rows are already with the phone.
        var next: Int
        let total: Int
        var bytes = 0
        let linesByY: [Int: [TerminalLine]]
        let styles: [Int: TerminalStyle]
    }

    init(
        terminalId: String, view: any TerminalView, channel: SecureChannel, onEnded: @escaping @Sendable () async -> Void
    ) {
        self.terminalId = terminalId
        self.view = view
        self.channel = channel
        self.onEnded = onEnded
    }

    func start() {
        let view = self.view
        puller = Task.detached { [self] in
            while await waitUntilMailboxEmpty() {
                let event = await view.nextFrame()
                if Task.isCancelled { break }
                await put(event)
                if case .ended = event { break }
            }
        }
        sender = Task.detached { [self] in
            await runSender()
        }
    }

    /// The phone missed part of the stream (PROTOCOL.md 11.7, 11.8): the next frame sent is a snapshot. The fill is
    /// dropped, frames that are not snapshots are dropped until then, and resyncs that arrive before it share it.
    func resync() async {
        fill = nil
        guard !waitingForSnapshot else { return }
        waitingForSnapshot = true
        snapshotRequested = true
        await view.requestSnapshot()
    }

    /// Ends both tasks and waits for them. Nothing is sent after it returns.
    func stop() async {
        shutdown()
        let puller = self.puller, sender = self.sender
        puller?.cancel()
        sender?.cancel()
        await puller?.value
        await sender?.value
    }

    // MARK: - Mailbox

    private func shutdown() {
        stopped = true
        mailbox = nil
        senderWaiter?.resume(returning: nil)
        senderWaiter = nil
        pullerWaiter?.resume(returning: false)
        pullerWaiter = nil
    }

    private func waitUntilMailboxEmpty() async -> Bool {
        if stopped { return false }
        if mailbox == nil { return true }
        return await withCheckedContinuation { pullerWaiter = $0 }
    }

    private func put(_ event: TerminalViewEvent) {
        guard !stopped else { return }
        if let waiter = senderWaiter {
            senderWaiter = nil
            waiter.resume(returning: event)
        } else {
            mailbox = event
        }
    }

    private func takeNow() -> TerminalViewEvent? {
        guard let event = mailbox else { return nil }
        mailbox = nil
        pullerWaiter?.resume(returning: true)
        pullerWaiter = nil
        return event
    }

    private func waitForEvent() async -> TerminalViewEvent? {
        if let event = takeNow() { return event }
        if stopped { return nil }
        return await withCheckedContinuation { senderWaiter = $0 }
    }

    // MARK: - Sender

    private func runSender() async {
        while !Task.isCancelled, !stopped {
            if let event = takeNow() {
                guard await handle(event) else { break }
            } else if fill != nil, let block = nextBlock() {
                guard await send(block) else { break }
            } else {
                fill = nil
                guard let event = await waitForEvent() else { break }
                guard await handle(event) else { break }
            }
        }
        shutdown()
    }

    /// False when the sender should stop.
    private func handle(_ event: TerminalViewEvent) async -> Bool {
        switch event {
        case let .ended(reason):
            if Task.isCancelled { return false }
            _ = await sendMessage(.terminalViewEnded(terminalId: terminalId, reason: reason))
            await onEnded()
            return false
        case let .frame(frame):
            return await process(frame)
        }
    }

    private func process(_ frame: TerminalGridFrame) async -> Bool {
        let head = frame.head
        let limit = 1...ShellXLink.terminalMaxGridSize
        guard limit.contains(head.cols), limit.contains(head.rows) else { return await fail() }
        switch head.kind {
        case .snapshot:
            waitingForSnapshot = false
            snapshotRequested = false
            return await sendSnapshot(frame)
        case .delta:
            if waitingForSnapshot { return await askForSnapshot() }
            guard let shape, shape.cols == head.cols, shape.rows == head.rows, shape.alt == head.alt else {
                waitingForSnapshot = true
                return await askForSnapshot()
            }
            return await sendDelta(frame)
        case .history, .other:
            // A source never sends history frames: this host makes them.
            return await askForSnapshot()
        }
    }

    /// Drops the frame being handled and asks the view for a snapshot, once until one arrives.
    private func askForSnapshot() async -> Bool {
        waitingForSnapshot = true
        if !snapshotRequested {
            snapshotRequested = true
            await view.requestSnapshot()
        }
        return true
    }

    private func sendSnapshot(_ frame: TerminalGridFrame) async -> Bool {
        let head = frame.head
        let total = head.alt ? 0 : min(head.history, ShellXLink.terminalHistoryRowBudget)
        var quick = min(ShellXLink.terminalSnapshotHistoryRows, total)
        revision += 1
        var parts: [TerminalFramePart]
        do {
            parts = try Self.split(Self.snapshot(frame, keeping: quick), revision: revision, terminalId: terminalId)
        } catch {
            // Without the 240 rows, the whole history comes by fill.
            quick = 0
            do {
                parts = try Self.split(Self.snapshot(frame, keeping: 0), revision: revision, terminalId: terminalId)
            } catch {
                linkLog.error("a terminal snapshot cannot be split: \(String(describing: error), privacy: .public)")
                return await fail()
            }
        }
        // Before the first send: a resync that arrives while the parts go out drops this fill too.
        shape = (head.cols, head.rows, head.alt)
        fill = nil
        if total > quick {
            var byY: [Int: [TerminalLine]] = [:]
            for line in frame.lines where line.y < -quick && line.y >= -total { byY[line.y, default: []].append(line) }
            fill = Fill(
                cols: head.cols, rows: head.rows, next: quick, total: total, linesByY: byY,
                styles: Dictionary(frame.styles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }))
        }
        return await send(parts)
    }

    private func sendDelta(_ frame: TerminalGridFrame) async -> Bool {
        let head = frame.head
        let allowed = min(head.history, ShellXLink.terminalMaxDeltaHistoryRows, max(0, head.scroll - head.rows))
        var clamped = frame
        clamped.head.history = allowed
        if allowed != head.history {
            clamped.lines = frame.lines.filter { $0.y >= -allowed }
            clamped.styles = Self.styles(frame.styles, usedBy: clamped.lines)
        }
        revision += 1
        let parts: [TerminalFramePart]
        do {
            parts = try Self.split(clamped, revision: revision, terminalId: terminalId)
        } catch {
            linkLog.error("a terminal delta cannot be split: \(String(describing: error), privacy: .public)")
            return await fail()
        }
        return await send(parts)
    }

    /// The next history frame of the fill, as parts, or nil when the fill is done or the next block would pass the
    /// byte cap (the fill is then dropped).
    private func nextBlock() -> [TerminalFramePart]? {
        guard var current = fill else { return nil }
        let count = min(ShellXLink.terminalSnapshotHistoryRows, current.total - current.next)
        guard count > 0 else {
            fill = nil
            return nil
        }
        var lines: [TerminalLine] = []
        for local in stride(from: -count, through: -1, by: 1) {
            for line in current.linesByY[local - current.next] ?? [] { lines.append(TerminalLine(y: local, runs: line.runs)) }
        }
        let head = TerminalFrameHead(kind: .history, cols: current.cols, rows: current.rows, alt: false, history: count)
        let frame = TerminalGridFrame(head: head, styles: Self.styles(Array(current.styles.values), usedBy: lines), lines: lines)
        guard let parts = try? Self.split(frame, revision: revision + 1, terminalId: terminalId),
              let size = try? parts.reduce(0, { try $0 + LinkCodec.encode(.terminalViewFrame(terminalId: terminalId, frame: $1)).count }),
              current.bytes + size <= ShellXLink.terminalHistoryFillMaxBytes
        else {
            fill = nil
            return nil
        }
        current.bytes += size
        current.next += count
        fill = current
        revision += 1
        return parts
    }

    private static func snapshot(_ frame: TerminalGridFrame, keeping quick: Int) -> TerminalGridFrame {
        var kept = frame
        kept.head.history = quick
        kept.lines = frame.lines.filter { $0.y >= -quick }
        kept.styles = styles(frame.styles, usedBy: kept.lines)
        return kept
    }

    /// The styles `lines` use, in id order.
    private static func styles(_ table: [TerminalStyle], usedBy lines: [TerminalLine]) -> [TerminalStyle] {
        var used = Set<Int>()
        for line in lines { for run in line.runs { if let id = run.style, id != 0 { used.insert(id) } } }
        return table.filter { used.contains($0.id) }.sorted { $0.id < $1.id }
    }

    private static func split(_ frame: TerminalGridFrame, revision: Int, terminalId: String) throws -> [TerminalFramePart] {
        try TerminalFrameSplitter.parts(of: frame, revision: revision, terminalId: terminalId)
    }

    // MARK: - Sending

    /// The pump cannot go on: tell the phone and end the view.
    private func fail() async -> Bool {
        if Task.isCancelled { return false }
        _ = await sendMessage(.terminalViewEnded(terminalId: terminalId, reason: .failed))
        await onEnded()
        return false
    }

    private func send(_ parts: [TerminalFramePart]) async -> Bool {
        for part in parts {
            if Task.isCancelled || stopped { return false }
            guard await sendMessage(.terminalViewFrame(terminalId: terminalId, frame: part)) else { return false }
        }
        return true
    }

    /// False when the channel is gone.
    private func sendMessage(_ message: LinkMessage) async -> Bool {
        do {
            try await channel.send(frame: LinkCodec.encode(message))
            return true
        } catch {
            return false
        }
    }
}
