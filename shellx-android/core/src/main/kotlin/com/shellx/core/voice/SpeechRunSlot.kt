package com.shellx.core.voice

/**
 * The microphone holds one dictation at a time; this decides which. Every [SpeechEngine] that shares the microphone
 * shares one slot.
 *
 * - [begin] marks a start: the newest start is the only one that may take the microphone. The outermost engine begins
 *   a press at its entry, before any suspension; beginning the same run again later changes nothing.
 * - [claim] is asked right before the audio starts. A start that a newer one overtook, or whose run was cancelled
 *   while it started (or before), is refused: it cleans up after itself and leaves the active run alone. A granted
 *   claim hands back the run it replaced, which the caller tears down.
 * - [cancel], [takeForFinish] and [ended] act on the run they name only.
 *
 * Thread-safe (`synchronized`): every call is short and never suspends while holding the lock.
 */
class SpeechRunSlot {
    /** How an engine finishes or tears down the run it claimed with. */
    class Handlers(val finish: suspend () -> String, val teardown: suspend () -> Unit)

    sealed interface Claim {
        /** The run holds the microphone now; tear down [replaced] (the run it took over from), if any. */
        class Granted(val replaced: Handlers?) : Claim

        /** Overtaken or cancelled: never start the audio; clean up and close the run's channel. */
        data object Refused : Claim
    }

    private class Current(val run: SpeechRunId, val handlers: Handlers)

    private val lock = Any()
    private var newest: SpeechRunId? = null
    private val begun = ArrayDeque<SpeechRunId>()
    private var current: Current? = null
    private val cancelled = ArrayDeque<SpeechRunId>()

    /** The run that holds the microphone. */
    val active: SpeechRunId? get() = synchronized(lock) { current?.run }

    fun isActive(run: SpeechRunId): Boolean = synchronized(lock) { current?.run == run }

    /** A start of [run] began; it is the newest start now, unless [run] began before. Beginning a run again (an inner
     *  engine after the router, a fallback retry) never makes an older run the newest again. */
    fun begin(run: SpeechRunId) {
        synchronized(lock) {
            if (run in begun) return
            begun.addLast(run)
            while (begun.size > BEGIN_MEMORY) begun.removeFirst()
            newest = run
        }
    }

    /** [run] is ready to take the microphone. */
    fun claim(run: SpeechRunId, handlers: Handlers): Claim = synchronized(lock) {
        if (newest != run || run in cancelled) return Claim.Refused
        val replaced = current?.handlers
        current = Current(run, handlers)
        Claim.Granted(replaced)
    }

    /** Cancels [run]: its handlers when it holds the microphone (the caller tears it down); otherwise null, and a start
     *  of [run] still under way (or not yet begun) will be refused. */
    fun cancel(run: SpeechRunId): Handlers? = synchronized(lock) {
        val holder = current
        if (holder != null && holder.run == run) {
            current = null
            return holder.handlers
        }
        if (run !in cancelled) {
            cancelled.addLast(run)
            while (cancelled.size > CANCEL_MEMORY) cancelled.removeFirst()
        }
        null
    }

    /** [run] is released to finish: its handlers when it holds the microphone (it no longer does). */
    fun takeForFinish(run: SpeechRunId): Handlers? = synchronized(lock) {
        val holder = current
        if (holder == null || holder.run != run) return null
        current = null
        holder.handlers
    }

    /** [run] ended by itself (an error, a time limit). True when it held the microphone until now: the caller gives
     *  the audio back. */
    fun ended(run: SpeechRunId): Boolean = synchronized(lock) {
        if (current?.run != run) return false
        current = null
        true
    }

    private companion object {
        /** Cancels remembered for runs that are not active (bounded, oldest dropped). */
        const val CANCEL_MEMORY = 32

        /** Runs remembered as begun, so beginning one again changes nothing (bounded, oldest dropped). */
        const val BEGIN_MEMORY = 32
    }
}
