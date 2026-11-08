import Foundation
import ShellXLinkCore

/// The terminal view of one session: at most one (PROTOCOL.md 11.1). Created by `LinkHost` for a session when the host
/// has a `TerminalViewSource`.
actor TerminalViewSlot {
    /// One open view. Only the slot touches it.
    private final class Active {
        let terminalId: String
        let view: any TerminalView
        let generation: Int
        var pump: TerminalViewPump?
        var closed = false

        init(terminalId: String, view: any TerminalView, generation: Int) {
            self.terminalId = terminalId
            self.view = view
            self.generation = generation
        }
    }

    private let source: any TerminalViewSource
    private let channel: SecureChannel
    private var active: Active?
    private var nextGeneration = 0

    init(source: any TerminalViewSource, channel: SecureChannel) {
        self.source = source
        self.channel = channel
    }

    /// `cols` and `rows` are already clamped.
    func open(callId: String, terminalId: String, cols: Int, rows: Int) async {
        if let current = active {
            if current.terminalId == terminalId {
                await stop(current)
            } else {
                try? await channel.send(.terminalViewOpenResult(callId: callId, outcome: .busy))
                return
            }
        }
        switch await source.openView(terminalId: terminalId, cols: cols, rows: rows) {
        case let .notOpened(outcome):
            try? await channel.send(.terminalViewOpenResult(callId: callId, outcome: outcome == .ok ? .failed : outcome))
        case let .opened(view):
            nextGeneration += 1
            let opened = Active(terminalId: terminalId, view: view, generation: nextGeneration)
            active = opened
            // The answer goes out before the first frame.
            do {
                try await channel.send(.terminalViewOpenResult(callId: callId, outcome: .ok))
            } catch {
                await stop(opened)
                return
            }
            let generation = opened.generation
            let pump = TerminalViewPump(terminalId: terminalId, view: view, channel: channel) { [weak self] in
                await self?.viewEnded(generation: generation)
            }
            opened.pump = pump
            await pump.start()
        }
    }

    func close(terminalId: String) async {
        guard let current = active, current.terminalId == terminalId else { return }
        await stop(current)
    }

    /// The session ended.
    func endSession() async {
        if let current = active { await stop(current) }
    }

    private func stop(_ view: Active) async {
        if active === view { active = nil }
        await view.pump?.stop()
        await closeOnce(view)
    }

    /// The pump ended the view (the source ended it, or it could not go on): forget it and close the view.
    private func viewEnded(generation: Int) async {
        guard let current = active, current.generation == generation else { return }
        active = nil
        await closeOnce(current)
    }

    private func closeOnce(_ view: Active) async {
        guard !view.closed else { return }
        view.closed = true
        await view.view.close()
    }
}
