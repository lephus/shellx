import CMUXMobileCore
import CmuxSettings
import CmuxTerminal
import Foundation
import os
import ShellXLinkCore
import ShellXLinkSession

/// One phone's view of one Mac terminal (PROTOCOL.md section 11): captures the terminal's render grid on demand, diffs it
/// against what the phone last got, and applies the phone's input through the Mac's own input paths.
///
/// The view is pull-based. The render observer only says "this surface may have changed"; the pump's `nextFrame()` call
/// waits for a change, passes cmux's frame pacer, captures the surface itself and diffs against the view's own baseline,
/// so a slow phone makes the view merge changes and nothing is queued. Logs carry fixed codes only.
@MainActor
final class ShellXLinkTerminalView: TerminalView, MobileTerminalFrameSink {
    /// What the view does with its terminal; the live one resolves the surface id on every call.
    struct Terminal {
        var surface: @MainActor () -> TerminalSurface?
        var type: @MainActor (_ text: String) -> Void
        var press: @MainActor (_ keyName: String) -> Bool
        var paste: @MainActor (_ text: String) -> Void
        var scroll: @MainActor (_ lines: Int, _ column: Int, _ row: Int) -> Void
    }

    /// The phone's part in the terminal's shared sizing.
    struct Sizing {
        var attach: @MainActor (_ cols: Int, _ rows: Int) -> (columns: Int, rows: Int)?
        var resize: @MainActor (_ cols: Int, _ rows: Int) -> Void
        var input: @MainActor (_ apply: () -> Void) -> Void
        var detach: @MainActor () -> Void
    }

    static let firstSnapshotFence: Duration = .milliseconds(500)

    private enum Wake {
        case changed, snapshotRequested, deadline, ended
    }

    private struct Waiter {
        let id: UInt64
        let continuation: CheckedContinuation<Wake, Never>
        let deadlineTask: Task<Void, Never>?
    }

    private enum Capture {
        case frame(TerminalGridFrame)
        case unchanged
        case notYet
        case gone
    }

    private static let log = Logger(subsystem: "pro.shellx.desktop", category: "link-terminal")

    let surfaceID: UUID
    private let terminal: Terminal
    private let sizing: Sizing
    private let frameSinks: any MobileTerminalFrameSinkRegistry
    private let isBlocked: @MainActor () -> Bool
    private let notificationCenter: NotificationCenter
    private let onClose: @MainActor (ShellXLinkTerminalView) -> Void

    private var needsSnapshot = true
    private var baseline: MobileTerminalRenderGridEmissionState?
    private var generation: UInt64?
    private var converter = ShellXLinkGridConverter(theme: .monokai)
    private var alternate = false
    private var lastCursor = TerminalCursor(x: 0, y: 0)
    private var inputSequence: UInt64?
    private var expectedGrid: (columns: Int, rows: Int)?
    private var fenceUntil: ContinuousClock.Instant?
    private var fencePassed = false
    private var heldUntil: ContinuousClock.Instant?
    private var pacing = ShellXLinkFramePacing()
    private var endReason: TerminalViewEndReason?
    private var closed = false
    private var pendingChange = false
    private var waiter: Waiter?
    private var nextWaitID: UInt64 = 0
    private var captureRevision: UInt64 = 0
    private var policyObserver: NSObjectProtocol?
    private(set) var wakeCountForTesting = 0
    private(set) var deepCaptureCountForTesting = 0

    init(
        surfaceID: UUID, terminal: Terminal, sizing: Sizing, frameSinks: any MobileTerminalFrameSinkRegistry,
        isBlocked: @escaping @MainActor () -> Bool, notificationCenter: NotificationCenter = .default,
        onClose: @escaping @MainActor (ShellXLinkTerminalView) -> Void = { _ in }
    ) {
        self.surfaceID = surfaceID
        self.terminal = terminal
        self.sizing = sizing
        self.frameSinks = frameSinks
        self.isBlocked = isBlocked
        self.notificationCenter = notificationCenter
        self.onClose = onClose
    }

    deinit {
        if let policyObserver {
            notificationCenter.removeObserver(policyObserver)
        }
    }

    /// Joins the sizing (keeps attach's answer for the first-snapshot fence), registers as a frame sink, and watches
    /// `ManagedDevicePolicy.didChangeNotification` on `notificationCenter`.
    func open(cols: Int, rows: Int) {
        expectedGrid = sizing.attach(cols, rows)
        frameSinks.addFrameSink(self)
        policyObserver = notificationCenter.addObserver(
            forName: ManagedDevicePolicy.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.devicePolicyChanged()
            }
        }
    }

    /// Ends the view without the phone asking: `nextFrame()` returns `.ended(reason)` from now on (first reason wins).
    func end(_ reason: TerminalViewEndReason) {
        if endReason == nil {
            endReason = reason
        }
        resumeWaiter(.ended)
    }

    private func devicePolicyChanged() {
        if isBlocked() {
            end(.refused)
        }
    }

    // MARK: - Frame sink

    var frameSinkSurfaceID: UUID { surfaceID }

    func terminalSurfaceMayHaveChanged() {
        if waiter != nil {
            resumeWaiter(.changed)
        } else {
            pendingChange = true
        }
    }

    // MARK: - TerminalView

    func nextFrame() async -> TerminalViewEvent {
        while true {
            if closed || Task.isCancelled { return .ended(.failed) }
            if let reason = endReason { return .ended(reason) }
            if isBlocked() {
                end(.refused)
                continue
            }
            if needsSnapshot {
                switch captureSnapshot(now: ContinuousClock.now) {
                case .frame(let frame): return .frame(frame)
                case .gone:
                    end(.gone)
                    continue
                case .unchanged, .notYet: break
                }
            }
            switch await waitForWake(until: earliest(heldUntil, fenceUntil)) {
            case .ended, .snapshotRequested:
                continue
            case .deadline:
                if let fence = fenceUntil, ContinuousClock.now >= fence {
                    fenceUntil = nil
                    fencePassed = true
                    continue
                }
                // A hold is one-shot: clear it before asking the pacer, or a passed deadline would wake us forever.
                heldUntil = nil
                guard pacing.holdEnded(now: ContinuousClock.now) else { continue }
            case .changed:
                if needsSnapshot { continue }
                switch pacing.changeArrived(now: ContinuousClock.now, inputSequence: inputSequence) {
                case .capture:
                    heldUntil = nil
                case .hold(let until):
                    heldUntil = until
                    continue
                }
            }
            switch captureUpdate() {
            case .frame(let frame): return .frame(frame)
            case .gone: end(.gone)
            case .unchanged, .notYet: continue
            }
        }
    }

    func requestSnapshot() async {
        needsSnapshot = true
        resumeWaiter(.snapshotRequested)
    }

    /// Applies the phone's units in order through the Mac's own input paths, as the phone's activity for sizing.
    /// A unit, key or modifier the Mac does not know is skipped.
    func input(_ units: [TerminalInputUnit]) async {
        if closed || endReason != nil { return }
        if isBlocked() {
            end(.refused)
            return
        }
        var applied = false
        sizing.input { [self] in
            for unit in units {
                if apply(unit) { applied = true }
            }
        }
        if applied {
            // The next change is then the echo of this input, which the pacer never holds.
            inputSequence = (inputSequence ?? 0) &+ 1
        }
    }

    func resize(cols: Int, rows: Int) async {
        if closed || endReason != nil { return }
        sizing.resize(cols, rows)
    }

    private func apply(_ unit: TerminalInputUnit) -> Bool {
        switch unit {
        case .text(let text):
            terminal.type(text)
            return true
        case .key(let key, let mods):
            guard let chord = ShellXLinkKeyChord(key: key, mods: mods) else { return false }
            return terminal.press(chord.macKeyName)
        case .paste(let text):
            terminal.paste(text)
            return true
        case .scroll(let lines):
            // The wheel acts only on the alternate screen; the main screen's history is the phone's own. A positive
            // count means toward older content, like Ghostty's positive wheel delta.
            guard alternate else { return false }
            terminal.scroll(lines, lastCursor.x, lastCursor.y)
            return true
        case .other:
            return false
        }
    }

    func close() async {
        guard !closed else { return }
        closed = true
        resumeWaiter(.ended)
        frameSinks.removeFrameSink(self)
        if let policyObserver {
            notificationCenter.removeObserver(policyObserver)
            self.policyObserver = nil
        }
        sizing.detach()
        onClose(self)
    }

    // MARK: - Waiting

    private func earliest(_ a: ContinuousClock.Instant?, _ b: ContinuousClock.Instant?) -> ContinuousClock.Instant? {
        switch (a, b) {
        case let (a?, b?): return min(a, b)
        case let (a?, nil): return a
        case let (nil, b?): return b
        case (nil, nil): return nil
        }
    }

    private func waitForWake(until deadline: ContinuousClock.Instant?) async -> Wake {
        if closed || endReason != nil || Task.isCancelled { return .ended }
        if pendingChange {
            pendingChange = false
            return .changed
        }
        nextWaitID &+= 1
        wakeCountForTesting += 1
        let id = nextWaitID
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Wake, Never>) in
                var deadlineTask: Task<Void, Never>?
                if let deadline {
                    deadlineTask = Task { [weak self] in
                        try? await Task.sleep(until: deadline, clock: .continuous)
                        guard !Task.isCancelled else { return }
                        self?.resumeWaiter(.deadline, id: id)
                    }
                }
                waiter = Waiter(id: id, continuation: continuation, deadlineTask: deadlineTask)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resumeWaiter(.ended, id: id)
            }
        }
    }

    private func resumeWaiter(_ wake: Wake, id: UInt64? = nil) {
        guard let current = waiter, id == nil || current.id == id else { return }
        waiter = nil
        current.deadlineTask?.cancel()
        current.continuation.resume(returning: wake)
    }

    // MARK: - Capturing

    private func capture(_ surface: TerminalSurface, history: Int) -> MobileTerminalRenderGridFrame? {
        captureRevision &+= 1
        let tee = MobileTerminalByteTee.shared
        return surface.mobileRenderGridFrame(
            stateSeq: tee.currentSequence(surfaceID: surfaceID) ?? 0,
            renderEpoch: tee.currentRenderCaptureIdentity(surfaceID: surfaceID).epoch,
            renderRevision: captureRevision,
            full: true,
            scrollbackLines: history,
            includeTheme: true,
            anchor: .screen
        )?.frame
    }

    private func captureSnapshot(now: ContinuousClock.Instant) -> Capture {
        guard let surface = terminal.surface() else { return .gone }
        if !fencePassed, let expected = expectedGrid {
            // While the grid the sizing decided has not arrived, probe cheaply; the deep capture waits for it.
            guard let probe = capture(surface, history: 0) else { return .notYet }
            if (probe.columns, probe.rows) != expected {
                fenceUntil = fenceUntil ?? now + Self.firstSnapshotFence
                if let fence = fenceUntil, now < fence { return .notYet }
            }
        }
        deepCaptureCountForTesting += 1
        guard let grid = capture(surface, history: ShellXLink.terminalHistoryRowBudget) else { return .notYet }
        fencePassed = true
        fenceUntil = nil
        expectedGrid = nil
        baseline = grid.emissionState
        generation = surface.runtimeSurfaceGeneration
        needsSnapshot = false
        heldUntil = nil
        converter = ShellXLinkGridConverter(theme: grid.terminalTheme ?? TerminalTheme.currentMacTerminalThemeSnapshot())
        remember(grid)
        pacing.noteSnapshot(now: now, inputSequence: inputSequence)
        return .frame(converter.snapshot(grid))
    }

    private func captureUpdate() -> Capture {
        guard let surface = terminal.surface() else { return .gone }
        if surface.runtimeSurfaceGeneration != generation {
            needsSnapshot = true
            return .unchanged
        }
        guard let grid = capture(surface, history: 0) else { return .notYet }
        do {
            var emission = try grid.renderGridEmission(
                comparedTo: baseline, fullScrollbackTarget: ShellXLink.terminalHistoryRowBudget, allowScrollbackRequest: true
            )
            if case .needsScrollback(let rows) = emission {
                guard let deeper = capture(surface, history: rows) else { return .notYet }
                emission = try deeper.renderGridEmission(
                    comparedTo: baseline, fullScrollbackTarget: ShellXLink.terminalHistoryRowBudget,
                    allowScrollbackRequest: false
                )
            }
            switch emission {
            case .none, .needsScrollback:
                return .unchanged
            case .emit(let frame, let state):
                baseline = state
                remember(frame)
                if frame.full {
                    converter = ShellXLinkGridConverter(
                        theme: frame.terminalTheme ?? TerminalTheme.currentMacTerminalThemeSnapshot()
                    )
                    return .frame(converter.snapshot(frame))
                }
                return .frame(converter.delta(frame))
            }
        } catch let error as MobileTerminalRenderGridError {
            Self.log.error("render grid diff failed: \(Self.code(of: error), privacy: .public)")
            needsSnapshot = true
            return .unchanged
        } catch {
            Self.log.error("render grid diff failed: other")
            needsSnapshot = true
            return .unchanged
        }
    }

    private func remember(_ frame: MobileTerminalRenderGridFrame) {
        alternate = frame.activeScreen == .alternate
        if let cursor = frame.cursor {
            lastCursor = TerminalCursor(x: cursor.column, y: cursor.row)
        }
    }

    private static func code(of error: MobileTerminalRenderGridError) -> String {
        switch error {
        case .invalidFormat: return "invalidFormat"
        case .invalidDimensions: return "invalidDimensions"
        case .invalidRow: return "invalidRow"
        case .invalidColumn: return "invalidColumn"
        case .invalidCursor: return "invalidCursor"
        case .invalidStyleID: return "invalidStyleID"
        case .invalidSpanWidth: return "invalidSpanWidth"
        }
    }
}
