package com.shellx.link.core

import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.FlowCollector
import kotlinx.coroutines.yield

/**
 * The terminal pushes of one session, between the reader that takes them off the circuit and their consumer, bounded
 * (plan 3G Task 4b, contracts §24). [offer] never suspends, so the session's reader never waits on a slow consumer:
 * pings, call answers and the other pushes keep flowing behind a terminal flood.
 *
 * The terminal viewed is the one of the last [TerminalViewPush.Opened], until its [TerminalViewPush.Ended]; a session
 * views one terminal (PROTOCOL.md 11.1). Its frames follow these rules:
 * - A delta or history frame that would take the frames queued past [maxQueuedWeight] is dropped, unless none is
 *   queued. The first one dropped puts [TerminalFramePart.LOST] in its place: the consumer's assembler sees the gap
 *   there and asks for one resync. From then until the terminal's next snapshot, its other frames are dropped too:
 *   an assembler that awaits a snapshot would ignore them anyway.
 * - A snapshot is never dropped, so the answer to every resync reaches the assembler: its part 0, and each later part
 *   in turn (a part sent again, out of order or after the snapshot is complete follows the bound like a delta). Kept,
 *   its part 0 removes every frame of the terminal still queued: a snapshot replaces the screen and the history
 *   (PROTOCOL.md 11.6), so at most one snapshot of the view is ever queued.
 *
 * The frames of any other terminal, which the client ignores (11.1), are kept while they fit the bound and dropped
 * when they do not, with no LOST part, and leave no state behind, so a host that names many terminals grows nothing.
 * [TerminalViewPush.Opened] (one per open the phone sent) and the viewed terminal's [TerminalViewPush.Ended] are never
 * dropped, and weigh nothing. An Ended of any other terminal, which the client ignores too, is kept only while fewer
 * than [MAX_QUEUED_OTHER_ENDS] such are queued, so a host that streams `terminal.view.ended` while nobody collects
 * grows nothing either (re-review B).
 *
 * A frame's weight is about the size of its JSON: the UTF-8 bytes of its texts, counted exactly, and a fixed estimate
 * for the rest. So the frames queued weigh at most [maxQueuedWeight] plus one snapshot of each view opened while the
 * consumer lagged (the phone opens views, one at a time). PROTOCOL.md 11.4 caps a snapshot at 256 parts of one frame
 * each; a snapshot of the largest grid a phone asks for, 300 × 120 with 240 history rows, is far smaller. Decoded, a
 * frame takes about 1 to 3 times its weight in memory (the most for many one-cell runs: an object and a string per
 * run), so the bound holds a session's queued terminal output to about 2 to 6 MiB, plus one snapshot of each view
 * opened while the consumer lags.
 *
 * A collector cancelled while it waits, or while it handles a push, takes nothing more: what was queued stays for the
 * next one. A collector working through a backlog yields after [PUSHES_PER_TURN] pushes or about 4 ms
 * ([NANOS_PER_TURN]), whichever comes first, before its next take: the collector's code never suspends, so without it a
 * flood that the reader keeps up would hold the collector's thread (the phone's main thread) until the bound trips. The
 * iPhone's pushes hop through the main actor one by one, which gives its run loop the same turns.
 */
class TerminalPushQueue(private val maxQueuedWeight: Int = MAX_QUEUED_WEIGHT) {
    companion object {
        /** About 2 MiB of frame JSON: a snapshot with its whole history fill (at most 262 144 bytes) fits many times. */
        const val MAX_QUEUED_WEIGHT = 2_097_152

        /** At most this many Ended pushes of terminals other than the one viewed are queued at once. */
        const val MAX_QUEUED_OTHER_ENDS = 16

        /** A collector hands its thread back after this many pushes in a row, or [NANOS_PER_TURN], whichever comes first. */
        const val PUSHES_PER_TURN = 16
        const val NANOS_PER_TURN = 4_000_000L
    }

    /** [otherEnd]: an Ended of a terminal other than the one viewed, counted in [otherEnds] while it is queued. */
    private class Entry(val push: TerminalViewPush, val weight: Int, val otherEnd: Boolean = false)

    /** The frame of a terminal whose parts are arriving; [next] is the index of the part it lacks first. */
    private class Arriving(val revision: Long, val parts: Int, val snapshot: Boolean) {
        var kept = true
        var next = 1
    }

    private val lock = Any()

    // Guarded by lock.
    private val entries = ArrayDeque<Entry>()
    private var weight = 0
    private var dropped = 0L
    private var closed = false
    private var viewing: String? = null

    /** The view's LOST part is queued (or was taken), and no snapshot of it was kept since. */
    private var viewLost = false

    /** The view's frame whose parts are arriving. */
    private var viewArriving: Arriving? = null

    /** How many queued Ended pushes are of a terminal other than the one viewed. */
    private var otherEnds = 0

    /** A token after each offer; a collector waits on it only when nothing is queued. */
    private val wake = Channel<Unit>(Channel.CONFLATED)

    /**
     * The pushes in the order offered, less the frames dropped or replaced. One collector at a time; a later collector
     * goes on where the one before stopped. Completes after [close], once the queued pushes are taken.
     *
     * A push taken for a collector is handed straight to its code, with no cancellation check in between (a `flow {}`
     * builder would check), so a collector cancelled from another thread loses no push, a LOST part included. A
     * cancelled collector takes no further push: the check comes before each take. Collect it directly: nothing built
     * on `flow {}` or on a channel (`transform`, `buffer`, `flowOn`, `shareIn`, `produceIn`) between this and the
     * assembler, which can lose what it holds at a cancel.
     */
    val pushes: Flow<TerminalViewPush> = object : Flow<TerminalViewPush> {
        override suspend fun collect(collector: FlowCollector<TerminalViewPush>) = deliver(collector)
    }

    private suspend fun deliver(collector: FlowCollector<TerminalViewPush>) {
        var handed = 0
        var since = System.nanoTime()
        while (true) {
            // A backlog hands the thread back now and then (the phone's main thread draws and takes touches meanwhile):
            // before a take, so a collector cancelled there leaves the rest queued.
            if (handed >= PUSHES_PER_TURN || System.nanoTime() - since >= NANOS_PER_TURN) {
                yield()
                handed = 0
                since = System.nanoTime()
            }
            // Before the take, never between the take and the emit: a cancelled collector leaves the rest queued.
            currentCoroutineContext().ensureActive()
            val entry = synchronized(lock) {
                entries.removeFirstOrNull()?.also { taken ->
                    weight -= taken.weight
                    if (taken.otherEnd) otherEnds -= 1
                } ?: if (closed) return else null
            }
            if (entry != null) {
                collector.emit(entry.push)
                handed += 1
                continue
            }
            try {
                wake.receiveCatching()
            } catch (e: CancellationException) {
                // The wake-up may have been this collector's: pass it on to one that waits beside it.
                if (synchronized(lock) { entries.isNotEmpty() }) wake.trySend(Unit)
                throw e
            }
            // It waited: the thread was free meanwhile.
            handed = 0
            since = System.nanoTime()
        }
    }

    /** Queues [push], or drops it by the rules above. Never suspends; ignored after [close]. */
    fun offer(push: TerminalViewPush) {
        var lostNow = false
        synchronized(lock) {
            if (closed) return
            when (push) {
                is TerminalViewPush.Opened -> {
                    view(push.terminalId)
                    add(push, 0)
                }
                is TerminalViewPush.Ended -> when {
                    viewing == push.terminalId -> {
                        view(null)
                        add(push, 0)
                    }
                    otherEnds >= MAX_QUEUED_OTHER_ENDS -> Unit
                    else -> {
                        otherEnds += 1
                        add(push, 0, otherEnd = true)
                    }
                }
                is TerminalViewPush.Frame -> lostNow = offerFrame(push)
            }
        }
        if (lostNow) LinkLog.event("client dropped terminal frames over the bound")
    }

    /** Completes [pushes] once the queued pushes are taken. Idempotent. */
    fun close() {
        synchronized(lock) {
            closed = true
            view(null)
        }
        wake.close()
    }

    /** The weight of the frames queued. For tests. */
    internal val queuedWeight: Int get() = synchronized(lock) { weight }

    /** How many pushes are queued, markers included. For tests. */
    internal val queuedPushes: Int get() = synchronized(lock) { entries.size }

    /** How many frames were dropped so far (replaced ones not counted). For tests. */
    internal val droppedFrames: Long get() = synchronized(lock) { dropped }

    /** Caller holds [lock]. True when this drop queued a LOST part. */
    private fun offerFrame(push: TerminalViewPush.Frame): Boolean {
        val id = push.terminalId
        val part = push.part
        val w = part.weight()
        if (id != viewing) {
            if (weight > 0 && weight + w > maxQueuedWeight) {
                dropped += 1
            } else {
                add(push, w)
            }
            return false
        }
        // A part belongs to the frame arriving only as the part it lacks next: a part sent again, out of order or
        // after the frame is complete is no part of it, and follows the bound like a delta.
        val frame = if (part.part == 0) {
            Arriving(part.revision, part.parts, part.head?.kind == TerminalFrameKind.SNAPSHOT).also { viewArriving = it }
        } else {
            viewArriving?.takeIf { it.revision == part.revision && it.parts == part.parts && it.next == part.part }
                ?.also { it.next += 1 }
        }
        if (frame != null && frame.next == frame.parts) viewArriving = null
        val snapshot = frame?.snapshot == true
        // The rest of a frame whose first part went, and what waits for a snapshot, go without another marker.
        if ((frame != null && !frame.kept) || (!snapshot && viewLost)) return drop(frame, markLost = false)
        if (!snapshot && weight > 0 && weight + w > maxQueuedWeight) return drop(frame, markLost = true)
        if (snapshot && part.part == 0) {
            replaceFramesOf(id)
            viewLost = false
        }
        add(push, w)
        return false
    }

    /** Caller holds [lock]. Drops a part of the view's frame; with [markLost], queues its LOST part unless it has one. */
    private fun drop(frame: Arriving?, markLost: Boolean): Boolean {
        dropped += 1
        frame?.kept = false
        val id = viewing
        if (!markLost || viewLost || id == null) return false
        viewLost = true
        add(TerminalViewPush.Frame(id, TerminalFramePart.LOST), 0)
        return true
    }

    /** Caller holds [lock]. Removes every queued frame of [terminalId]: a snapshot of it replaces them all. */
    private fun replaceFramesOf(terminalId: String) {
        val iterator = entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            if (entry.push is TerminalViewPush.Frame && entry.push.terminalId == terminalId) {
                weight -= entry.weight
                iterator.remove()
            }
        }
    }

    /** Caller holds [lock]. A new view, or none: what was known of the old view's frames no longer holds. */
    private fun view(terminalId: String?) {
        viewing = terminalId
        viewLost = false
        viewArriving = null
    }

    /** Caller holds [lock]. */
    private fun add(push: TerminalViewPush, w: Int, otherEnd: Boolean = false) {
        entries.addLast(Entry(push, w, otherEnd))
        weight += w
        wake.trySend(Unit)
    }
}

/**
 * What a part weighs in [TerminalPushQueue]: the UTF-8 bytes of its run texts, counted exactly, plus a fixed estimate
 * for the JSON around them (64 per part, 48 per style, 2 560 for a palette, 16 per line, 24 per run). About the
 * size of the part's JSON.
 */
private fun TerminalFramePart.weight(): Int {
    var w = 64 + styles.size * 48 + if (head?.palette != null) 256 * 10 else 0
    for (line in lines) {
        w += 16
        for (run in line.runs) w += 24 + utf8Bytes(run.text)
    }
    return w
}

/** The UTF-8 size of [text], without encoding it. A lone surrogate counts 3, as its replacement character does. */
private fun utf8Bytes(text: String): Int {
    var n = 0
    var i = 0
    while (i < text.length) {
        val c = text[i]
        n += when {
            c.code < 0x80 -> 1
            c.code < 0x800 -> 2
            Character.isHighSurrogate(c) && i + 1 < text.length && Character.isLowSurrogate(text[i + 1]) -> {
                i += 1
                4
            }
            else -> 3
        }
        i += 1
    }
    return n
}
