package com.shellx.core.demo

import com.shellx.core.text.dropLastGrapheme
import com.shellx.core.text.graphemes
import com.shellx.link.core.TerminalCursor
import com.shellx.link.core.TerminalFrameHead
import com.shellx.link.core.TerminalFrameKind
import com.shellx.link.core.TerminalFramePart
import com.shellx.link.core.TerminalGridFrame
import com.shellx.link.core.TerminalInputUnit
import com.shellx.link.core.TerminalKey
import com.shellx.link.core.TerminalLine
import com.shellx.link.core.TerminalModifier
import com.shellx.link.core.TerminalRun
import com.shellx.link.core.TerminalViewEndReason
import com.shellx.link.core.TerminalViewOpenOutcome
import com.shellx.link.core.TerminalViewPush
import com.shellx.link.core.WorkspaceControlOutcome
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * [FakeMac]'s terminals (FakeMacTerminals.swift), as the host a phone's session talks to: on Android there is no
 * `LinkHost`, so each [FakeMacSession] is its own host and calls in here with the host rules of PROTOCOL.md 11.1–11.3
 * and TerminalViewSlot.swift already checked (feature, sizes clamped, input checked).
 *
 * A session views at most one terminal. A view shows its terminal's fixture ([setFixtures]), or a fresh
 * [DemoTerminalScreens.prompt] at the size asked for. A fixture with a prompt is a tiny shell that echoes typing; one
 * with ticks prints a line every interval while it is viewed (`delay` in the Mac's [scope]). Frames go to the
 * session's terminal pushes as they are made, one part each (in memory there is no frame limit), at revision 1, 2, … of
 * the view: a snapshot when the view opens and for each resync, a delta after each change (2C Task 1's rules 1–6).
 * Every call is recorded for tests.
 *
 * Every member takes the Mac's lock; frames are offered under it, so each view's frames keep their order.
 */
internal class FakeMacTerminals(
    live: FakeMacLive,
    private val workspaces: FakeMacWorkspaces,
    private val scope: CoroutineScope,
) {
    private val lock = live.lock
    private var fixtures: Map<String, DemoTerminalFixture> = emptyMap()
    private val refused = HashMap<String, TerminalViewOpenOutcome>()
    private val views = LinkedHashMap<FakeMacSession, FakeMacTerminalView>()
    private val opens = ArrayList<FakeMac.TerminalViewSize>()
    private val resizes = ArrayList<FakeMac.TerminalViewSize>()
    private val closes = ArrayList<String>()
    private val inputs = HashMap<String, MutableList<List<TerminalInputUnit>>>()
    private val snapshotRequests = HashMap<String, Int>()
    private val creates = ArrayList<String>()
    private var nextCreateOutcome: WorkspaceControlOutcome? = null

    /** Opens wait while it holds, after their size is recorded. */
    val hold = FakeMacHold(lock)

    val viewOpens: List<FakeMac.TerminalViewSize> get() = synchronized(lock) { opens.toList() }
    val viewResizes: List<FakeMac.TerminalViewSize> get() = synchronized(lock) { resizes.toList() }
    val viewCloses: List<String> get() = synchronized(lock) { closes.toList() }
    val createCalls: List<String> get() = synchronized(lock) { creates.toList() }

    fun viewInputs(terminalId: String): List<List<TerminalInputUnit>> = synchronized(lock) { inputs[terminalId]?.toList() ?: emptyList() }

    fun viewSnapshotRequests(terminalId: String): Int = synchronized(lock) { snapshotRequests[terminalId] ?: 0 }

    fun setFixtures(fixtures: Map<String, DemoTerminalFixture>) {
        synchronized(lock) { this.fixtures = fixtures.toMap() }
    }

    fun refuse(terminalId: String, outcome: TerminalViewOpenOutcome) {
        synchronized(lock) { refused[terminalId] = outcome }
    }

    fun setNextCreateOutcome(outcome: WorkspaceControlOutcome) {
        synchronized(lock) { nextCreateOutcome = outcome }
    }

    /** [frame] goes out as the next revision of every view of [terminalId]. */
    fun emit(terminalId: String, frame: TerminalGridFrame) {
        synchronized(lock) { for (view in views.values) if (view.terminalId == terminalId) view.sendLocked(frame) }
    }

    /** Every session viewing [terminalId] gets `Ended(terminalId, reason)`, and those views close. */
    fun end(terminalId: String, reason: TerminalViewEndReason) {
        synchronized(lock) {
            for ((session, view) in views.entries.filter { it.value.terminalId == terminalId }) {
                session.offerTerminal(TerminalViewPush.Ended(terminalId, reason))
                closeLocked(session, view)
            }
        }
    }

    // The session's calls (FakeMacSession, one at a time per session)

    /**
     * `terminal.view.open` with [cols] and [rows] already clamped. Another terminal viewed → BUSY, nothing recorded.
     * The same one → its view closes, then as a new open: the size is recorded, the open waits while [hold] holds,
     * then a refused id answers its outcome, an id no workspace lists NOT_FOUND, and otherwise the view opens:
     * `Opened` and its snapshot at revision 1 are on the session's pushes before OK is returned.
     */
    suspend fun open(session: FakeMacSession, terminalId: String, cols: Int, rows: Int): TerminalViewOpenOutcome {
        synchronized(lock) {
            val current = views[session]
            if (current != null) {
                if (current.terminalId != terminalId) return TerminalViewOpenOutcome.BUSY
                closeLocked(session, current)
            }
            opens += FakeMac.TerminalViewSize(terminalId, cols, rows)
        }
        hold.pass()
        synchronized(lock) {
            // The phone's session ended while the open waited: the Mac drops it (its answer has nowhere to go).
            if (session.hasEnded) return TerminalViewOpenOutcome.FAILED
            refused[terminalId]?.let { return if (it == TerminalViewOpenOutcome.OK) TerminalViewOpenOutcome.FAILED else it }
            if (!workspaces.listsTerminal(terminalId)) return TerminalViewOpenOutcome.NOT_FOUND
            // Another open of this session may have won meanwhile: a session views one terminal.
            views[session]?.let { if (it.terminalId != terminalId) return TerminalViewOpenOutcome.BUSY else closeLocked(session, it) }
            val fixture = fixtures[terminalId] ?: DemoTerminalScreens.prompt(cols, rows)
            val view = FakeMacTerminalView(terminalId, fixture, session)
            views[session] = view
            session.offerTerminal(TerminalViewPush.Opened(terminalId))
            view.sendSnapshotLocked()
            startTicksLocked(view)
            return TerminalViewOpenOutcome.OK
        }
    }

    /** `terminal.view.close`: the viewed terminal's view closes; any other id does nothing. */
    fun close(session: FakeMacSession, terminalId: String) {
        synchronized(lock) {
            val view = views[session]?.takeIf { it.terminalId == terminalId } ?: return
            closeLocked(session, view)
        }
    }

    /** `terminal.view.input`, already checked: recorded and applied (rule 3) for the view, else `not_open`. */
    fun input(session: FakeMacSession, terminalId: String, units: List<TerminalInputUnit>) {
        synchronized(lock) {
            val view = viewing(session, terminalId) ?: return notOpen(session, terminalId)
            inputs.getOrPut(terminalId) { ArrayList() } += units
            view.applyLocked(units)
        }
    }

    /** `terminal.view.resize` with [cols] and [rows] already clamped: recorded for the view (its fixture keeps its size). */
    fun resize(session: FakeMacSession, terminalId: String, cols: Int, rows: Int) {
        synchronized(lock) {
            viewing(session, terminalId) ?: return notOpen(session, terminalId)
            resizes += FakeMac.TerminalViewSize(terminalId, cols, rows)
        }
    }

    /** `terminal.view.resync`: counted, then a snapshot of the view; `not_open` for any other terminal. */
    fun resync(session: FakeMacSession, terminalId: String) {
        synchronized(lock) {
            val view = viewing(session, terminalId) ?: return notOpen(session, terminalId)
            snapshotRequests[terminalId] = (snapshotRequests[terminalId] ?: 0) + 1
            view.sendSnapshotLocked()
        }
    }

    /** The session ended: its view closes. Idempotent. */
    fun sessionEnded(session: FakeMacSession) {
        synchronized(lock) { views[session]?.let { closeLocked(session, it) } }
    }

    /**
     * `terminal.create` (rule 6): recorded; a forced next outcome other than OK answers it once with no id; otherwise
     * the workspace gets a new tab (OK and its id), or NOT_FOUND for a workspace the Mac does not list.
     */
    fun create(workspaceId: String): Pair<WorkspaceControlOutcome, String?> {
        val forced = synchronized(lock) {
            creates += workspaceId
            nextCreateOutcome.also { nextCreateOutcome = null }
        }
        if (forced != null && forced != WorkspaceControlOutcome.OK) return forced to null
        val id = workspaces.addTerminal(workspaceId) ?: return WorkspaceControlOutcome.NOT_FOUND to null
        return WorkspaceControlOutcome.OK to id
    }

    private fun viewing(session: FakeMacSession, terminalId: String): FakeMacTerminalView? =
        views[session]?.takeIf { it.terminalId == terminalId }

    private fun notOpen(session: FakeMacSession, terminalId: String) {
        session.offerTerminal(TerminalViewPush.Ended(terminalId, TerminalViewEndReason.NOT_OPEN))
    }

    private fun closeLocked(session: FakeMacSession, view: FakeMacTerminalView) {
        if (views[session] === view) views.remove(session)
        view.closed = true
        view.ticker?.cancel()
        view.ticker = null
        closes += view.terminalId
    }

    /** Rule 5: ticks `n % ticks.size` at the cursor every interval, while the view is open. */
    private fun startTicksLocked(view: FakeMacTerminalView) {
        val interval = view.fixture.tickInterval ?: return
        if (view.fixture.ticks.isEmpty()) return
        view.ticker = scope.launch {
            var n = 0
            while (true) {
                delay(interval)
                synchronized(lock) {
                    if (view.closed) return@launch
                    view.printLineLocked(n)
                }
                n += 1
            }
        }
    }
}

/**
 * One view of a fake terminal (FakeMacTerminalView in FakeMacTerminals.swift): its fixture's content, changed by typing
 * (a fixture with a prompt) and ticks, sent to its session as frames. Guarded by the Mac's lock.
 */
internal class FakeMacTerminalView(
    val terminalId: String,
    val fixture: DemoTerminalFixture,
    private val session: FakeMacSession,
) {
    private val history: MutableList<List<TerminalRun>> = if (fixture.alt) ArrayList() else fixture.history.toMutableList()

    /** Exactly `max(1, fixture.rows)` rows. */
    private val screen: MutableList<List<TerminalRun>> = run {
        val rows = maxOf(1, fixture.rows)
        (fixture.screen.take(rows) + List(maxOf(0, rows - fixture.screen.size)) { emptyList<TerminalRun>() }).toMutableList()
    }
    private var cursor: TerminalCursor = fixture.cursor

    /** What was typed after the prompt on the cursor row. */
    private var typed = ""
    private var revision = 0L
    private var dirty = false

    /** Rows that scrolled off the top since the last frame. */
    private var scrolled = 0
    var closed = false
    var ticker: Job? = null

    /** A snapshot of the content as it is now. */
    fun sendSnapshotLocked() {
        dirty = false
        scrolled = 0
        sendLocked(fixture.copy(history = history.toList(), screen = screen.toList(), cursor = cursor).snapshot)
    }

    /** [frame] as the view's next revision, in one part. */
    fun sendLocked(frame: TerminalGridFrame) {
        revision += 1
        session.offerTerminal(
            TerminalViewPush.Frame(terminalId, TerminalFramePart(revision, 0, 1, frame.head, frame.styles, frame.lines)),
        )
    }

    /** Rule 3: with a prompt, [units] change the shell's rows; one delta when anything changed. */
    fun applyLocked(units: List<TerminalInputUnit>) {
        if (fixture.prompt == null) return
        for (unit in units) apply(unit)
        sendDeltaLocked()
    }

    /** Rule 5: prints tick [n] at the cursor row, then moves down a row, and sends the change. */
    fun printLineLocked(n: Int) {
        screen[cursor.y] = fixture.ticks[n % fixture.ticks.size]
        cursor = cursor.copy(x = 0)
        lineFeed()
        dirty = true
        sendDeltaLocked()
    }

    private fun sendDeltaLocked() {
        if (!dirty) return
        dirty = false
        val delta = delta()
        scrolled = 0
        sendLocked(delta)
    }

    private fun apply(unit: TerminalInputUnit) {
        when {
            unit is TerminalInputUnit.Text -> typeText(unit.text)
            unit is TerminalInputUnit.Paste -> {
                val line = StringBuilder()
                for (character in unit.text.graphemes()) {
                    if (character == "\n" || character == "\r\n" || character == "\r") {
                        typeText(line.toString())
                        line.setLength(0)
                        newPrompt()
                    } else {
                        line.append(character)
                    }
                }
                typeText(line.toString())
            }
            unit is TerminalInputUnit.Key && unit.mods.isEmpty() && unit.key == TerminalKey.ENTER -> newPrompt()
            unit is TerminalInputUnit.Key && unit.mods.isEmpty() && unit.key == TerminalKey.BACKSPACE -> {
                if (typed.isEmpty()) return
                typed = typed.dropLastGrapheme()
                redrawPromptRow()
            }
            unit is TerminalInputUnit.Key && unit.mods == listOf(TerminalModifier.CTRL) && unit.key.letter == 'c' -> {
                typeText("^C")
                newPrompt()
            }
            unit is TerminalInputUnit.Key && unit.mods == listOf(TerminalModifier.CTRL) && unit.key.letter == 'l' -> {
                for (y in screen.indices) screen[y] = emptyList()
                cursor = cursor.copy(y = 0)
                typed = ""
                redrawPromptRow()
            }
            else -> Unit
        }
    }

    private fun typeText(text: String) {
        if (text.isEmpty()) return
        typed += text
        redrawPromptRow()
    }

    /** The cursor row becomes the prompt and what was typed after it; the cursor follows the text. */
    private fun redrawPromptRow() {
        val prompt = fixture.prompt ?: return
        screen[cursor.y] = if (typed.isEmpty()) prompt else prompt + TerminalRun(text = typed)
        val x = DemoTerminalScreens.columns(prompt) + typed.codePointCount(0, typed.length)
        cursor = cursor.copy(x = minOf(x, maxOf(0, fixture.cols - 1)))
        dirty = true
    }

    /** Enter: the row stays, a new prompt row starts under it. */
    private fun newPrompt() {
        lineFeed()
        typed = ""
        redrawPromptRow()
    }

    /** The cursor moves down a row; at the bottom row the screen scrolls one row (into history on the main screen). */
    private fun lineFeed() {
        if (cursor.y < screen.size - 1) {
            cursor = cursor.copy(y = cursor.y + 1)
        } else {
            val top = screen.removeAt(0)
            screen += emptyList<TerminalRun>()
            if (!fixture.alt) {
                history += top
                scrolled += 1
            }
        }
        dirty = true
    }

    /** Every screen row as a line; rows that scrolled past the whole screen go along as history rows (rule 2). */
    private fun delta(): TerminalGridFrame {
        val rows = screen.size
        val carried = minOf(maxOf(0, scrolled - rows), history.size)
        val lines = ArrayList<TerminalLine>(carried + rows)
        history.takeLast(carried).forEachIndexed { index, runs -> lines += TerminalLine(index - carried, runs) }
        screen.forEachIndexed { y, runs -> lines += TerminalLine(y, runs) }
        return TerminalGridFrame(
            TerminalFrameHead(
                TerminalFrameKind.DELTA, fixture.cols, rows, alt = fixture.alt, cursor = cursor, history = carried,
                scroll = if (fixture.alt) 0 else scrolled,
            ),
            fixture.styles, lines,
        )
    }
}
