import Foundation
import ShellXLinkCore
import ShellXLinkSession

/// `terminal-view`, `terminal-type` and `terminal-create`: a phone's terminal views (PROTOCOL.md section 11).
enum TerminalCommands {
    /// Opens a view and logs what a phone would draw, until the view or its session ends (exit 4) or `--seconds` pass.
    static func view(_ args: Arguments) async throws {
        let terminalId = args.positional[0]
        let (cols, rows) = try size(args)
        let seconds = try args.optionalInt("seconds")
        let client = try await Session.open(args).client
        try requireFeature(client, ShellXLink.terminalViewFeature)
        let watcher = ViewWatcher(client: client, terminalId: terminalId)
        let consumer = Task { await watcher.consume() }
        let outcome = try await watcher.open(cols: cols, rows: rows)
        guard outcome == .ok else {
            await client.close()
            throw ExitStatus(code: 2)
        }
        let closedByTimer = Flag()
        let timer = seconds.map { seconds in
            Task {
                try await Task.sleep(for: .seconds(seconds))
                closedByTimer.set()
                Log.line("terminal-view: \(seconds) s elapsed, closing")
                await client.close()
            }
        }
        await consumer.value
        timer?.cancel()
        await watcher.printScreen("when it stopped")
        if !closedByTimer.isSet {
            Log.line("terminal-view: the view or its session ended at \(Log.wallClock())")
            throw ExitStatus(code: 4)
        }
    }

    /// Opens a view, waits for its first snapshot, sends one input message and logs the time until the next frame.
    static func type(_ args: Arguments) async throws {
        let terminalId = args.positional[0]
        let units = try inputUnits(args)
        do throws(TerminalInputError) {
            try TerminalInputCheck.check(units)
        } catch {
            throw ProbeError("invalid input: \(error.reason)")
        }
        if args.flag("dry-run") {
            let frame = try LinkCodec.encode(.terminalViewInput(terminalId: terminalId, units: units))
            print(String(decoding: frame, as: UTF8.self))
            return
        }
        let (cols, rows) = try size(args)
        let waitMs = try args.optionalInt("wait-ms") ?? 1000
        let client = try await Session.open(args).client
        try requireFeature(client, ShellXLink.terminalViewFeature)
        let watcher = ViewWatcher(client: client, terminalId: terminalId)
        let consumer = Task { await watcher.consume() }
        let outcome = try await watcher.open(cols: cols, rows: rows)
        guard outcome == .ok else {
            await client.close()
            throw ExitStatus(code: 2)
        }
        guard await watcher.waitForFirstSnapshot(timeout: .seconds(10)) else {
            await client.close()
            throw ProbeError("no snapshot arrived within 10 s")
        }
        let echo = watcher.nextFrameWaiter()
        let started = ContinuousClock.now
        try await client.sendTerminalInput(terminalId: terminalId, units: units)
        if let at = await echo.value(timeout: .seconds(10)) {
            Log.line("echo \(Stats.format(Stats.ms(at - started))) ms")
        } else {
            Log.line("echo: no frame within 10 s")
        }
        try await Task.sleep(for: .milliseconds(waitMs))
        await watcher.printScreen("after the input")
        try? await client.closeTerminalView(terminalId: terminalId)
        await client.close()
        await consumer.value
    }

    static func create(_ args: Arguments) async throws {
        let workspaceId = args.positional[0]
        let client = try await Session.open(args).client
        try requireFeature(client, ShellXLink.terminalCreateFeature)
        let started = ContinuousClock.now
        let result = try await client.createTerminal(workspaceId: workspaceId)
        Log.line(
            "terminal.create \(Log.shown(workspaceId)) outcome=\(Log.shown(result.outcome.wire))"
                + (result.terminalId.map { " terminal=\(Log.shown($0))" } ?? "")
                + " rtt=\(Stats.format(Stats.ms(ContinuousClock.now - started))) ms")
        await client.close()
        if result.outcome != .ok { throw ExitStatus(code: 2) }
    }

    // MARK: - Arguments

    private static func size(_ args: Arguments) throws -> (Int, Int) {
        (try args.optionalInt("cols") ?? 80, try args.optionalInt("rows") ?? 24)
    }

    /// Exit 3 when the Mac does not offer `feature`.
    private static func requireFeature(_ client: LinkClient, _ feature: String) throws {
        guard client.hostFeatures.contains(feature) else {
            Log.line("the Mac does not offer \(feature)")
            throw ExitStatus(code: 3)
        }
    }

    /// The paste file's text, then `--text`, then each `--key`, in that order.
    private static func inputUnits(_ args: Arguments) throws -> [TerminalInputUnit] {
        var units: [TerminalInputUnit] = []
        if let path = args.optional("paste-file") { units.append(.paste(try TextFile.read(path, flag: "paste-file"))) }
        if let text = args.optional("text") { units.append(.text(text)) }
        for name in args.all("key") { units.append(try parseKey(name)) }
        guard !units.isEmpty else { throw ProbeError("terminal-type needs --text, --key or --paste-file") }
        return units
    }

    /// `name` or `mod+name`, like `ctrl+c` or `shift+tab`.
    static func parseKey(_ text: String) throws -> TerminalInputUnit {
        let words = text.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let last = words.last, !last.isEmpty else { throw ProbeError("empty key name") }
        let key = TerminalKey(wire: last)
        if case .other = key { throw ProbeError("unknown key name: \(Log.short(last))") }
        var mods: [TerminalModifier] = []
        for word in words.dropLast() {
            let mod = TerminalModifier(wire: word)
            if case .other = mod { throw ProbeError("unknown modifier name: \(Log.short(word))") }
            mods.append(mod)
        }
        return .key(key, mods: mods)
    }
}

/// Follows `client.terminalPushes` of one view: assembles the frames, applies them, logs them and asks for a snapshot
/// when the assembler finds a gap.
actor ViewWatcher {
    private let client: LinkClient
    private let terminalId: String
    private var assembler = TerminalFrameAssembler()
    private var screen = TerminalScreen()
    private var openedAt: ContinuousClock.Instant?
    private var snapshots = 0
    private var snapshotWaiters: [CheckedContinuation<Void, Never>] = []
    private let echo = EchoWaiters()

    init(client: LinkClient, terminalId: String) {
        self.client = client
        self.terminalId = terminalId
    }

    nonisolated func nextFrameWaiter() -> EchoWaiter { echo.make() }

    /// Sends `terminal.view.open` and logs its answer.
    func open(cols: Int, rows: Int) async throws -> TerminalViewOpenOutcome {
        openedAt = .now
        let outcome = try await client.openTerminalView(terminalId: terminalId, cols: cols, rows: rows)
        Log.line("terminal.view.open \(Log.shown(terminalId)) \(cols)x\(rows) outcome=\(Log.shown(outcome.wire))")
        return outcome
    }

    /// Reads the pushes until the session ends.
    func consume() async {
        for await push in client.terminalPushes { await handle(push) }
    }

    func waitForFirstSnapshot(timeout: Duration) async -> Bool {
        if snapshots > 0 { return true }
        let deadline = ContinuousClock.now + timeout
        while snapshots == 0, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        return snapshots > 0
    }

    func printScreen(_ when: String) {
        guard screen.cols > 0 else { return Log.line("no screen \(when)") }
        Log.line("screen \(when) (\(screen.cols)x\(screen.rows), history \(screen.historyRows.count) rows)")
        for row in screen.screenText() { print("    \(Log.shown(row))") }
    }

    private func handle(_ push: TerminalViewPush) async {
        switch push {
        case let .opened(id) where id == terminalId:
            assembler = TerminalFrameAssembler()
            screen = TerminalScreen()
        case let .frame(id, part) where id == terminalId:
            let result = assembler.receive(part)
            if let frame = result.frame {
                screen.apply(frame)
                let head = frame.head
                Log.line(
                    "frame r=\(assembler.revision) \(Log.shown(head.kind.wire)) \(head.cols)x\(head.rows) alt=\(head.alt)"
                        + " history=\(head.history) scroll=\(head.scroll) parts=\(part.parts)")
                echo.frameArrived()
                if head.kind == .snapshot {
                    snapshots += 1
                    if snapshots == 1, let openedAt {
                        Log.line("first snapshot \(Stats.format(Stats.ms(ContinuousClock.now - openedAt))) ms after the open")
                    }
                    printScreen("after the snapshot")
                }
            }
            if result.resync {
                Log.line("gap: asked for a snapshot")
                try? await client.resyncTerminalView(terminalId: terminalId)
            }
        case let .ended(id, reason) where id == terminalId:
            Log.line("terminal.view.ended reason=\(Log.shown(reason.wire))")
        default:
            break
        }
    }
}

/// Hands the time of the next applied frame to whoever asked for it before it came.
final class EchoWaiters: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [EchoWaiter] = []

    func make() -> EchoWaiter {
        let waiter = EchoWaiter()
        lock.withLock { waiters.append(waiter) }
        return waiter
    }

    func frameArrived() {
        let pending = lock.withLock { () -> [EchoWaiter] in
            defer { waiters = [] }
            return waiters
        }
        for waiter in pending { waiter.fulfil(.now) }
    }
}

final class EchoWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var arrival: ContinuousClock.Instant?

    func fulfil(_ instant: ContinuousClock.Instant) {
        lock.withLock { if arrival == nil { arrival = instant } }
    }

    /// The arrival time, or nil after `timeout`.
    func value(timeout: Duration) async -> ContinuousClock.Instant? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let at = lock.withLock({ arrival }) { return at }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return lock.withLock { arrival }
    }
}
