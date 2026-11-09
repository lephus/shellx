package com.shellx.core.testing

import com.shellx.core.voice.SpeechEngine
import com.shellx.core.voice.SpeechRunId
import com.shellx.core.voice.SpeechRunSlot
import com.shellx.core.voice.SpeechStartException
import com.shellx.core.voice.VoiceLanguage
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.yield

/**
 * A [SpeechEngine] the test drives (port of FakeTranscriber), following the real recognizers' rule through a
 * [SpeechRunSlot]: one run holds the microphone; the newest start wins; a start that was overtaken, or whose run was
 * cancelled while it started, never takes the microphone; a granted start tears down the run it replaces (its channel
 * closes).
 *
 * [say] sends the words heard so far on the run that holds the microphone; [fail] and [endStream] end it by
 * themselves (an error, a time limit); [finalText] is what `finish` returns (by default the last words said). Records
 * each start, granted claim, finish and cancel, and can hold starts until the test releases them, all at once or one
 * run at a time. Thread-safe.
 */
class FakeTranscriber(private val slot: SpeechRunSlot = SpeechRunSlot()) : SpeechEngine {
    /** One `start` call. */
    data class Start(val run: SpeechRunId, val language: VoiceLanguage, val contextualStrings: List<String>)

    private val lock = Any()
    private val streams = HashMap<SpeechRunId, Channel<String>>()
    private var lastSaid = ""
    private var finalAnswer: String? = null
    private var storedStartError: Throwable? = null
    private val startList = mutableListOf<Start>()
    private val grantList = mutableListOf<SpeechRunId>()
    private var finishCount = 0
    private val cancelList = mutableListOf<SpeechRunId>()
    private var holding = false
    private val heldStarts = mutableListOf<Pair<SpeechRunId, CompletableDeferred<Unit>>>()

    /** Every start, in order. */
    val starts: List<Start> get() = synchronized(lock) { startList.toList() }

    /** The runs whose start took the microphone, in order. */
    val grantedRuns: List<SpeechRunId> get() = synchronized(lock) { grantList.toList() }

    val finishCalls: Int get() = synchronized(lock) { finishCount }

    /** Every `cancel`, whatever run it named. */
    val cancelCalls: Int get() = synchronized(lock) { cancelList.size }

    /** The runs `cancel` named, in order. */
    val cancelledRuns: List<SpeechRunId> get() = synchronized(lock) { cancelList.toList() }

    /** The run that holds the microphone. */
    val activeRun: SpeechRunId? get() = slot.active

    /** A run holds the microphone and its channel is open. */
    val isRunning: Boolean
        get() {
            val active = slot.active ?: return false
            return synchronized(lock) { streams[active] != null }
        }

    /** Starts held by [holdStarts]. */
    val startsWaiting: Int get() = synchronized(lock) { heldStarts.size }

    /** What `finish` returns; null returns the last words said. */
    var finalText: String?
        get() = synchronized(lock) { finalAnswer }
        set(value) { synchronized(lock) { finalAnswer = value } }

    /** When set, `start` throws it (before taking the microphone). */
    var startError: Throwable?
        get() = synchronized(lock) { storedStartError }
        set(value) { synchronized(lock) { storedStartError = value } }

    /** Holds every later `start` (after it is recorded and has begun) until it is released. */
    fun holdStarts() {
        synchronized(lock) { holding = true }
    }

    /** Lets every held start through, oldest first, and stops holding. */
    fun releaseStarts() {
        val held = synchronized(lock) {
            holding = false
            heldStarts.map { it.second }.also { heldStarts.clear() }
        }
        for (start in held) start.complete(Unit)
    }

    /** Lets the held start of [run] through; the others stay held. */
    fun releaseStart(run: SpeechRunId) {
        val held = synchronized(lock) {
            val index = heldStarts.indexOfFirst { it.first == run }
            if (index < 0) null else heldStarts.removeAt(index).second
        }
        held?.complete(Unit)
    }

    /** Sends [text] as everything the run holding the microphone heard so far. */
    fun say(text: String) {
        val open = synchronized(lock) {
            val active = slot.active ?: return
            val current = streams[active] ?: return
            lastSaid = text
            current
        }
        open.trySend(text)
    }

    /** Ends the active run's channel with [error], as a recognizer that fails does. */
    fun fail(error: Throwable) {
        endActive()?.close(error)
    }

    /** Ends the active run's channel without an error, as a recognizer that reaches its time limit does. */
    fun endStream() {
        endActive()?.close()
    }

    private fun endActive(): Channel<String>? {
        val active = slot.active ?: return null
        if (!slot.ended(active)) return null
        return synchronized(lock) { streams.remove(active) }
    }

    private fun close(run: SpeechRunId) {
        synchronized(lock) { streams.remove(run) }?.close()
    }

    override suspend fun start(run: SpeechRunId, language: VoiceLanguage, contextualStrings: List<String>): ReceiveChannel<String> {
        slot.begin(run)
        val hold = synchronized(lock) {
            startList += Start(run, language, contextualStrings)
            if (holding) CompletableDeferred<Unit>().also { heldStarts += run to it } else null
        }
        if (hold != null) {
            try {
                hold.await()
            } finally {
                synchronized(lock) { heldStarts.removeAll { it.second === hold } }
            }
        }
        startError?.let { throw it }
        val channel = Channel<String>(Channel.UNLIMITED)
        synchronized(lock) { streams[run] = channel }
        val handlers = SpeechRunSlot.Handlers(
            finish = {
                val text = synchronized(lock) { finalAnswer ?: lastSaid }
                close(run)
                text
            },
            teardown = { close(run) },
        )
        when (val claim = slot.claim(run, handlers)) {
            // Overtaken or cancelled while starting: never takes the microphone.
            SpeechRunSlot.Claim.Refused -> close(run)
            is SpeechRunSlot.Claim.Granted -> {
                synchronized(lock) {
                    grantList += run
                    lastSaid = ""
                }
                claim.replaced?.teardown?.invoke()
            }
        }
        return channel
    }

    override suspend fun finish(run: SpeechRunId): String {
        synchronized(lock) { finishCount += 1 }
        return slot.takeForFinish(run)?.finish?.invoke() ?: ""
    }

    override suspend fun cancel(run: SpeechRunId) {
        synchronized(lock) { cancelList += run }
        slot.cancel(run)?.teardown?.invoke()
    }
}

/**
 * An engine whose `cancel` suspends once (a real recognizer's teardown hops to the main thread, or waits for its
 * callback) before it tears the run down: a give-back that is cancelled at that suspension never releases the mic.
 */
class HoppingCancel(private val base: FakeTranscriber) : SpeechEngine by base {
    override suspend fun cancel(run: SpeechRunId) {
        yield()
        base.cancel(run)
    }
}

/**
 * 3E's planned on-device engine (3E plan, its start): it claims the mic, then waits for the recognizer to be ready, and
 * its teardown does not end that wait. [failReady] ends it as the readiness timeout does: the start then throws
 * [SpeechStartException.Recognizer]. Thread-safe.
 */
class NotReadyPrimary(private val slot: SpeechRunSlot) : SpeechEngine {
    private val ready = CompletableDeferred<Unit>()

    fun failReady() {
        ready.complete(Unit)
    }

    override suspend fun start(run: SpeechRunId, language: VoiceLanguage, contextualStrings: List<String>): ReceiveChannel<String> {
        slot.begin(run)
        val channel = Channel<String>(Channel.UNLIMITED)
        val claim = slot.claim(run, SpeechRunSlot.Handlers(finish = { channel.close(); "" }, teardown = { channel.close() }))
        if (claim is SpeechRunSlot.Claim.Refused) {
            channel.close()
            return channel
        }
        ready.await()
        throw SpeechStartException.Recognizer(IllegalStateException("not_ready"))
    }

    override suspend fun finish(run: SpeechRunId): String = slot.takeForFinish(run)?.finish?.invoke() ?: ""

    override suspend fun cancel(run: SpeechRunId) {
        slot.cancel(run)?.teardown?.invoke()
    }
}
