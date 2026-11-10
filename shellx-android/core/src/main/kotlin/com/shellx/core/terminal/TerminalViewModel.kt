package com.shellx.core.terminal

import com.shellx.core.diagnostics.LatencyMetric
import com.shellx.core.link.MachineLinkState
import com.shellx.link.core.TerminalFrameAssembler
import com.shellx.link.core.TerminalFrameKind
import com.shellx.link.core.TerminalFramePart
import com.shellx.link.core.TerminalGridFrame
import com.shellx.link.core.TerminalInputUnit
import com.shellx.link.core.TerminalKey
import com.shellx.link.core.TerminalModifier
import com.shellx.link.core.TerminalScreen
import com.shellx.link.core.TerminalViewEndReason
import com.shellx.link.core.TerminalViewOpenOutcome
import com.shellx.link.core.TerminalViewPush
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.ComparableTimeMark
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.yield

enum class TerminalUnavailableReason { GONE, REFUSED, FAILED }

sealed interface TerminalViewPhase {
    /** Opening the view, or waiting for its first screen. */
    data object Connecting : TerminalViewPhase

    data object Live : TerminalViewPhase

    /** The Mac is not online: the last screen (if any) stays, dimmed. */
    data object Offline : TerminalViewPhase

    /** The Mac is online but its ShellX shows no terminals (no `terminal_view`). */
    data object Unsupported : TerminalViewPhase

    data class Unavailable(val reason: TerminalUnavailableReason) : TerminalViewPhase
}

/** What a terminal page shows ([TerminalViewModel.state], A3). */
data class TerminalViewState(
    /** The terminal the page shown is; null while it is none (an agent's chat). */
    val terminalId: String? = null,
    val phase: TerminalViewPhase = TerminalViewPhase.Connecting,
    /** Raised by one whenever [TerminalViewModel.screen] changes. */
    val screenRevision: Long = 0,
    /** Snapshots applied since the terminal was shown (0: no screen yet). */
    val snapshots: Int = 0,
    /** Rows added above the oldest history row, minus rows dropped from the top, since the last snapshot (R7): the
     *  surface keeps a scrolled-up view in place by it. */
    val topShift: Int = 0,
    /** The input method's word in progress, copied out of TerminalTyping after every change. */
    val markedText: String = "",
    val ctrlLatched: Boolean = false,
    /** Raised by one for every input message queued (typing, keys, paste, scroll): the surface goes back to the bottom. */
    val sentInputs: Int = 0,
    /** Raised by one each time a paste is refused for its size (R12, A6). */
    val pasteTooLarge: Int = 0,
    /** [TerminalViewModel.acceptsInput]. */
    val acceptsInput: Boolean = false,
)

/**
 * One workspace screen's terminal: the one terminal it shows, opened on the Mac at the phone's size (TerminalViewModel
 * .swift, plan 2C's rules R1–R12 with plan 3G's A1–A6). Main-confined: every call, and the outbox and delays it runs in
 * [scope], are on the main thread.
 *
 * The model holds the terminal shown (`terminalId`), the phone grid (null until the surface reports one), `active` (its
 * newest `run()` is running), and at most one **view**: the terminal it asked the Mac to show, an attempt number,
 * whether the open was answered `ok`, whether its `Opened` push arrived, and the size last sent for it. Every message
 * to the Mac goes through one FIFO outbox drained by one coroutine in [scope] (started by the first `run()`, finished by
 * [close]); it awaits each call, and an open's answer is handled before the next message goes.
 *
 * **Every send is the last step of a change** (review C I-1). On an immediate dispatcher (the app's `hub.scope` is
 * `Main.immediate`; the demo's in-process Mac answers without suspending) `send()` may deliver the message, and the
 * answer and the pushes it brings may be handled, before it returns. So the phase, the clocks, the counters and the
 * view are set before a message goes, and nothing is written after it.
 *
 * - **R1 Want.** The model wants a view while `active`, `terminalId != null`, a grid is known, `link.isOnline`,
 *   `link.supportsTerminalView`, the phase is not Unavailable, and it is not waiting for the Mac after a NotSent (R3).
 *   reconcile() (after every change below) first queues `close` for a view that is no longer wanted or is for another
 *   terminal and forgets it; then, when wanted and there is no view, queues `open(terminalId, cols, rows)` with the
 *   next attempt number and sets Connecting. While `active`, when the Mac is the reason nothing can be wanted: online
 *   without `terminal_view` → Unsupported; not online → Offline (a Mac that went away while Unsupported stays
 *   Unsupported). A model that is not `active` never changes its phase in reconcile().
 * - **R2 show(id).** A different id: a fresh `TerminalScreen(maxHistoryRows)`, assembler and `TerminalTyping`;
 *   `snapshots = 0`, `topShift = 0`, `screenRevision += 1`; retry budgets restored; Connecting; the first-screen clock
 *   starts (when `id` is not null); reconcile. The same id does nothing. The clock starts here, at the user's swipe or
 *   tap, not at the `ok`: the Mac may hold the first snapshot up to 500 ms for the phone's size (contracts §17) and that
 *   wait is part of criterion 3. It never runs while the Mac is offline or unsupported, or the page is stopped (R1, R8,
 *   A2): the open that follows starts it again. The phase stays Connecting (the pane's loading state) after the `ok`
 *   until a snapshot is applied.
 * - **R3 Open answers**, for the current attempt only (any other is ignored): `ok` → answered. `busy` → forget the
 *   view; after 300 ms reconcile; after 5 such retries Unavailable(FAILED). `not_found` → forget, Unavailable(GONE).
 *   `refused` → forget, Unavailable(REFUSED). `failed` (also the answer for a terminal the Mac lists but cannot view,
 *   contracts §17), an unknown outcome, or NoAnswer while `link.isOnline` → forget; the first time, reconcile after
 *   1 s (Connecting meanwhile); the second time Unavailable(FAILED). NoAnswer while online means the Mac may have
 *   opened the view although its answer never came, so `close` for that view is queued first (through the same
 *   outbox); NoAnswer while not online sends no close, the session being gone as in R8. NotSent, or NoAnswer while not
 *   online → forget, and open again only after the next State event of this Mac or a `show`, `retry` or new `run()`
 *   (so a hub that still calls the Mac online during a reconnect cannot make the model ask in a loop); while `active`,
 *   R1 then sets Offline or Unsupported.
 * - **R4 `Opened(id)`** for the view's terminal on this Mac, once its open was handed to the link (`sent`: a leftover
 *   `Opened` of an earlier open is ignored): a fresh `TerminalFrameAssembler`; frames count from now on. Frames of that
 *   terminal before it are ignored. Every push for another terminal or another Mac is ignored.
 * - **R5 Frames.** `assembler.receive(part)` for every part, `TerminalFramePart.LOST` included, with no revision
 *   filter before it (plan 3G Decision 2); `resync` → queue `resync(id)`; a complete frame → R7.
 * - **R6 `Ended(id, reason)`** of the view (after its `Opened`): `gone` → Unavailable(GONE); `refused` →
 *   Unavailable(REFUSED); `not_open` → forget the view and reconcile at once (a new open), on the failed-open budget: a
 *   second `not_open` (or failure) before a snapshot restores it gives Unavailable(FAILED); `failed` or unknown → as a
 *   failed open (R3). Before `Opened` it is ignored.
 * - **R7 Apply.** `screen.apply(frame)`, `screenRevision += 1`. A snapshot: `snapshots += 1`, `topShift = 0`, phase
 *   Live, the first-screen latency recorded (once per start of the clock; a reopen after R6, R8 or a new run() starts
 *   it again when it is not running), both retry budgets restored. A history frame: `topShift += after − before`. A
 *   delta on the main screen: `topShift −= max(0, before + min(scroll, rows) + min(history, max(0, scroll − rows)) −
 *   after)` (`before`/`after`: history row counts around the apply; `scroll`, `rows`, `history` from the head). Every
 *   apply records TERMINAL_FRAME_APPLY (assemble plus apply); the first apply after an echo start records
 *   TERMINAL_KEY_ECHO.
 * - **R8 Mac state** `State(machineId, s)`: not Online → forget the view without a close (its session is gone),
 *   restore both retry budgets (an open lost with the session, answered NoAnswer before the hub saw the drop, is no
 *   failure of the Mac's) and, unless the phase is Unavailable or Unsupported, set Offline; the screen stays. Online →
 *   reconcile (a new open).
 * - **R9 run().** Collects `link.terminalEvents(machineId)`, sets running, reconciles, handles events until cancelled,
 *   then clears running and reconciles (the close is queued and still goes out; A2). A `run()` that starts while an
 *   older one is still running takes over: only the newest handles events and owns running; the older one stops
 *   collecting and returns without touching state. `retry()` clears Unavailable and the budgets, sets Connecting,
 *   reconciles. A run that starts with no view (after a stop) restores both budgets: a stopped page hears no State,
 *   so it cannot tell whether a reconnect it missed would have restored them (R8).
 * - **R10 Typing** (`insertText`, `setMarkedText`, `unmarkText`, `deleteBackward`, `typeKey`, `press`, `toggleCtrl`):
 *   `TerminalTyping` turns the call into units; with a view, each message of `TerminalInputBatcher.messages(units)` is
 *   queued as `input(id, units)` (after any queued open) and raises `sentInputs` by one; without a view they are
 *   dropped. A message holding a `text` or `key` unit starts the echo clock if it is not running; the clock is dropped
 *   after 2 s without a frame.
 * - **R11 Grid** `setPhoneGrid(cols, rows)`: values below 1 are ignored; the grid is stored and the model reconciles
 *   (the first grid may open). With a view, a grid different from the size last sent is queued as `resize` 200 ms
 *   after the last change (a newer change restarts the wait); an open carries the grid of its moment.
 * - **R12 Paste and scroll.** `paste(text)`: when `TerminalInputBatcher.pasteFits(text)` is false nothing is sent and
 *   the model raises `pasteTooLarge` (A6); otherwise `TerminalInputBatcher.pasteUnits(text)` → messages, with a view.
 *   `scroll(lines)` only with a view and `screen.alt`: summed for 50 ms, then `TerminalInputBatcher.scrollUnits(total)`
 *   as one message.
 *
 * Plan 3G's changes for Android:
 * - **A1 (R1, R9).** No `suspend()` or `resume()`: where 2C says resume, read "a new run()". `active` means the newest
 *   run() is running. The workspace screen runs run() only while it is STARTED, so the background, another screen over
 *   it, or a rotation cancels it (the view closes), and the next START runs it again (it reopens).
 * - **A2 (R9).** The cleanup of a cancelled run() is deferred by one dispatch: it is launched in [scope] and yields
 *   once, so a run() started in the same main-loop turn (a restarted effect) takes over. Then, if no newer run()
 *   started, the model stops being active: it cancels an open that has no answer yet, so the client announces no
 *   `Opened` for it that a later run would take as its own (re-review B N-1), and reconciles (the close is queued and
 *   still goes out). An open still queued then is never sent (review C m1).
 * - **A3 (state).** The observable part is [state]; `markedText` and `ctrlLatched` are copied out of the mutable
 *   `TerminalTyping` after every change. [screen] is the mutable `TerminalScreen`, replaced by R2 and changed in place
 *   by R7 (`screenRevision` says when).
 * - **A4 ([close]).** Stops the model for good: queues the close of its view, cancels an open without an answer and
 *   every delay, lets the outbox drain, and ignores every later call. The screen's holder calls it from `onCleared()`.
 * - **A5 (clock).** The first-screen, apply and echo clocks read [now].
 * - **A6 (R12).** The notice of a paste over `MAX_PASTE_BYTES` is `pasteTooLarge`, raised by one per refused paste.
 *
 * Only the newest collection of a Mac's terminal events takes its pushes (plan 3G chunk B, [TerminalLink]): of two
 * models of one Mac that run at once (a navigation transition, predictive back), only the newer one gets frames; the
 * older one gets states, and pushes again only when the newer one stops.
 */
class TerminalViewModel(
    val machineId: String,
    private val link: TerminalLink,
    private val scope: CoroutineScope,
    private val maxHistoryRows: Int = TerminalScreen.DEFAULT_MAX_HISTORY_ROWS,
    private val sleep: suspend (Duration) -> Unit = { delay(it) },
    private val now: TimeSource.WithComparableMarks = TimeSource.Monotonic,
) : TerminalTextInput {
    companion object {
        val RESIZE_DELAY: Duration = 200.milliseconds
        val BUSY_RETRY_DELAY: Duration = 300.milliseconds
        const val BUSY_RETRIES = 5
        val FAILED_RETRY_DELAY: Duration = 1.seconds
        val SCROLL_COALESCING: Duration = 50.milliseconds
        val ECHO_TIMEOUT: Duration = 2.seconds

        /**
         * Shows [screen] in [phase] and sends nothing (render tests, previews): its link is never online and supports
         * nothing, and its scope never runs anything. Never call run() on it. `snapshots` is 1 when [screen] has a
         * size, else 0.
         */
        fun fixed(
            terminalId: String,
            screen: TerminalScreen = TerminalScreen(),
            phase: TerminalViewPhase = TerminalViewPhase.Live,
            markedText: String = "",
            ctrlLatched: Boolean = false,
        ): TerminalViewModel {
            val model = TerminalViewModel("", SilentTerminalLink, CoroutineScope(Job().apply { cancel() }), sleep = {})
            model.shown.terminalId = terminalId
            model.screen = screen
            model.shown.phase = phase
            model.typing = TerminalTyping(markedText, ctrlLatched)
            model.shown.snapshots = if (screen.cols > 0) 1 else 0
            model.publish()
            return model
        }
    }

    private data class GridSize(val cols: Int, val rows: Int)

    /** The terminal asked of the Mac (R1). */
    private class View(val terminalId: String, val attempt: Int, var size: GridSize) {
        /** The outbox handed the open to the link: its `Opened` may come before the answer. */
        var sent = false
        var answered = false
        var opened = false
    }

    private sealed interface Message {
        data class Open(val terminalId: String, val cols: Int, val rows: Int, val attempt: Int) : Message
        data class Close(val terminalId: String) : Message
        data class Input(val terminalId: String, val units: List<TerminalInputUnit>) : Message
        data class Resize(val terminalId: String, val cols: Int, val rows: Int) : Message
        data class Resync(val terminalId: String) : Message
    }

    /** What [state] publishes, kept here as it changes and copied out by [publish]. */
    private class Shown {
        var terminalId: String? = null
        var phase: TerminalViewPhase = TerminalViewPhase.Connecting
        var screenRevision = 0L
        var snapshots = 0
        var topShift = 0
        var sentInputs = 0
        var pasteTooLarge = 0
    }

    private val shown = Shown()
    private val _state = MutableStateFlow(TerminalViewState())

    /** A3: everything a page draws but the screen itself. */
    val state: StateFlow<TerminalViewState> = _state.asStateFlow()

    val terminalId: String? get() = state.value.terminalId
    val phase: TerminalViewPhase get() = state.value.phase
    val screenRevision: Long get() = state.value.screenRevision
    val snapshots: Int get() = state.value.snapshots
    val topShift: Int get() = state.value.topShift
    override val markedText: String get() = state.value.markedText
    val ctrlLatched: Boolean get() = state.value.ctrlLatched
    val sentInputs: Int get() = state.value.sentInputs
    val pasteTooLarge: Int get() = state.value.pasteTooLarge

    /**
     * Whether what is typed goes anywhere, so the page keeps or takes the keyboard and shows the key bar (the iPhone's
     * final review): Live, or Connecting after a screen came while a view is opening (input queues behind the open,
     * R10: a new run, a reconnect, a `not_open` reopen). Not in the wait before a busy or failed open is retried, nor
     * while waiting for the Mac after a NotSent (no view to type into), Offline, Unsupported, Unavailable, or before the
     * first screen (the loading card covers the surface). A stopped page (A1) keeps the phase, and so the keyboard, as
     * it was.
     */
    val acceptsInput: Boolean get() = state.value.acceptsInput

    /** The screen shown: replaced by show() of another terminal, changed in place by each frame. Main thread only. */
    var screen: TerminalScreen = TerminalScreen(maxHistoryRows)
        private set

    private var typing = TerminalTyping()
    private var assembler = TerminalFrameAssembler()
    private var grid: GridSize? = null
    private var view: View? = null
    private var attempts = 0

    /** Raised by every run(): only the newest handles events and owns [running] (R9). */
    private var runGeneration = 0
    private var running = false
    private var closed = false

    /** A run's collection of terminal events; [stopped] tells its run that a newer run() or close() cancelled it. */
    private class Collection(private val job: Job) {
        var stopped = false
            private set

        fun stop() {
            stopped = true
            job.cancel()
        }
    }

    /** The newest run's collection of terminal events, while it runs: a newer run() or close() stops it. */
    private var collecting: Collection? = null

    /** After a NotSent (or NoAnswer while not online): no open until this Mac's next State, show, retry or run (R3). */
    private var waitingForMac = false
    private var busyRetriesUsed = 0
    private var failedRetriesUsed = 0

    /** A busy or failed open waiting out its delay: no open meanwhile. */
    private var retryWait: Job? = null
    private var retryToken = 0

    /** The first-screen clock (R2, R7): running from a show or a reopen until a snapshot is applied. */
    private var firstScreenStart: ComparableTimeMark? = null

    private val outbox = Channel<Message>(Channel.UNLIMITED)
    private var drainer: Job? = null

    /** An open the outbox waits on: [abandon] ends the wait at once and cancels the call (A2, A4). */
    private class OpenCall(private val call: Job, private val abandoned: CompletableDeferred<Unit>) {
        fun abandon() {
            abandoned.complete(Unit)
            call.cancel()
        }
    }

    /** The open the outbox is waiting on, while it waits: A2 and A4 abandon it. */
    private var openCall: OpenCall? = null

    /** The resize waiting out RESIZE_DELAY after the last grid change (R11). */
    private var resizeWait: Job? = null
    private var resizeToken = 0

    /** Alternate-screen scrolling summed until SCROLL_COALESCING has passed (R12). */
    private var scrollSum = 0
    private var scrollWait: Job? = null
    private var scrollToken = 0

    /** The echo clock (R10): from the first message of typed text or a key to the next frame applied, at most
     *  ECHO_TIMEOUT. */
    private var echoStart: ComparableTimeMark? = null
    private var echoWait: Job? = null
    private var echoToken = 0

    // Lifecycle (R2, R9, R11, A1, A2, A4)

    /**
     * R9, A1, A2: handles this Mac's terminal events until cancelled (or until a newer run() or [close] takes over);
     * the close queued at the end still goes out.
     */
    suspend fun run() {
        if (closed) return
        startOutbox()
        val generation = ++runGeneration
        collecting?.stop()
        running = true
        waitingForMac = false
        if (view == null) {
            // After a stop (not a restart in the same turn, which keeps its view): the page heard no State meanwhile,
            // and a reconnect it missed restores both budgets on the iPhone (R8; review C m3). A retry wait still
            // pending stays.
            busyRetriesUsed = 0
            failedRetriesUsed = 0
        }
        reconcile()
        publish()
        var mine: Collection? = null
        try {
            coroutineScope {
                val collection = Collection(coroutineContext.job)
                mine = collection
                collecting = collection
                // Straight into a handler that never suspends: no operator between the hub's queue and the assembler.
                link.terminalEvents(machineId).collect { event ->
                    if (generation == runGeneration && !closed) {
                        handle(event)
                        publish()
                    }
                }
            }
        } catch (e: CancellationException) {
            // Only a newer run() or close() ends a run quietly (review C m2); the caller's own cancellation goes on.
            if (mine?.stopped != true) throw e
            currentCoroutineContext().ensureActive()
        } finally {
            if (collecting === mine) collecting = null
            if (generation == runGeneration && !closed) stopAfterOneDispatch(generation)
        }
    }

    /** R2. */
    fun show(terminalId: String?) {
        if (closed || terminalId == shown.terminalId) return
        shown.terminalId = terminalId
        screen = TerminalScreen(maxHistoryRows)
        assembler = TerminalFrameAssembler()
        typing = TerminalTyping()
        shown.snapshots = 0
        shown.topShift = 0
        shown.screenRevision += 1
        restoreBudgets()
        dropEcho()
        waitingForMac = false
        shown.phase = TerminalViewPhase.Connecting
        firstScreenStart = if (terminalId == null) null else now.markNow()
        reconcile()
        publish()
    }

    /** R11: the size that fits the pane. Values below 1 are ignored. */
    fun setPhoneGrid(cols: Int, rows: Int) {
        if (closed || cols < 1 || rows < 1) return
        val grid = GridSize(cols, rows)
        this.grid = grid
        reconcile()
        val current = view
        if (current == null || grid == current.size) cancelResize() else scheduleResize()
        publish()
    }

    /** Try Again. Nothing to do while a view is open. */
    fun retry() {
        if (closed || view != null) return
        restoreBudgets()
        waitingForMac = false
        shown.phase = TerminalViewPhase.Connecting
        reconcile()
        publish()
    }

    /**
     * A4: stops the model for good. The close of its view is queued, an open without an answer is cancelled, every
     * delay is cancelled, and the returned job completes once the outbox has sent what it holds. Every later call is
     * ignored.
     */
    fun close(): Job {
        if (!closed) {
            closed = true
            running = false
            view?.let {
                forgetView()
                send(Message.Close(it.terminalId))
            }
            openCall?.abandon()
            restoreBudgets()
            dropEcho()
            collecting?.stop()
            outbox.close()
        }
        return drainer ?: Job().apply { complete() }
    }

    // R1

    private val active: Boolean get() = running && !closed

    private val isUnavailable: Boolean get() = shown.phase is TerminalViewPhase.Unavailable

    private fun reconcile() {
        val online = link.isOnline(machineId)
        val supported = link.supportsTerminalView(machineId)
        val id = shown.terminalId
        val grid = grid
        val wanted = active && id != null && grid != null && online && supported && !isUnavailable && !waitingForMac
        val current = view
        if (current != null && (!wanted || current.terminalId != id)) {
            forgetView()
            send(Message.Close(current.terminalId))
        }
        if (wanted) {
            if (view != null || retryWait != null) return
            attempts += 1
            view = View(id, attempts, grid)
            if (firstScreenStart == null) firstScreenStart = now.markNow()
            shown.phase = TerminalViewPhase.Connecting
            // Last: the answer, the Opened and the first screen may all be handled inside it.
            send(Message.Open(id, grid.cols, grid.rows, attempts))
            return
        }
        if (!active || isUnavailable || (online && supported)) return
        // No open while the Mac is the reason: the first-screen clock starts again at the open that brings it.
        firstScreenStart = null
        shown.phase = when {
            online -> TerminalViewPhase.Unsupported
            shown.phase == TerminalViewPhase.Unsupported -> TerminalViewPhase.Unsupported
            else -> TerminalViewPhase.Offline
        }
    }

    /** The view's waits go with it: a resize or scroll for it never reaches the next view. */
    private fun forgetView() {
        view = null
        cancelResize()
        scrollWait?.cancel()
        scrollWait = null
        scrollToken += 1
        scrollSum = 0
        dropEcho()
    }

    private fun restoreBudgets() {
        busyRetriesUsed = 0
        failedRetriesUsed = 0
        retryWait?.cancel()
        retryWait = null
        retryToken += 1
    }

    private fun becomeUnavailable(reason: TerminalUnavailableReason) {
        forgetView()
        shown.phase = TerminalViewPhase.Unavailable(reason)
        firstScreenStart = null
    }

    /** Reconciles after [delay]; no open goes out meanwhile. */
    private fun retryAfter(delay: Duration) {
        retryWait?.cancel()
        val token = ++retryToken
        val wait = scope.launch(start = CoroutineStart.LAZY) {
            sleep(delay)
            if (retryToken != token) return@launch
            retryWait = null
            reconcile()
            publish()
        }
        retryWait = wait
        wait.start()
    }

    /** A2: the run with [generation] ended; unless a newer one starts within one dispatch, the model stops being active. */
    private fun stopAfterOneDispatch(generation: Int) {
        scope.launch {
            yield()
            if (generation != runGeneration || closed) return@launch
            running = false
            // The iPhone's suspend(): the clock stops; the open of the next run starts it again.
            firstScreenStart = null
            reconcile()
            // An open still waiting would be announced to the next run as its own `Opened` (re-review B N-1). After
            // reconcile(), which forgot its view and queued its close: the cancel may be handled inside this call.
            openCall?.abandon()
            publish()
        }
    }

    // The outbox

    private fun send(message: Message) {
        outbox.trySend(message)
    }

    private fun startOutbox() {
        if (drainer != null) return
        drainer = scope.launch {
            for (message in outbox) deliver(message)
        }
    }

    private suspend fun deliver(message: Message) {
        when (message) {
            is Message.Open -> {
                // A stopped page's open that was still queued (review C m1): its view is forgotten and its close queued.
                // Sent now, its `Opened` would wait in the queue for the next run, which would take it as its own.
                if (!running && view?.attempt != message.attempt) return
                openSending(message.attempt)
                val call = scope.async(start = CoroutineStart.UNDISPATCHED) {
                    link.openTerminalView(machineId, message.terminalId, message.cols, message.rows)
                }
                val abandoned = CompletableDeferred<Unit>()
                val open = OpenCall(call, abandoned)
                openCall = open
                val result = try {
                    // An abandoned open is not waited for (a link may be slow to honour the cancel, review C m4):
                    // whoever abandoned it forgot its view and queued its close, and there is no answer to handle.
                    select<TerminalOpenResult?> {
                        abandoned.onAwait { null }
                        call.onAwait { it }
                    }
                } catch (e: CancellationException) {
                    // The drainer's own cancellation goes on; a call cancelled by anyone else is an open with no answer.
                    currentCoroutineContext().ensureActive()
                    if (abandoned.isCompleted) null else TerminalOpenResult.NoAnswer
                } finally {
                    if (openCall === open) openCall = null
                }
                if (result != null) openAnswered(result, message.attempt)
            }
            is Message.Close -> link.closeTerminalView(machineId, message.terminalId)
            is Message.Input -> link.sendTerminalInput(machineId, message.terminalId, message.units)
            is Message.Resize -> link.resizeTerminalView(machineId, message.terminalId, message.cols, message.rows)
            is Message.Resync -> link.resyncTerminalView(machineId, message.terminalId)
        }
    }

    // R3

    private fun openSending(attempt: Int) {
        view?.takeIf { it.attempt == attempt }?.sent = true
    }

    private fun openAnswered(result: TerminalOpenResult, attempt: Int) {
        if (closed) return
        val current = view?.takeIf { it.attempt == attempt } ?: return
        when (result) {
            is TerminalOpenResult.Outcome -> when (result.outcome) {
                TerminalViewOpenOutcome.OK -> current.answered = true
                TerminalViewOpenOutcome.BUSY -> {
                    forgetView()
                    if (busyRetriesUsed >= BUSY_RETRIES) {
                        becomeUnavailable(TerminalUnavailableReason.FAILED)
                    } else {
                        busyRetriesUsed += 1
                        retryAfter(BUSY_RETRY_DELAY)
                    }
                }
                TerminalViewOpenOutcome.NOT_FOUND -> becomeUnavailable(TerminalUnavailableReason.GONE)
                TerminalViewOpenOutcome.REFUSED -> becomeUnavailable(TerminalUnavailableReason.REFUSED)
                else -> failedOpen()
            }
            TerminalOpenResult.NoAnswer -> if (link.isOnline(machineId)) {
                failedOpen()
                // The Mac may have opened it although the answer never came.
                send(Message.Close(current.terminalId))
            } else {
                waitForMac()
            }
            TerminalOpenResult.NotSent -> waitForMac()
        }
        publish()
    }

    private fun waitForMac() {
        forgetView()
        waitingForMac = true
        reconcile()
    }

    /**
     * A failed open or a failed view: retried once after 1 s, then Try Again. The wait is Connecting: a view that ended
     * while live must not look live while nothing typed can reach the Mac (the iPhone's final review, core M1).
     */
    private fun failedOpen() {
        forgetView()
        if (failedRetriesUsed >= 1) {
            becomeUnavailable(TerminalUnavailableReason.FAILED)
        } else {
            failedRetriesUsed += 1
            shown.phase = TerminalViewPhase.Connecting
            retryAfter(FAILED_RETRY_DELAY)
        }
    }

    // Events (R4–R8)

    private fun handle(event: TerminalHubEvent) {
        when (event) {
            is TerminalHubEvent.State -> if (event.machineId == machineId) macState(event.state)
            is TerminalHubEvent.Push -> {
                if (event.machineId != machineId) return
                when (val push = event.push) {
                    is TerminalViewPush.Opened -> opened(push.terminalId)
                    is TerminalViewPush.Frame -> frame(push.terminalId, push.part)
                    is TerminalViewPush.Ended -> ended(push.terminalId, push.reason)
                }
            }
        }
    }

    /** R4. */
    private fun opened(id: String) {
        val current = view?.takeIf { it.terminalId == id && it.sent } ?: return
        current.opened = true
        assembler = TerminalFrameAssembler()
    }

    /** R5: every part, LOST included, goes to the assembler. */
    private fun frame(id: String, part: TerminalFramePart) {
        view?.takeIf { it.terminalId == id && it.opened } ?: return
        val started = now.markNow()
        val result = assembler.receive(part)
        result.frame?.let { apply(it, started) }
        if (result.resync) send(Message.Resync(id))
    }

    /** R6. */
    private fun ended(id: String, reason: TerminalViewEndReason) {
        view?.takeIf { it.terminalId == id && it.opened } ?: return
        when (reason) {
            TerminalViewEndReason.GONE -> becomeUnavailable(TerminalUnavailableReason.GONE)
            TerminalViewEndReason.REFUSED -> becomeUnavailable(TerminalUnavailableReason.REFUSED)
            TerminalViewEndReason.NOT_OPEN -> {
                // Reopened at once, but on the failed-open budget (a snapshot restores it): a Mac that keeps ending its
                // views before any screen cannot make the phone open them forever.
                forgetView()
                if (failedRetriesUsed >= 1) {
                    becomeUnavailable(TerminalUnavailableReason.FAILED)
                } else {
                    failedRetriesUsed += 1
                    reconcile()
                }
            }
            else -> failedOpen()
        }
    }

    /** R7. */
    private fun apply(frame: TerminalGridFrame, started: ComparableTimeMark) {
        val head = frame.head
        val before = screen.historyRows.size
        screen.apply(frame)
        val after = screen.historyRows.size
        shown.screenRevision += 1
        when {
            head.kind == TerminalFrameKind.SNAPSHOT -> {
                shown.snapshots += 1
                shown.topShift = 0
                shown.phase = TerminalViewPhase.Live
                firstScreenStart?.let {
                    link.recordLatency(LatencyMetric.TERMINAL_FIRST_SCREEN, it.elapsedNow())
                    firstScreenStart = null
                }
                restoreBudgets()
            }
            head.kind == TerminalFrameKind.HISTORY -> shown.topShift += after - before
            head.kind == TerminalFrameKind.DELTA && !head.alt -> {
                val carried = minOf(head.history, maxOf(0, head.scroll - head.rows))
                shown.topShift -= maxOf(0, before + minOf(head.scroll, head.rows) + carried - after)
            }
        }
        link.recordLatency(LatencyMetric.TERMINAL_FRAME_APPLY, started.elapsedNow())
        echoStart?.let {
            link.recordLatency(LatencyMetric.TERMINAL_KEY_ECHO, it.elapsedNow())
            dropEcho()
        }
    }

    /** R8. */
    private fun macState(state: MachineLinkState) {
        waitingForMac = false
        if (state != MachineLinkState.Online) {
            forgetView()   // its session is gone: nothing to close
            firstScreenStart = null   // the open once it is back starts the clock again
            // An open lost with the session was no failure of the Mac's: the next session starts with both retries.
            restoreBudgets()
            if (!isUnavailable && shown.phase != TerminalViewPhase.Unsupported) shown.phase = TerminalViewPhase.Offline
            return
        }
        reconcile()
    }

    // Typing, paste, scrolling and resizing (R10–R12)

    override fun insertText(text: String) = type { typing.insert(text) }

    override fun setMarkedText(text: String) = type { typing.setMarked(text) }

    override fun unmarkText() = type { typing.unmark() }

    override fun deleteBackward() = type { typing.deleteBackward() }

    /** Text a key event types: the word in progress goes first, in the same message (review B2 I-2). */
    override fun typeKey(text: String) = type { typing.typeKey(text) }

    override fun press(key: TerminalKey, mods: List<TerminalModifier>) = type { typing.key(key, mods) }

    fun toggleCtrl() = type {
        typing.toggleCtrl()
        emptyList()
    }

    /**
     * R12: refused whole when it does not fit (`pasteTooLarge`, A6; the word being composed stays), else sent in
     * paste-sized messages after the word being composed, which is committed first as before a key.
     */
    override fun paste(text: String) {
        if (closed) return
        if (!TerminalInputBatcher.pasteFits(text)) {
            shown.pasteTooLarge += 1
        } else {
            sendUnits(typing.unmark() + TerminalInputBatcher.pasteUnits(text))
        }
        publish()
    }

    /** R12: alternate-screen scrolling (positive: toward older content), summed for SCROLL_COALESCING. */
    fun scroll(lines: Int) {
        if (closed || view == null || !screen.alt || lines == 0) return
        scrollSum += lines
        if (scrollWait != null) return
        val token = scrollToken
        val wait = scope.launch(start = CoroutineStart.LAZY) {
            sleep(SCROLL_COALESCING)
            flushScroll(token)
        }
        scrollWait = wait
        wait.start()
    }

    /** One typing call: [units] of it go out with a view, and the typing state is copied out (A3). */
    private inline fun type(units: () -> List<TerminalInputUnit>) {
        if (closed) return
        sendUnits(units())
        publish()
    }

    /** R10: [units] as input messages to the view, after any queued open; dropped without a view. */
    private fun sendUnits(units: List<TerminalInputUnit>) {
        val current = view ?: return
        if (units.isEmpty()) return
        for (message in TerminalInputBatcher.messages(units)) {
            // A message handled inside its send may have ended the view: the rest would go to a view that is gone.
            if (view !== current) return
            shown.sentInputs += 1
            if (echoStart == null && message.any { it is TerminalInputUnit.Text || it is TerminalInputUnit.Key }) startEcho()
            send(Message.Input(current.terminalId, message))
        }
    }

    private fun flushScroll(token: Int) {
        if (token != scrollToken) return
        scrollWait = null
        val total = scrollSum
        scrollSum = 0
        sendUnits(TerminalInputBatcher.scrollUnits(total))
        publish()
    }

    private fun startEcho() {
        echoStart = now.markNow()
        val token = ++echoToken
        echoWait?.cancel()
        val wait = scope.launch(start = CoroutineStart.LAZY) {
            sleep(ECHO_TIMEOUT)
            if (echoToken != token) return@launch
            echoStart = null
            echoWait = null
        }
        echoWait = wait
        wait.start()
    }

    private fun dropEcho() {
        echoStart = null
        echoToken += 1
        echoWait?.cancel()
        echoWait = null
    }

    /** R11: the grid goes out RESIZE_DELAY after its last change, unless it is the size last sent. */
    private fun scheduleResize() {
        resizeWait?.cancel()
        val token = ++resizeToken
        val wait = scope.launch(start = CoroutineStart.LAZY) {
            sleep(RESIZE_DELAY)
            if (resizeToken != token) return@launch
            resizeWait = null
            val current = view ?: return@launch
            val grid = grid ?: return@launch
            if (grid == current.size) return@launch
            current.size = grid
            send(Message.Resize(current.terminalId, grid.cols, grid.rows))
        }
        resizeWait = wait
        wait.start()
    }

    private fun cancelResize() {
        resizeWait?.cancel()
        resizeWait = null
        resizeToken += 1
    }

    private fun publish() {
        _state.value = TerminalViewState(
            terminalId = shown.terminalId,
            phase = shown.phase,
            screenRevision = shown.screenRevision,
            snapshots = shown.snapshots,
            topShift = shown.topShift,
            markedText = typing.markedText,
            ctrlLatched = typing.ctrlLatched,
            sentInputs = shown.sentInputs,
            pasteTooLarge = shown.pasteTooLarge,
            acceptsInput = when (shown.phase) {
                TerminalViewPhase.Live -> true
                TerminalViewPhase.Connecting -> shown.snapshots > 0 && retryWait == null && !waitingForMac
                else -> false
            },
        )
    }
}

/** The link of a fixed model: never online, supports nothing, sends nothing. */
private object SilentTerminalLink : TerminalLink {
    override fun terminalEvents(machineId: String): Flow<TerminalHubEvent> = emptyFlow()

    override fun isOnline(machineId: String): Boolean = false

    override fun supportsTerminalView(machineId: String): Boolean = false

    override suspend fun openTerminalView(machineId: String, terminalId: String, cols: Int, rows: Int): TerminalOpenResult =
        TerminalOpenResult.NotSent

    override suspend fun closeTerminalView(machineId: String, terminalId: String) = Unit

    override suspend fun sendTerminalInput(machineId: String, terminalId: String, units: List<TerminalInputUnit>) = Unit

    override suspend fun resizeTerminalView(machineId: String, terminalId: String, cols: Int, rows: Int) = Unit

    override suspend fun resyncTerminalView(machineId: String, terminalId: String) = Unit

    override fun recordLatency(metric: LatencyMetric, duration: Duration) = Unit
}
