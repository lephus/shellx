import Foundation
import Observation
import ShellXLinkCore
import ShellXLinkSession

public enum TerminalUnavailableReason: Equatable, Sendable { case gone, refused, failed }

public enum TerminalViewPhase: Equatable, Sendable {
    /// Opening the view, or waiting for its first screen.
    case connecting
    case live
    /// The Mac is not online: the last screen (if any) stays, dimmed.
    case offline
    /// The Mac is online but its ShellX shows no terminals (no `terminal_view`).
    case unsupported
    case unavailable(TerminalUnavailableReason)
}

/// One workspace screen's terminal: the one terminal it shows, opened on the Mac at the phone's size (rules R1-R12).
///
/// The model holds the terminal shown (`terminalId`), the phone grid (nil until the surface reports one), `active` (its
/// newest `run()` is running and it is not suspended), and at most one **view**: the terminal it asked the Mac to show,
/// an attempt number, whether the open was answered `ok`, whether its `.opened` push arrived, and the size last sent for
/// it. Every message to the Mac goes through one FIFO outbox drained by one task (started by the first `run()`, finished
/// by `deinit`); the task awaits each call, and an open's answer is handled before the next message goes.
///
/// - **R1 Want.** The model wants a view while `active`, `terminalId != nil`, a grid is known,
///   `link.isOnline(machineID)`, `link.supportsTerminalView(machineID)`, the phase is not `.unavailable`, and it is not
///   waiting for the Mac after a `.notSent` (R3). `reconcile()` (after every change below) first queues `close` for a
///   view that is no longer wanted or is for another terminal and forgets it; then, when wanted and there is no view,
///   queues `open(terminalId, cols, rows)` with the next attempt number and sets `.connecting`. While `active`, when the
///   Mac is the reason nothing can be wanted: online without `terminal_view` → `.unsupported`; not online → `.offline`. A
///   model that is not `active` never changes its phase in `reconcile()`.
/// - **R2 show(id).** A different id: a fresh `TerminalScreen(maxHistoryRows:)`, assembler and `TerminalTyping`;
///   `snapshots = 0`, `topShift = 0`, `screenRevision += 1`; retry budgets restored; `.connecting`; the first-screen
///   clock starts (when `id` is not nil); reconcile. The same id does nothing. The clock starts here, at the user's swipe
///   or tap, not at the `ok`: the Mac may hold the first snapshot up to 500 ms for the phone's size (contracts §17) and
///   that wait is part of criterion 3. It never runs while the Mac is offline or unsupported, or the app is in the
///   background (R1, R8, `suspend()`): the open that follows starts it again. The phase stays `.connecting` (the
///   pane's loading state) after the `ok` until a snapshot is applied.
/// - **R3 Open answers**, for the current attempt only (any other is ignored): `ok` → answered. `busy` → forget the view;
///   after 300 ms reconcile; after 5 such retries `.unavailable(.failed)`. `not_found` → forget, `.unavailable(.gone)`.
///   `refused` → forget, `.unavailable(.refused)`. `failed` (also the answer for a terminal the Mac lists but cannot
///   view, contracts §17), an unknown outcome, or `.noAnswer` while `link.isOnline` → forget; the first time, reconcile
///   after 1 s (`.connecting` meanwhile); the second time `.unavailable(.failed)`. `.notSent`, or `.noAnswer` while not
///   online → forget, and open again only after the next `.state` event of this Mac or a `show`, `retry` or `resume`
///   (so a hub that still calls the Mac online during a reconnect cannot make the model ask in a loop); while `active`,
///   R1 then sets `.offline` or `.unsupported`.
/// - **R4 `.opened(id)`** for the view's terminal on this Mac: a fresh `TerminalFrameAssembler`; frames count from now
///   on. Frames of that terminal before it are ignored. Every push for another terminal or another Mac is ignored.
/// - **R5 Frames.** `assembler.receive(part)`; `resync` → queue `resync(id)`; a complete frame → R7.
/// - **R6 `.ended(id, reason)`** of the view (after its `.opened`): `gone` → `.unavailable(.gone)`; `refused` →
///   `.unavailable(.refused)`; `not_open` → forget the view and reconcile at once (a new open), on the failed-open budget:
///   a second `not_open` (or failure) before a snapshot restores it gives `.unavailable(.failed)`; `failed` or unknown →
///   as a failed open (R3). Before `.opened` it is ignored.
/// - **R7 Apply.** `screen.apply(frame)`, `screenRevision += 1`. A snapshot: `snapshots += 1`, `topShift = 0`, phase
///   `.live`, the first-screen latency recorded (once per start of the clock; a reopen after R6, R8 or `resume` starts it
///   again when it is not running), both retry budgets restored. A history frame: `topShift += after − before`. A delta
///   on the main screen: `topShift −= max(0, before + min(scroll, rows) + min(history, max(0, scroll − rows)) − after)`
///   (`before`/`after`: history row counts around the apply; `scroll`, `rows`, `history` from the head). Every apply
///   records `terminalFrameApply` (assemble plus apply); the first apply after an echo start records `terminalKeyEcho`.
/// - **R8 Mac state** `.state(machineID, s)`: not `.online` → forget the view without a close (its session is gone),
///   restore both retry budgets (an open lost with the session, answered `.noAnswer` before the hub saw the drop, is no
///   failure of the Mac's) and, unless the phase is `.unavailable` or `.unsupported`, set `.offline`; the screen stays.
///   `.online` → reconcile (a new open).
/// - **R9 run().** Subscribes to `link.terminalEvents()`, sets running, reconciles, handles events until cancelled, then
///   clears running and reconciles (the close is queued and still goes out). A `run()` that starts while an older one is
///   still finishing (SwiftUI restarts `.task`) takes over: only the newest handles events and owns running; an older one
///   returns without touching state. `suspend()` / `resume()` (app background / foreground) clear / set suspended and
///   reconcile. `retry()` clears `.unavailable` and the budgets, sets `.connecting`, reconciles.
/// - **R10 Typing** (`insertText`, `setMarkedText`, `unmarkText`, `deleteBackward`, `press`, `toggleCtrl`):
///   `TerminalTyping` turns the call into units; with a view, each message of `TerminalInputBatcher.messages(units)` is
///   queued as `input(id, units)` (after any queued open) and raises `sentInputs` by one; without a view they are
///   dropped. A message holding a `text` or `key` unit starts the echo clock if it is not running; the clock is dropped
///   after 2 s without a frame.
/// - **R11 Grid** `setPhoneGrid(cols:rows:)`: values below 1 are ignored; the grid is stored and the model reconciles
///   (the first grid may open). With a view, a grid different from the size last sent is queued as `resize` 200 ms after
///   the last change (a newer change restarts the wait); an open carries the grid of its moment.
/// - **R12 Paste and scroll.** `paste(text)`: when `TerminalInputBatcher.pasteFits(text)` is false nothing is sent and
///   the model raises the `pasteTooLarge` notice (string `terminal.paste.tooLarge`); otherwise
///   `TerminalInputBatcher.pasteUnits(text)` → messages, with a view. `scroll(lines:)` only with a view and `screen.alt`:
///   summed for 50 ms, then `TerminalInputBatcher.scrollUnits(total)` as one message.
///
/// ---
///
/// R3, a timed-out open: `.noAnswer` while `link.isOnline` means the Mac may have opened the view although its answer
/// never came, so `close` for that view is queued (through the same outbox, before the view is forgotten), then the
/// failed-open handling above follows (reconcile after 1 s the first time, `.unavailable(.failed)` the second).
/// `.noAnswer` while not online sends no close: the session is gone, as in R8.
///
/// R1 and R8 agree on one point: a Mac that went away while the phase was `.unsupported` stays `.unsupported` (its
/// last known ShellX shows no terminals) until it comes back with `terminal_view`.
@MainActor @Observable
public final class TerminalViewModel {
    public static let resizeDelay: Duration = .milliseconds(200)
    public static let busyRetryDelay: Duration = .milliseconds(300)
    public static let busyRetries = 5
    public static let failedRetryDelay: Duration = .seconds(1)
    public static let scrollCoalescing: Duration = .milliseconds(50)
    public static let echoTimeout: Duration = .seconds(2)

    public let machineID: String
    /// The terminal the page shown is; nil while it is none (an agent's chat).
    public private(set) var terminalId: String?
    public private(set) var phase: TerminalViewPhase = .connecting
    public private(set) var screen: TerminalScreen
    /// Raised by one whenever `screen` changes.
    public private(set) var screenRevision = 0
    /// Snapshots applied since the terminal was shown (0: no screen yet).
    public private(set) var snapshots = 0
    /// Rows added above the oldest history row, minus rows dropped from the top, since the last snapshot (R7): the surface
    /// keeps a scrolled-up view in place by it.
    public private(set) var topShift = 0
    public private(set) var typing = TerminalTyping()
    /// Raised by one for every input message queued (typing, keys, paste, scroll): the surface goes back to the bottom.
    public private(set) var sentInputs = 0
    /// Raised by one each time a paste is refused for its size (R12: `TerminalInputBatcher.pasteFits` is false); nothing
    /// is sent, and the pane shows `terminal.paste.tooLarge`.
    public private(set) var pasteTooLarge = 0

    /// Whether what is typed goes anywhere, so the page keeps or takes the keyboard and shows the key bar: `.live`, or
    /// `.connecting` after a screen came while a view is opening (input queues behind the open, R10: a resume, a
    /// reconnect, a `not_open` reopen). Not in the wait before a busy or failed open is retried, nor while waiting for
    /// the Mac after a `.notSent` (no view to type into), offline, unsupported, unavailable, or before the first screen
    /// (the loading card covers the surface). The background keeps the phase, and so the keyboard, as it was.
    public var acceptsInput: Bool {
        switch phase {
        case .live: true
        case .connecting: snapshots > 0 && retryWait == nil && !waitingForMac
        case .offline, .unsupported, .unavailable: false
        }
    }

    private struct GridSize: Equatable {
        var cols: Int
        var rows: Int
    }

    /// The terminal asked of the Mac (R1).
    private struct View {
        let terminalId: String
        let attempt: Int
        /// The size the open carried, then the size of the last resize sent.
        var size: GridSize
        /// The outbox handed the open to the link: its `.opened` may come before the answer.
        var sent = false
        var answered = false
        var opened = false
    }

    private let link: any TerminalLink
    private let maxHistoryRows: Int
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> ContinuousClock.Instant
    private let outbox: TerminalOutbox

    @ObservationIgnored private var assembler = TerminalFrameAssembler()
    @ObservationIgnored private var grid: GridSize?
    @ObservationIgnored private var view: View?
    @ObservationIgnored private var attempts = 0
    /// Raised by every `run()`: only the newest handles events and owns `running` (R9).
    @ObservationIgnored private var runGeneration = 0
    @ObservationIgnored private var running = false
    @ObservationIgnored private var suspended = false
    /// After a `.notSent` (or `.noAnswer` while not online): no open until this Mac's next `.state`, `show`, `retry` or
    /// `resume` (R3). Observed: `acceptsInput` reads it.
    private var waitingForMac = false
    @ObservationIgnored private var busyRetriesUsed = 0
    @ObservationIgnored private var failedRetriesUsed = 0
    /// A busy or failed open waiting out its delay: no open meanwhile. Observed: `acceptsInput` reads it.
    private var retryWait: Task<Void, Never>?
    @ObservationIgnored private var retryToken = 0
    /// The first-screen clock (R2, R7): running from a show or a reopen until a snapshot is applied.
    @ObservationIgnored private var firstScreenStart: ContinuousClock.Instant?
    /// The resize waiting out `resizeDelay` after the last grid change (R11).
    @ObservationIgnored private var resizeWait: Task<Void, Never>?
    @ObservationIgnored private var resizeToken = 0
    /// Alternate-screen scrolling summed until `scrollCoalescing` has passed (R12).
    @ObservationIgnored private var scrollSum = 0
    @ObservationIgnored private var scrollWait: Task<Void, Never>?
    @ObservationIgnored private var scrollToken = 0
    /// The echo clock (R10): from the first message of typed text or a key to the next frame applied, at most
    /// `echoTimeout`.
    @ObservationIgnored private var echoStart: ContinuousClock.Instant?
    @ObservationIgnored private var echoWait: Task<Void, Never>?
    @ObservationIgnored private var echoToken = 0

    /// `sleep` waits out every delay (tests pass a `ManualSleeper`); `now` times the latencies.
    public init(
        machineID: String, link: any TerminalLink, maxHistoryRows: Int = TerminalScreen.defaultMaxHistoryRows,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.machineID = machineID
        self.link = link
        self.maxHistoryRows = maxHistoryRows
        self.sleep = sleep
        self.now = now
        screen = TerminalScreen(maxHistoryRows: maxHistoryRows)
        outbox = TerminalOutbox(link: link, machineID: machineID)
        outbox.owner = self
    }

    deinit {
        outbox.input.finish()
    }

    /// A model that shows `screen` in `phase` and sends nothing (render tests, previews). Never call `run()` on it.
    /// `snapshots` is 1 when `screen` has a size, else 0.
    public static func fixed(
        terminalId: String, screen: TerminalScreen = TerminalScreen(), phase: TerminalViewPhase = .live,
        typing: TerminalTyping = TerminalTyping()
    ) -> TerminalViewModel {
        let model = TerminalViewModel(machineID: "", link: SilentTerminalLink(), sleep: { _ in })
        model.terminalId = terminalId
        model.screen = screen
        model.phase = phase
        model.typing = typing
        model.snapshots = screen.cols > 0 ? 1 : 0
        return model
    }

    // MARK: - Lifecycle (R2, R9, R11)

    /// R9: handles this Mac's terminal events until cancelled; the close queued at the end still goes out.
    public func run() async {
        outbox.start()
        runGeneration += 1
        let generation = runGeneration
        running = true
        let events = link.terminalEvents()
        reconcile()
        for await event in events {
            guard generation == runGeneration else { break }
            handle(event)
        }
        // SwiftUI restarts a page's `.task` by cancelling the old one and starting a new one at once: let the new run
        // take over before this one gives the view up.
        await Task.yield()
        guard generation == runGeneration else { return }
        running = false
        reconcile()
    }

    /// R2.
    public func show(_ terminalId: String?) {
        guard terminalId != self.terminalId else { return }
        self.terminalId = terminalId
        screen = TerminalScreen(maxHistoryRows: maxHistoryRows)
        assembler = TerminalFrameAssembler()
        typing = TerminalTyping()
        snapshots = 0
        topShift = 0
        screenRevision += 1
        restoreBudgets()
        dropEcho()
        waitingForMac = false
        phase = .connecting
        firstScreenStart = terminalId == nil ? nil : now()
        reconcile()
    }

    /// R11: the size that fits the pane. Values below 1 are ignored.
    public func setPhoneGrid(cols: Int, rows: Int) {
        guard cols >= 1, rows >= 1 else { return }
        let grid = GridSize(cols: cols, rows: rows)
        self.grid = grid
        reconcile()
        guard let view, grid != view.size else {
            cancelResize()
            return
        }
        scheduleResize()
    }

    /// The app went to the background: the view closes, the screen stays. The first-screen clock stops; the open on
    /// return starts it again.
    public func suspend() {
        suspended = true
        firstScreenStart = nil
        reconcile()
    }

    public func resume() {
        suspended = false
        waitingForMac = false
        reconcile()
    }

    /// Try Again. Nothing to do while a view is open.
    public func retry() {
        guard view == nil else { return }
        restoreBudgets()
        waitingForMac = false
        phase = .connecting
        reconcile()
    }

    // MARK: - R1

    private var active: Bool { running && !suspended }

    private var isUnavailable: Bool {
        if case .unavailable = phase { return true }
        return false
    }

    private func reconcile() {
        let online = link.isOnline(machineID)
        let supported = link.supportsTerminalView(machineID)
        let wanted = active && terminalId != nil && grid != nil && online && supported && !isUnavailable && !waitingForMac
        if let view, !wanted || view.terminalId != terminalId {
            outbox.send(.close(view.terminalId))
            forgetView()
        }
        if wanted {
            guard view == nil, retryWait == nil, let terminalId, let grid else { return }
            attempts += 1
            view = View(terminalId: terminalId, attempt: attempts, size: grid)
            outbox.send(.open(terminalId, cols: grid.cols, rows: grid.rows, attempt: attempts))
            if firstScreenStart == nil { firstScreenStart = now() }
            phase = .connecting
            return
        }
        guard active, !isUnavailable, !(online && supported) else { return }
        // No open while the Mac is the reason: the first-screen clock starts again at the open that brings it.
        firstScreenStart = nil
        if !online {
            if phase != .unsupported { phase = .offline }
        } else {
            phase = .unsupported
        }
    }

    /// The view's waits go with it: a resize or scroll for it never reaches the next view.
    private func forgetView() {
        view = nil
        cancelResize()
        scrollWait?.cancel()
        scrollWait = nil
        scrollToken += 1
        scrollSum = 0
        dropEcho()
    }

    private func restoreBudgets() {
        busyRetriesUsed = 0
        failedRetriesUsed = 0
        retryWait?.cancel()
        retryWait = nil
        retryToken += 1
    }

    private func becomeUnavailable(_ reason: TerminalUnavailableReason) {
        forgetView()
        phase = .unavailable(reason)
        firstScreenStart = nil
    }

    /// Reconciles after `delay`; no open goes out meanwhile.
    private func retry(after delay: Duration) {
        retryWait?.cancel()
        retryToken += 1
        let token = retryToken
        let sleep = sleep
        retryWait = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard let self, self.retryToken == token else { return }
            self.retryWait = nil
            self.reconcile()
        }
    }

    // MARK: - R10-R12

    /// R10: `units` as input messages to the view, after any queued open; dropped without a view.
    private func send(_ units: [TerminalInputUnit]) {
        guard let view, !units.isEmpty else { return }
        for message in TerminalInputBatcher.messages(units) {
            outbox.send(.input(view.terminalId, message))
            sentInputs += 1
            if echoStart == nil, message.contains(where: Self.isTyped) { startEcho() }
        }
    }

    private static func isTyped(_ unit: TerminalInputUnit) -> Bool {
        switch unit {
        case .text, .key: true
        default: false
        }
    }

    private func flushScroll(_ token: Int) {
        guard token == scrollToken else { return }
        scrollWait = nil
        let total = scrollSum
        scrollSum = 0
        send(TerminalInputBatcher.scrollUnits(total))
    }

    private func startEcho() {
        echoStart = now()
        echoToken += 1
        let token = echoToken
        let sleep = sleep
        echoWait?.cancel()
        echoWait = Task { [weak self] in
            do { try await sleep(TerminalViewModel.echoTimeout) } catch { return }
            guard let self, self.echoToken == token else { return }
            self.echoStart = nil
            self.echoWait = nil
        }
    }

    private func dropEcho() {
        echoStart = nil
        echoToken += 1
        echoWait?.cancel()
        echoWait = nil
    }

    /// R11: the grid goes out `resizeDelay` after its last change, unless it is the size last sent.
    private func scheduleResize() {
        resizeWait?.cancel()
        resizeToken += 1
        let token = resizeToken
        let sleep = sleep
        resizeWait = Task { [weak self] in
            do { try await sleep(TerminalViewModel.resizeDelay) } catch { return }
            guard let self, self.resizeToken == token else { return }
            self.resizeWait = nil
            guard let view = self.view, let grid = self.grid, grid != view.size else { return }
            self.outbox.send(.resize(view.terminalId, cols: grid.cols, rows: grid.rows))
            self.view?.size = grid
        }
    }

    private func cancelResize() {
        resizeWait?.cancel()
        resizeWait = nil
        resizeToken += 1
    }

    // MARK: - R3

    fileprivate func openSending(attempt: Int) {
        if view?.attempt == attempt { view?.sent = true }
    }

    fileprivate func openAnswered(_ result: TerminalOpenResult, attempt: Int) {
        guard let current = view, current.attempt == attempt else { return }
        switch result {
        case .outcome(.ok):
            view?.answered = true
        case .outcome(.busy):
            forgetView()
            if busyRetriesUsed >= Self.busyRetries {
                becomeUnavailable(.failed)
            } else {
                busyRetriesUsed += 1
                retry(after: Self.busyRetryDelay)
            }
        case .outcome(.notFound):
            becomeUnavailable(.gone)
        case .outcome(.refused):
            becomeUnavailable(.refused)
        case .outcome(.failed), .outcome(.other):
            failedOpen()
        case .noAnswer where link.isOnline(machineID):
            // The Mac may have opened it although the answer never came.
            outbox.send(.close(current.terminalId))
            failedOpen()
        case .noAnswer, .notSent:
            forgetView()
            waitingForMac = true
            reconcile()
        }
    }

    /// A failed open or a failed view: retried once after 1 s, then Try Again. The wait is `.connecting`: a view that
    /// ended while live must not look live while nothing typed can reach the Mac (the pane takes input only `.live`).
    private func failedOpen() {
        forgetView()
        if failedRetriesUsed >= 1 {
            becomeUnavailable(.failed)
        } else {
            failedRetriesUsed += 1
            phase = .connecting
            retry(after: Self.failedRetryDelay)
        }
    }

    // MARK: - Events (R4-R8)

    private func handle(_ event: TerminalHubEvent) {
        switch event {
        case let .state(machine, state):
            guard machine == machineID else { return }
            macState(state)
        case let .push(machine, push):
            guard machine == machineID else { return }
            switch push {
            case let .opened(id): opened(id)
            case let .frame(id, part): frame(id, part)
            case let .ended(id, reason): ended(id, reason)
            }
        }
    }

    /// R4.
    private func opened(_ id: String) {
        guard let current = view, current.terminalId == id, current.sent else { return }
        view?.opened = true
        assembler = TerminalFrameAssembler()
    }

    /// R5.
    private func frame(_ id: String, _ part: TerminalFramePart) {
        guard let current = view, current.terminalId == id, current.opened else { return }
        let started = now()
        let result = assembler.receive(part)
        if result.resync { outbox.send(.resync(id)) }
        if let frame = result.frame { apply(frame, started: started) }
    }

    /// R6.
    private func ended(_ id: String, _ reason: TerminalViewEndReason) {
        guard let current = view, current.terminalId == id, current.opened else { return }
        switch reason {
        case .gone:
            becomeUnavailable(.gone)
        case .refused:
            becomeUnavailable(.refused)
        case .notOpen:
            // Reopened at once, but on the failed-open budget (a snapshot restores it): a Mac that keeps ending its
            // views before any screen cannot make the phone open them forever.
            forgetView()
            if failedRetriesUsed >= 1 {
                becomeUnavailable(.failed)
            } else {
                failedRetriesUsed += 1
                reconcile()
            }
        case .failed, .other:
            failedOpen()
        }
    }

    /// R7.
    private func apply(_ frame: TerminalGridFrame, started: ContinuousClock.Instant) {
        let head = frame.head
        let before = screen.historyRows.count
        screen.apply(frame)
        let after = screen.historyRows.count
        screenRevision += 1
        switch head.kind {
        case .snapshot:
            snapshots += 1
            topShift = 0
            phase = .live
            if let start = firstScreenStart {
                link.recordLatency(.terminalFirstScreen, now() - start)
                firstScreenStart = nil
            }
            restoreBudgets()
        case .history:
            topShift += after - before
        case .delta where !head.alt:
            let carried = min(head.history, max(0, head.scroll - head.rows))
            topShift -= max(0, before + min(head.scroll, head.rows) + carried - after)
        default:
            break
        }
        link.recordLatency(.terminalFrameApply, now() - started)
        if let start = echoStart {
            link.recordLatency(.terminalKeyEcho, now() - start)
            dropEcho()
        }
    }

    /// R8.
    private func macState(_ state: MachineLinkState) {
        waitingForMac = false
        guard state == .online else {
            forgetView()   // its session is gone: nothing to close
            firstScreenStart = nil   // the open once it is back starts the clock again
            // An open lost with the session was no failure of the Mac's: the next session starts with both retries.
            restoreBudgets()
            switch phase {
            case .unavailable, .unsupported: break
            default: phase = .offline
            }
            return
        }
        reconcile()
    }
}

// MARK: - Typing, paste, scrolling and resizing (R10-R12)

extension TerminalViewModel {
    public func insertText(_ text: String) { send(typing.insert(text)) }

    public func setMarkedText(_ text: String) { send(typing.setMarked(text)) }

    public func unmarkText() { send(typing.unmark()) }

    public func deleteBackward() { send(typing.deleteBackward()) }

    public func press(_ key: TerminalKey, mods: [TerminalModifier] = []) { send(typing.key(key, mods: mods)) }

    public func toggleCtrl() { typing.toggleCtrl() }

    /// R12: refused whole when it does not fit (`pasteTooLarge`; the word being composed stays), else sent in
    /// paste-sized messages after the word being composed, which is committed first as before a key.
    public func paste(_ text: String) {
        guard TerminalInputBatcher.pasteFits(text) else {
            pasteTooLarge += 1
            return
        }
        send(typing.unmark() + TerminalInputBatcher.pasteUnits(text))
    }

    /// R12: alternate-screen scrolling (positive: toward older content), summed for `scrollCoalescing`.
    public func scroll(lines: Int) {
        guard view != nil, screen.alt, lines != 0 else { return }
        scrollSum += lines
        guard scrollWait == nil else { return }
        let token = scrollToken
        let sleep = sleep
        scrollWait = Task { [weak self] in
            do { try await sleep(TerminalViewModel.scrollCoalescing) } catch { return }
            self?.flushScroll(token)
        }
    }
}

/// The one FIFO outbox of a `TerminalViewModel`: one task sends each message in turn and hands an open's answer back
/// before the next message goes. It holds the link, so what was queued still goes out after the model is gone.
@MainActor
private final class TerminalOutbox {
    enum Message: Sendable {
        case open(String, cols: Int, rows: Int, attempt: Int)
        case close(String)
        case input(String, [TerminalInputUnit])
        case resize(String, cols: Int, rows: Int)
        case resync(String)
    }

    nonisolated let input: AsyncStream<Message>.Continuation
    private let messages: AsyncStream<Message>
    private let link: any TerminalLink
    private let machineID: String
    weak var owner: TerminalViewModel?
    private var drain: Task<Void, Never>?

    init(link: any TerminalLink, machineID: String) {
        (messages, input) = AsyncStream.makeStream(of: Message.self)
        self.link = link
        self.machineID = machineID
    }

    func send(_ message: Message) {
        input.yield(message)
    }

    /// Starts the drain once; it ends when the model's `deinit` finishes `input`.
    func start() {
        guard drain == nil else { return }
        drain = Task { [self] in
            for await message in messages { await deliver(message) }
        }
    }

    private func deliver(_ message: Message) async {
        switch message {
        case let .open(id, cols, rows, attempt):
            owner?.openSending(attempt: attempt)
            let result = await link.openTerminalView(machineID: machineID, terminalId: id, cols: cols, rows: rows)
            owner?.openAnswered(result, attempt: attempt)
        case let .close(id):
            await link.closeTerminalView(machineID: machineID, terminalId: id)
        case let .input(id, units):
            await link.sendTerminalInput(machineID: machineID, terminalId: id, units: units)
        case let .resize(id, cols, rows):
            await link.resizeTerminalView(machineID: machineID, terminalId: id, cols: cols, rows: rows)
        case let .resync(id):
            await link.resyncTerminalView(machineID: machineID, terminalId: id)
        }
    }
}

/// The link of a fixed model: never online, supports nothing, sends nothing.
@MainActor
private final class SilentTerminalLink: TerminalLink {
    func terminalEvents() -> AsyncStream<TerminalHubEvent> { AsyncStream { $0.finish() } }
    func isOnline(_ machineID: String) -> Bool { false }
    func supportsTerminalView(_ machineID: String) -> Bool { false }
    func openTerminalView(machineID: String, terminalId: String, cols: Int, rows: Int) async -> TerminalOpenResult { .notSent }
    func closeTerminalView(machineID: String, terminalId: String) async {}
    func sendTerminalInput(machineID: String, terminalId: String, units: [TerminalInputUnit]) async {}
    func resizeTerminalView(machineID: String, terminalId: String, cols: Int, rows: Int) async {}
    func resyncTerminalView(machineID: String, terminalId: String) async {}
    func recordLatency(_ metric: LatencyMetric, _ duration: Duration) {}
}
