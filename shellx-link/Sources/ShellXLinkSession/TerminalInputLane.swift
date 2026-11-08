import Foundation
import ShellXLinkCore

/// The input and resize messages of one view, applied one at a time in the order they arrived (PROTOCOL.md 11.2).
/// At most `ShellXLink.terminalMaxQueuedInputs` wait besides the one being applied; later ones are dropped.
actor TerminalInputLane {
    enum Item: Sendable {
        case input([TerminalInputUnit])
        case resize(cols: Int, rows: Int)
    }

    private let view: any TerminalView
    private var queue: [Item] = []
    private var running = false
    private var cancelled = false
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    init(view: any TerminalView) {
        self.view = view
    }

    /// False when the item was dropped because too many wait.
    func enqueue(_ item: Item) -> Bool {
        guard !cancelled, queue.count < ShellXLink.terminalMaxQueuedInputs else { return false }
        queue.append(item)
        if !running {
            running = true
            Task { await self.run() }
        }
        return true
    }

    /// Returns once everything queued so far has been applied.
    func drain() async {
        guard running || !queue.isEmpty else { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }

    /// Drops what waits (the view ended; nothing more is applied).
    func cancel() {
        cancelled = true
        queue = []
        wakeDrainers()
    }

    private func run() async {
        while !cancelled, !queue.isEmpty {
            let item = queue.removeFirst()
            switch item {
            case let .input(units): await view.input(units)
            case let .resize(cols, rows): await view.resize(cols: cols, rows: rows)
            }
        }
        running = false
        wakeDrainers()
    }

    private func wakeDrainers() {
        let waiting = drainWaiters
        drainWaiters = []
        for waiter in waiting { waiter.resume() }
    }
}
