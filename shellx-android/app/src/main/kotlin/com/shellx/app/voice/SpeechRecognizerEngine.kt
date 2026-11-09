package com.shellx.app.voice

import android.annotation.SuppressLint
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import com.shellx.core.platform.CoreLog
import com.shellx.core.voice.SpeechEngine
import com.shellx.core.voice.SpeechRunId
import com.shellx.core.voice.SpeechRunSlot
import com.shellx.core.voice.SpeechStartException
import com.shellx.core.voice.SpeechTimeouts
import com.shellx.core.voice.TranscriptAccumulator
import com.shellx.core.voice.VoiceLanguage
import java.io.IOException
import java.util.concurrent.TimeoutException
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/** The intent of one listening segment. */
class RecognizerIntents(private val packageName: String, private val sdkInt: Int = Build.VERSION.SDK_INT) {
    /**
     * ACTION_RECOGNIZE_SPEECH with LANGUAGE_MODEL_FREE_FORM, the language's tag, partial results, one result,
     * EXTRA_PREFER_OFFLINE = [preferOffline] and the calling package; on API 33+ also the biasing strings
     * ([contextualStrings]) and formatting for quality.
     */
    @SuppressLint("InlinedApi") // The two API 33 extras are only put on API 33 and later (sdkInt).
    fun of(language: VoiceLanguage, contextualStrings: List<String>, preferOffline: Boolean): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, language.tag)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, preferOffline)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            if (sdkInt >= 33) {
                putStringArrayListExtra(RecognizerIntent.EXTRA_BIASING_STRINGS, ArrayList(contextualStrings))
                putExtra(RecognizerIntent.EXTRA_ENABLE_FORMATTING, RecognizerIntent.FORMATTING_OPTIMIZE_QUALITY)
            }
        }
}

/**
 * One `android.speech` recognizer as 3C's [SpeechEngine] (the iPhone's LegacyTranscriber and AnalyzerTranscriber).
 * Never logs what it hears.
 *
 * - A run starts its recognizer, then waits at most [READY_TIMEOUT] for it to be ready (ready for speech, speech
 *   began, or a first word). A start error says whose fault it was ([startError]): the recognizer's (the fallback
 *   gives the on-device recognizer up for the language) or the audio's.
 * - Runs go through the [SpeechRunSlot] shared with every other engine of the microphone: a start that was overtaken
 *   or cancelled never takes it, and a granted start tears down the run it replaced.
 * - Android's recognizer ends a segment at every pause. While the user holds the mic, a segment with words starts
 *   listening again on the same recognizer, and the words before the pause stay (RF 5, ledger A-23). A segment with no
 *   words (silence, no match) ends the dictation by itself, keeping the words.
 * - [finish] stops listening and waits for the final result at most [finalTimeout]; [finish] and [cancel] give the
 *   microphone back also when they are cancelled, and never throw for a recognizer error.
 *
 * Every port call and listener callback runs on [main].
 */
class SpeechRecognizerEngine(
    private val kind: RecognizerKind,
    private val slot: SpeechRunSlot,
    private val makePort: () -> RecognizerPort?,
    private val meter: AudioLevelMeter,
    private val intents: RecognizerIntents,
    private val main: CoroutineDispatcher = Dispatchers.Main.immediate,
    private val preferOffline: suspend (VoiceLanguage) -> Boolean = { false },
) : SpeechEngine {
    private enum class State { STARTING, LISTENING, FINISHING, ENDED }

    /** One dictation: its recognizer, what it heard, and where it stands. Main-confined. */
    private inner class Run(val id: SpeechRunId, val port: RecognizerPort, val intent: Intent) {
        val channel = Channel<String>(Channel.CONFLATED)
        val heard = TranscriptAccumulator()
        val ready = CompletableDeferred<Unit>()
        val final = CompletableDeferred<String>()
        var state = State.STARTING

        val listener = object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) = markReady(this@Run)

            override fun onBeginningOfSpeech() = markReady(this@Run)

            override fun onRmsChanged(rmsdB: Float) {
                if (state == State.LISTENING || state == State.FINISHING) meter.update(rmsdB)
            }

            override fun onBufferReceived(buffer: ByteArray?) = Unit

            override fun onEndOfSpeech() = Unit

            override fun onError(error: Int) = failed(this@Run, error)

            override fun onResults(results: Bundle?) = resulted(this@Run, first(results))

            override fun onPartialResults(partialResults: Bundle?) {
                val text = first(partialResults) ?: return
                if (state == State.ENDED) return
                markReady(this@Run)
                channel.trySend(heard.take(text, isFinal = false))
            }

            override fun onEvent(eventType: Int, params: Bundle?) = Unit
        }
    }

    override suspend fun start(run: SpeechRunId, language: VoiceLanguage, contextualStrings: List<String>): ReceiveChannel<String> {
        // Before any suspension: the order of the presses decides which is the newest.
        slot.begin(run)
        return withContext(main) {
            val port = makePort() ?: throw SpeechStartException.Recognizer(IllegalStateException("unavailable"))
            val intent = try {
                intents.of(language, contextualStrings, preferOffline(language))
            } catch (e: Throwable) {
                quietly { port.destroy() }
                throw e
            }
            val r = Run(run, port, intent)
            val handlers = SpeechRunSlot.Handlers(
                finish = { finish(r) },
                teardown = { withContext(NonCancellable + main) { tearDown(r) } },
            )
            when (val claim = slot.claim(run, handlers)) {
                SpeechRunSlot.Claim.Refused -> {
                    // Overtaken or cancelled while it started: never takes the microphone.
                    r.state = State.ENDED
                    quietly { port.destroy() }
                    r.channel.close()
                    return@withContext r.channel
                }
                is SpeechRunSlot.Claim.Granted -> claim.replaced?.teardown?.invoke()
            }
            val ready = try {
                port.start(intent, r.listener)
                withTimeoutOrNull(READY_TIMEOUT) { r.ready.await() }
            } catch (e: CancellationException) {
                // The caller left while the recognizer started: the microphone goes back.
                giveUp(r)
                throw e
            } catch (e: SpeechStartException) {
                giveUp(r)
                throw e
            } catch (e: RuntimeException) {
                giveUp(r)
                CoreLog.log("speech_start_failed ${e.javaClass.simpleName}")
                throw SpeechStartException.Recognizer(e)
            }
            if (ready == null) {
                giveUp(r)
                CoreLog.log("speech_start_timeout")
                throw SpeechStartException.Recognizer(TimeoutException("speech_ready_timeout"))
            }
            // Torn down while it started (cancelled, overtaken or finished): its channel is closed.
            if (!slot.isActive(run)) {
                tearDown(r)
                return@withContext r.channel
            }
            r.channel
        }
    }

    override suspend fun finish(run: SpeechRunId): String = slot.takeForFinish(run)?.finish?.invoke() ?: ""

    override suspend fun cancel(run: SpeechRunId) {
        slot.cancel(run)?.teardown?.invoke()
    }

    // Private

    /** Stops listening and waits for the final result, at most [finalTimeout]; the words heard so far otherwise. The
     *  recognizer is torn down in every case, also when the caller is cancelled. */
    private suspend fun finish(r: Run): String {
        try {
            return withContext(main) {
                if (r.state != State.ENDED) {
                    r.state = State.FINISHING
                    quietly { r.port.stop() }
                }
                withTimeoutOrNull(finalTimeout(kind)) { r.final.await() } ?: r.heard.text
            }
        } finally {
            withContext(NonCancellable + main) { tearDown(r) }
        }
    }

    /** A start that failed after it claimed the microphone: gives the microphone back and tears the run down. */
    private suspend fun giveUp(r: Run) {
        withContext(NonCancellable + main) {
            slot.ended(r.id)
            tearDown(r)
        }
    }

    /** The recognizer is ready (ready for speech, speech began, or a first word): errors from now on end the
     *  dictation, they no longer fail its start. */
    private fun markReady(r: Run) {
        if (r.state == State.STARTING) r.state = State.LISTENING
        r.ready.complete(Unit)
    }

    private fun resulted(r: Run, segment: String?) {
        if (r.state == State.ENDED) return
        markReady(r)
        r.channel.trySend(r.heard.take(segment ?: "", isFinal = true))
        when (r.state) {
            State.FINISHING -> {
                r.final.complete(r.heard.text)
                tearDown(r)
            }
            // The user paused but still holds: listen again on the same recognizer (RF 5).
            State.LISTENING -> if (segment.isNullOrBlank()) {
                endByItself(r, null)
            } else {
                try {
                    r.port.start(r.intent, r.listener)
                } catch (e: RuntimeException) {
                    CoreLog.log("speech_restart_failed ${e.javaClass.simpleName}")
                    endByItself(r, null)
                }
            }
            State.STARTING, State.ENDED -> Unit
        }
    }

    private fun failed(r: Run, code: Int) {
        when (r.state) {
            State.STARTING -> {
                CoreLog.log("speech_start_error code=$code")
                r.ready.completeExceptionally(startError(code))
            }
            State.FINISHING -> {
                r.final.complete(r.heard.text)
                tearDown(r)
            }
            State.LISTENING -> {
                // Words heard are always kept; an error before any word ends the dictation with it.
                val error = when {
                    code == SpeechRecognizer.ERROR_NO_MATCH || code == SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> null
                    r.heard.text.isBlank() -> IOException("speech_error_$code")
                    else -> null
                }
                if (error != null) CoreLog.log("speech_error code=$code")
                endByItself(r, error)
            }
            State.ENDED -> Unit
        }
    }

    /** The run ended by itself (silence, an error): its channel closes, and the microphone is given back. */
    private fun endByItself(r: Run, error: Throwable?) {
        if (r.state == State.ENDED) return
        r.state = State.ENDED
        r.channel.close(error)
        meter.reset()
        r.final.complete(r.heard.text)
        r.ready.complete(Unit)
        slot.ended(r.id)
        // The recognizer is this run's alone.
        quietly { r.port.destroy() }
    }

    /** Cancel, a newer run took the microphone, or the finish is done: stops the recognizer once. */
    private fun tearDown(r: Run) {
        if (r.state == State.ENDED) return
        r.state = State.ENDED
        quietly { r.port.cancel() }
        quietly { r.port.destroy() }
        r.channel.close()
        meter.reset()
        r.final.complete(r.heard.text)
        // A start still waiting for the recognizer stops waiting (3C final review, consumer fit 11).
        r.ready.complete(Unit)
    }

    private inline fun quietly(call: () -> Unit) {
        try {
            call()
        } catch (e: RuntimeException) {
            CoreLog.log("speech_port_failed ${e.javaClass.simpleName}")
        }
    }

    companion object {
        /** How long a start waits for the recognizer to be ready. */
        val READY_TIMEOUT: Duration = 3.seconds

        /** How long [finish] waits for the final result (ledger 6.2-20). */
        fun finalTimeout(kind: RecognizerKind): Duration = when (kind) {
            RecognizerKind.ON_DEVICE -> SpeechTimeouts.ON_DEVICE_FINALIZE
            RecognizerKind.STANDARD -> SpeechTimeouts.STANDARD_FINAL_RESULT
        }

        /** ERROR_AUDIO (3) and ERROR_INSUFFICIENT_PERMISSIONS (9) are the audio's fault; every other code the
         *  recognizer's. */
        fun startError(code: Int): SpeechStartException {
            val cause = IOException("speech_error_$code")
            return when (code) {
                SpeechRecognizer.ERROR_AUDIO, SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> SpeechStartException.Audio(cause)
                else -> SpeechStartException.Recognizer(cause)
            }
        }

        private fun first(results: Bundle?): String? = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
    }
}
