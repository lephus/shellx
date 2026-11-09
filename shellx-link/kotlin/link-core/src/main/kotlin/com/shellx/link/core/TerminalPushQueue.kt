package com.shellx.link.core

import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * The terminal pushes of one session, between the reader that takes them off the circuit and their consumer, bounded
 * (plan 3G Task 4b, contracts §24). [offer] never suspends, so the session's reader never waits on a slow consumer:
 * pings, call answers and the other pushes keep flowing behind a terminal flood.
 *
 * The rules, per terminal:
 * - A delta or history frame that would take the frames queued past [maxQueuedWeight] is dropped, unless none is
 *   queued. The first one dropped puts [TerminalFramePart.LOST] in its place: the consumer's assembler sees the gap
 *   there and asks for one resync. From then until the terminal's next snapshot, its other frames are dropped too:
 *   an assembler that awaits a snapshot would ignore them anyway.
 * - A snapshot of the terminal viewed (the one of the last [TerminalViewPush.Opened]) is never dropped, so the answer
 *   to every resync reaches the assembler. Kept, it removes every frame of its terminal still queued: a snapshot
 *   replaces the screen and the history (PROTOCOL.md 11.6). So at most one snapshot per terminal is ever queued.
 *   Another terminal's snapshot follows the bound like a delta.
 * - [TerminalViewPush.Opened] and [TerminalViewPush.Ended] are never dropped and weigh nothing.
 *
 * A frame's weight is about the size of its JSON: the UTF-8 bytes of its texts, counted exactly, and a fixed estimate
 * for the rest. So the frames queued weigh at most [maxQueuedWeight] plus one snapshot of the terminal viewed, which
 * PROTOCOL.md 11.4 caps at 256 parts of one frame each (a snapshot of the largest grid a phone asks for, 300 × 120 with
 * 240 history rows, is far smaller). Decoded, a frame takes about 1 to 3 times its weight in memory (the most for many
 * one-cell runs: an object and a string per run), so the bound holds a session's queued terminal output to about 2 to
 * 6 MiB, plus that one snapshot.
 *
 * A collector cancelled while it waits takes nothing: what was queued stays for the next one.
 */
class TerminalPushQueue(private val maxQueuedWeight: Int = MAX_QUEUED_WEIGHT) {
    companion object {
        /** About 2 MiB of frame JSON: a snapshot with its whole history fill (at most 262 144 bytes) fits many times. */
        const val MAX_QUEUED_WEIGHT = 2_097_152
    }

    private class Entry(val push: TerminalViewPush, val weight: Int)

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
    private val lost = HashSet<String>()
    private val arriving = HashMap<String, Arriving>()

    /** A token after each offer; a collector waits on it only when nothing is queued. */
    private val wake = Channel<Unit>(Channel.CONFLATED)

    /**
     * The pushes in the order offered, less the frames dropped or replaced. One collector at a time; a later collector
     * goes on where the one before stopped. Completes after [close], once the queued pushes are taken.
     */
    val pushes: Flow<TerminalViewPush> = flow {
        while (true) {
            val entry = synchronized(lock) {
                entries.removeFirstOrNull()?.also { weight -= it.weight } ?: if (closed) return@flow else null
            }
            if (entry != null) emit(entry.push) else wake.receiveCatching()
        }
    }

    /** Queues [push], or drops it by the rules above. Never suspends; ignored after [close]. */
    fun offer(push: TerminalViewPush) {
        var lostNow = false
        synchronized(lock) {
            if (closed) return
            when (push) {
                is TerminalViewPush.Opened -> {
                    viewing = push.terminalId
                    forget(push.terminalId)
                    add(push, 0)
                }
                is TerminalViewPush.Ended -> {
                    if (viewing == push.terminalId) viewing = null
                    forget(push.terminalId)
                    add(push, 0)
                }
                is TerminalViewPush.Frame -> lostNow = offerFrame(push)
            }
        }
        if (lostNow) LinkLog.event("client dropped terminal frames over the bound")
    }

    /** Completes [pushes] once the queued pushes are taken. Idempotent. */
    fun close() {
        synchronized(lock) { closed = true }
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
        // A part belongs to the frame arriving only as the part it lacks next: a part sent again, out of order or
        // after the frame is complete is no part of it, and follows the bound like a delta.
        val frame = if (part.part == 0) {
            Arriving(part.revision, part.parts, part.head?.kind == TerminalFrameKind.SNAPSHOT).also { arriving[id] = it }
        } else {
            arriving[id]?.takeIf { it.revision == part.revision && it.parts == part.parts && it.next == part.part }
                ?.also { it.next += 1 }
        }
        if (frame != null && frame.next == frame.parts) arriving.remove(id)
        val snapshot = frame?.snapshot == true
        // The rest of a frame whose first part went, and what waits for a snapshot, go without another marker.
        if ((frame != null && !frame.kept) || (!snapshot && id in lost)) return drop(frame, null)
        val w = part.weight()
        if (!(snapshot && id == viewing) && weight > 0 && weight + w > maxQueuedWeight) return drop(frame, id)
        if (snapshot && part.part == 0) {
            replaceFramesOf(id)
            lost.remove(id)
        }
        add(push, w)
        return false
    }

    /** Caller holds [lock]. Drops a frame part; with [markLost], queues the terminal's LOST part unless it has one. */
    private fun drop(frame: Arriving?, markLost: String?): Boolean {
        dropped += 1
        frame?.kept = false
        if (markLost == null || !lost.add(markLost)) return false
        add(TerminalViewPush.Frame(markLost, TerminalFramePart.LOST), 0)
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

    /** Caller holds [lock]. A new view of [terminalId], or its end: what was known of its frames no longer holds. */
    private fun forget(terminalId: String) {
        lost.remove(terminalId)
        arriving.remove(terminalId)
    }

    /** Caller holds [lock]. */
    private fun add(push: TerminalViewPush, w: Int) {
        entries.addLast(Entry(push, w))
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
