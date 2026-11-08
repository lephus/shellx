import Foundation
import ShellXLinkCore

/// Pulls frames from one `TerminalView`, numbers them, splits them into parts and sends them (PROTOCOL.md 11.4, 11.8).
///
/// Two tasks: a puller that asks the view for its next frame only when the sender has taken the one before, so at most
/// one frame waits, and a sender that numbers, splits and sends in order.
actor TerminalViewPump {
    private let terminalId: String
    private let view: any TerminalView
    private let channel: SecureChannel
    private let onEnded: @Sendable () async -> Void

    private var puller: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var revision = 0
    /// True until a snapshot is sent, and after a gap the pump itself found: frames that are not snapshots are dropped.
    private var waitingForSnapshot = true
    private var snapshotRequested = false

    init(
        terminalId: String, view: any TerminalView, channel: SecureChannel, onEnded: @escaping @Sendable () async -> Void
    ) {
        self.terminalId = terminalId
        self.view = view
        self.channel = channel
        self.onEnded = onEnded
    }

    func start() {
        let (credits, creditsOut) = AsyncStream.makeStream(of: Void.self)
        let (events, eventsOut) = AsyncStream.makeStream(of: TerminalViewEvent.self)
        creditsOut.yield(())
        let view = self.view
        puller = Task.detached {
            for await _ in credits {
                if Task.isCancelled { break }
                let event = await view.nextFrame()
                if Task.isCancelled { break }
                eventsOut.yield(event)
                if case .ended = event { break }
            }
            eventsOut.finish()
        }
        sender = Task.detached { [self] in
            for await event in events {
                if Task.isCancelled { break }
                // The frame is out of the mailbox: the view may make the next one.
                creditsOut.yield(())
                if await !handle(event) { break }
            }
            creditsOut.finish()
            await cancelPuller()
        }
    }

    /// The phone missed part of the stream (PROTOCOL.md 11.7, 11.8): the next frame sent is a snapshot. Frames that are
    /// not snapshots are dropped until then, and resyncs that arrive before it share it.
    func resync() async {
        guard !waitingForSnapshot else { return }
        waitingForSnapshot = true
        snapshotRequested = true
        await view.requestSnapshot()
    }

    /// Ends both tasks and waits for them. Nothing is sent after it returns.
    func stop() async {
        let puller = self.puller, sender = self.sender
        puller?.cancel()
        sender?.cancel()
        await puller?.value
        await sender?.value
    }

    private func cancelPuller() {
        puller?.cancel()
    }

    // MARK: - Sending

    /// False when the sender should stop.
    private func handle(_ event: TerminalViewEvent) async -> Bool {
        switch event {
        case let .ended(reason):
            if Task.isCancelled { return false }
            _ = await send(.terminalViewEnded(terminalId: terminalId, reason: reason))
            await onEnded()
            return false
        case let .frame(frame):
            return await process(frame)
        }
    }

    private func process(_ frame: TerminalGridFrame) async -> Bool {
        if waitingForSnapshot {
            guard frame.head.kind == .snapshot else {
                if !snapshotRequested {
                    snapshotRequested = true
                    await view.requestSnapshot()
                }
                return true
            }
            waitingForSnapshot = false
            snapshotRequested = false
        }
        revision += 1
        let parts: [TerminalFramePart]
        do {
            parts = try TerminalFrameSplitter.parts(of: frame, revision: revision, terminalId: terminalId)
        } catch {
            linkLog.error("a terminal frame cannot be split: \(String(describing: error), privacy: .public)")
            return await fail()
        }
        for part in parts {
            if Task.isCancelled { return false }
            guard await send(.terminalViewFrame(terminalId: terminalId, frame: part)) else { return false }
        }
        return true
    }

    /// The pump cannot go on: tell the phone and end the view.
    private func fail() async -> Bool {
        if Task.isCancelled { return false }
        _ = await send(.terminalViewEnded(terminalId: terminalId, reason: .failed))
        await onEnded()
        return false
    }

    /// False when the channel is gone.
    private func send(_ message: LinkMessage) async -> Bool {
        do {
            try await channel.send(frame: LinkCodec.encode(message))
            return true
        } catch {
            return false
        }
    }
}
