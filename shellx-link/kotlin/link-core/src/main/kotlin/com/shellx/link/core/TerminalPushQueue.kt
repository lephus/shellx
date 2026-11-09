package com.shellx.link.core

import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.receiveAsFlow

/**
 * The terminal pushes of one session, between the reader that takes them off the circuit and their one consumer,
 * bounded (plan 3G Task 4b, contracts §24). [offer] never suspends, so the session's reader never waits on a slow
 * consumer and pings, call answers and the other pushes keep flowing behind a terminal flood.
 *
 * Frames are counted by their weight, about the UTF-8 bytes of their JSON. A frame that would take the frames queued
 * past [maxQueuedWeight] is dropped, unless none is queued (one frame always fits). The first frame dropped of a
 * terminal since one of its frames was last kept queues [TerminalFramePart.LOST] in its place, so the consumer's
 * assembler sees exactly where the frames went missing and asks for one resync; the host answers with a snapshot.
 * [TerminalViewPush.Opened] and [TerminalViewPush.Ended] are never dropped and weigh nothing.
 */
class TerminalPushQueue(private val maxQueuedWeight: Int = MAX_QUEUED_WEIGHT) {
    companion object {
        /** About 2 MiB of frame JSON: a snapshot with its whole history fill (at most 262 144 bytes) fits many times. */
        const val MAX_QUEUED_WEIGHT = 2_097_152
    }

    private class Entry(val push: TerminalViewPush, val weight: Int)

    private val lock = Any()
    private val entries = Channel<Entry>(Channel.UNLIMITED)

    // Guarded by lock.
    private var weight = 0
    private var count = 0
    private var dropped = 0L
    private val lost = HashSet<String>()

    /** The pushes in the order offered, less the frames dropped. Single consumer; completes after [close]. */
    val pushes: Flow<TerminalViewPush> = entries.receiveAsFlow().map { entry ->
        synchronized(lock) {
            weight -= entry.weight
            count -= 1
        }
        entry.push
    }

    /** Queues [push], or drops it when it is a frame over the bound. Never suspends; ignored after [close]. */
    fun offer(push: TerminalViewPush) {
        synchronized(lock) {
            val w = (push as? TerminalViewPush.Frame)?.part?.weight() ?: 0
            if (push is TerminalViewPush.Frame) {
                if (weight > 0 && weight + w > maxQueuedWeight) {
                    dropped += 1
                    if (lost.add(push.terminalId)) {
                        LinkLog.event("client dropped terminal frames over the bound")
                        enqueue(TerminalViewPush.Frame(push.terminalId, TerminalFramePart.LOST), 0)
                    }
                    return
                }
                lost.remove(push.terminalId)
            } else if (push is TerminalViewPush.Opened) {
                lost.remove(push.terminalId)
            }
            enqueue(push, w)
        }
    }

    /** Completes [pushes] once the queued pushes are taken. Idempotent. */
    fun close() {
        entries.close()
    }

    /** The weight of the frames queued. For tests. */
    internal val queuedWeight: Int get() = synchronized(lock) { weight }

    /** How many pushes are queued, markers included. For tests. */
    internal val queuedPushes: Int get() = synchronized(lock) { count }

    /** How many frames were dropped so far. For tests. */
    internal val droppedFrames: Long get() = synchronized(lock) { dropped }

    /** Caller holds [lock]. */
    private fun enqueue(push: TerminalViewPush, w: Int) {
        if (entries.trySend(Entry(push, w)).isSuccess) {
            weight += w
            count += 1
        }
    }
}

/** About the UTF-8 bytes of the part's JSON: what bounds [TerminalPushQueue]. */
private fun TerminalFramePart.weight(): Int {
    var w = 64 + styles.size * 48 + if (head?.palette != null) 256 * 10 else 0
    for (line in lines) {
        w += 16
        for (run in line.runs) w += 24 + run.text.length
    }
    return w
}
