package com.shellx.app.testing

import com.shellx.core.voice.SpeechEngine
import com.shellx.core.voice.SpeechRunId
import com.shellx.core.voice.SpeechRunSlot
import com.shellx.core.voice.VoiceLanguage
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ReceiveChannel

/**
 * A [SpeechEngine] the test drives (a small port of 3C's core-test FakeTranscriber, which `:app` cannot see). It
 * follows the real recognizers' rule through a [SpeechRunSlot]: one run holds the microphone, the newest start wins,
 * and a granted start tears down the run it replaces.
 *
 * [say] sends the whole text heard so far to the run that holds the microphone; [end] ends that run by itself;
 * [finalText] is what `finish` answers (null: the last text said). Records every start, finish and cancel. Main
 * thread.
 */
class FakeSpeechEngine(private val slot: SpeechRunSlot = SpeechRunSlot()) : SpeechEngine {
    data class Start(val run: SpeechRunId, val language: VoiceLanguage, val contextualStrings: List<String>)

    private val channels = HashMap<SpeechRunId, Channel<String>>()
    private val startList = mutableListOf<Start>()
    private val finishList = mutableListOf<SpeechRunId>()
    private val cancelList = mutableListOf<SpeechRunId>()
    private var lastSaid = ""

    val starts: List<Start> get() = startList.toList()

    /** The runs `finish` named, in order. */
    val finishCalls: List<SpeechRunId> get() = finishList.toList()

    /** The runs `cancel` named, in order. */
    val cancelCalls: List<SpeechRunId> get() = cancelList.toList()

    /** The run that holds the microphone. */
    val activeRun: SpeechRunId? get() = slot.active

    /** What `finish` answers for the active run; null answers the last text said. */
    var finalText: String? = null

    override suspend fun start(run: SpeechRunId, language: VoiceLanguage, contextualStrings: List<String>): ReceiveChannel<String> {
        slot.begin(run)
        startList += Start(run, language, contextualStrings)
        val channel = Channel<String>(Channel.CONFLATED)
        val handlers = SpeechRunSlot.Handlers(finish = { finishRun(run) }, teardown = { tearDown(run) })
        when (val claim = slot.claim(run, handlers)) {
            SpeechRunSlot.Claim.Refused -> channel.close()
            is SpeechRunSlot.Claim.Granted -> {
                channels[run] = channel
                lastSaid = ""
                claim.replaced?.teardown?.invoke()
            }
        }
        return channel
    }

    override suspend fun finish(run: SpeechRunId): String {
        finishList += run
        return slot.takeForFinish(run)?.finish?.invoke() ?: ""
    }

    override suspend fun cancel(run: SpeechRunId) {
        cancelList += run
        slot.cancel(run)?.teardown?.invoke()
    }

    /** [text] is everything the active run heard so far. */
    fun say(text: String) {
        val active = slot.active ?: return
        val channel = channels[active] ?: return
        lastSaid = text
        channel.trySend(text)
    }

    /** The active run's channel ends by itself, with [error] when there is one. */
    fun end(error: Throwable? = null) {
        val active = slot.active ?: return
        channels.remove(active)?.close(error)
        slot.ended(active)
    }

    private fun finishRun(run: SpeechRunId): String {
        val text = finalText ?: lastSaid
        channels.remove(run)?.close()
        return text
    }

    private fun tearDown(run: SpeechRunId) {
        channels.remove(run)?.close()
    }
}
