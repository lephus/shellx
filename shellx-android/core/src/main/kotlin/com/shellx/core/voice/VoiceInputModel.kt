package com.shellx.core.voice

import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.diagnostics.LatencyMetric
import com.shellx.core.home.ComposerValidation
import com.shellx.core.platform.CoreLog
import com.shellx.core.platform.rethrowIfCancelled
import com.shellx.core.platform.runDetached
import com.shellx.core.text.cutToUtf8
import com.shellx.core.text.utf8Size
import kotlin.time.ComparableTimeMark
import kotlin.time.Duration
import kotlin.time.TimeSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What a mic shows (`VoiceInputModel.state`). */
data class VoiceInputState(
    val phase: VoiceInputModel.Phase = VoiceInputModel.Phase.Idle,
    val wantsKeyboard: Boolean = false,
    val firstWordLatency: Duration? = null,
    val limitReached: Boolean = false,
    val language: VoiceLanguage,
)

/**
 * Hold-to-talk (S3 §7.3). [press] checks the permissions and that some recognizer can run, then listens; the words
 * show in [phase] as they come; [release] returns them. A drag to the left arms cancel ([drag]); a swipe up before
 * any word asks for the keyboard instead. With TalkBack the same calls make a tap-to-start, tap-to-finish button.
 *
 * - The keyboard always stays usable: no recognizer ([Phase.Unavailable]) also sets [wantsKeyboard]; denied
 *   permissions only say so ([Phase.Denied]) until the next press.
 * - Past [maxBytes] UTF-8 bytes, listening stops on its own; the words within the limit are kept and [limitReached] is
 *   set, so nothing longer than the composer accepts is ever sent.
 * - [firstWordLatency] is the time from [press] to the first update with a word (by `timeSource`), also recorded in
 *   the [LatencyLog] (`firstWord`, target 300 ms); not for a press that showed a permission prompt. Transcripts are
 *   never logged and never print.
 * - The microphone is always given back: on release, cancel, [typeInstead], and when the recognizer's channel closes
 *   by itself. Each press is its own [SpeechRunId], so stopping an old press never stops a newer one.
 * - Android only: a screen's coroutine can be cancelled in the middle of a call (the iPhone never cancels a view's
 *   Task). The recognizer's finish and every give-back of the mic run in `scope`, so a cancelled caller never leaves
 *   the mic stuck in [Phase.Finishing] or a recognizer listening behind an idle mic (review 4 I-1). A press whose
 *   caller is cancelled while it starts is dropped, and its run gives the mic back (M-2). An engine whose `finish` or
 *   `cancel` throws is logged by code (`voice_finish_failed`, `voice_cancel_failed`) and the dictation still ends
 *   (M-1).
 *
 * Main-confined. The reader of the recognizer's channel runs in `scope`.
 */
class VoiceInputModel(
    private val engine: SpeechEngine,
    private val permissions: VoicePermissionChecking,
    private val capabilities: suspend (VoiceLanguage) -> VoiceCapabilities,
    language: VoiceLanguage,
    private val contextualStrings: () -> List<String>,
    private val latency: LatencyLog,
    private val timeSource: TimeSource.WithComparableMarks,
    private val scope: CoroutineScope,
    /** The most UTF-8 bytes one dictation keeps. */
    val maxBytes: Int = ComposerValidation.MAX_BYTES,
) {
    sealed interface Phase {
        data object Idle : Phase

        /** Listening (or starting to); [text] is everything heard so far. */
        data class Listening(val text: String) : Phase {
            override fun toString(): String = "Listening(<redacted>)"
        }

        /** Still listening, but releasing now cancels. */
        data class CancelArmed(val text: String) : Phase {
            override fun toString(): String = "CancelArmed(<redacted>)"
        }

        /** Released; waiting for the recognizer's final text. */
        data object Finishing : Phase

        /** A permission is missing: the screen says so and offers Settings. */
        data class Denied(val permission: VoicePermission) : Phase

        /** No recognizer can run now (no network and nothing on the phone): the screen says so. */
        data object Unavailable : Phase
    }

    /** Where the recognizer of the current press stands. */
    private enum class Recognition {
        /** Checking permissions and capabilities, or starting the recognizer. */
        STARTING,

        /** Running: updates are taken. */
        RUNNING,

        /** Released: `finish` was asked for; late updates are still taken, but the channel's end is not an end by
         *  itself. */
        FINISHING,

        /** Stopped by itself (the limit, an error, its own end): what was heard is kept. */
        STOPPED,
    }

    private val _state = MutableStateFlow(VoiceInputState(language = language))
    val state: StateFlow<VoiceInputState> = _state.asStateFlow()

    val phase: Phase get() = state.value.phase

    /** Set when the user swiped up before any word, or when no recognizer can run: the screen opens the keyboard, then
     *  sets this back to false. */
    var wantsKeyboard: Boolean
        get() = state.value.wantsKeyboard
        set(value) = _state.update { it.copy(wantsKeyboard = value) }

    /** From the last [press] to its first update with a word; null until then. */
    val firstWordLatency: Duration? get() = state.value.firstWordLatency

    /** The last dictation stopped at [maxBytes]. */
    val limitReached: Boolean get() = state.value.limitReached

    /** The language of the next press. */
    var language: VoiceLanguage
        get() = state.value.language
        set(value) = _state.update { it.copy(language = value) }

    /** Listening, cancel armed or finishing. */
    val isActive: Boolean
        get() = when (phase) {
            is Phase.Listening, is Phase.CancelArmed, Phase.Finishing -> true
            Phase.Idle, is Phase.Denied, Phase.Unavailable -> false
        }

    /** Counts presses; work of an older press is dropped. */
    private var attempt = 0

    /** The current press was released (or cancelled) while it was still starting. */
    private var released = false
    private var recognition = Recognition.STOPPED
    private var text = ""
    private var elapsed: ComparableTimeMark? = null
    private var reader: Job? = null

    /** The current press's run: the engine's `finish` and `cancel` name it. */
    private var run: SpeechRunId? = null

    // Gestures

    /** The finger went down (or TalkBack's first tap): checks the permissions and that a recognizer can run, then
     *  listens. Does nothing while a dictation is active. */
    suspend fun press() {
        if (isActive) return
        attempt += 1
        val current = attempt
        val run = SpeechRunId()
        this.run = run
        released = false
        recognition = Recognition.STARTING
        text = ""
        elapsed = timeSource.markNow()
        _state.update {
            it.copy(phase = Phase.Listening(""), wantsKeyboard = false, firstWordLatency = null, limitReached = false)
        }

        try {
            // A system prompt's time is not speech latency: that press records no first-word sample.
            if (permissions.needsPrompt() && attempt == current) elapsed = null
            if (!permissions.microphone()) return refuse(current, Phase.Denied(VoicePermission.MICROPHONE))
            if (!permissions.speech()) return refuse(current, Phase.Denied(VoicePermission.SPEECH))
            if (capabilities(language).engine == null) return refuse(current, Phase.Unavailable)
            if (attempt != current || released) return

            val channel = try {
                engine.start(run, language, contextualStrings())
            } catch (e: Exception) {
                rethrowIfCancelled(e)
                return refuse(current, Phase.Unavailable)
            }
            // Released while the recognizer started: the release already cancelled this run, so the engine refused
            // it the microphone; nothing more to stop.
            if (attempt != current || released) return
            recognition = Recognition.RUNNING
            reader = scope.launch { read(channel, current, run) }
        } catch (e: Throwable) {
            abandon(current)
            throw e
        }
    }

    /** The finger moved by ([dx], [dy]) dp from where it went down. */
    fun drag(dx: Double, dy: Double) {
        if (phase !is Phase.Listening && phase !is Phase.CancelArmed) return
        if (dy <= -KEYBOARD_DISTANCE && isBlank(text)) {
            wantsKeyboard = true
            val run = drop()
            if (run != null) scope.launch { cancelQuietly(run) }
            return
        }
        setPhase(if (dx <= -CANCEL_DISTANCE) Phase.CancelArmed(text) else Phase.Listening(text))
    }

    /** The finger went up (or TalkBack's second tap): the final text, trimmed, unless cancel was armed or nothing was
     *  said. Null also while nothing listens. */
    suspend fun release(): String? {
        when (phase) {
            is Phase.Listening -> Unit
            is Phase.CancelArmed -> {
                drop()?.let { giveBack(it) }
                return null
            }
            else -> {
                released = true
                return null
            }
        }
        return when (recognition) {
            Recognition.STARTING -> {
                // Cancelled now, while it starts: the engine never gives it the microphone.
                drop()?.let { giveBack(it) }
                null
            }
            Recognition.STOPPED, Recognition.FINISHING -> {
                setPhase(Phase.Idle)
                nonBlank(text)
            }
            Recognition.RUNNING -> {
                val run = run ?: return null
                setPhase(Phase.Finishing)
                recognition = Recognition.FINISHING
                // In the model's scope: a caller cancelled while the recognizer finishes still leaves the mic idle.
                scope.runDetached {
                    var finalText = ""
                    try {
                        finalText = engine.finish(run)
                    } catch (e: Exception) {
                        rethrowIfCancelled(e)
                        // The words heard so far stay; the run is cancelled so the mic is given back.
                        CoreLog.log("voice_finish_failed")
                        cancelQuietly(run)
                    } finally {
                        recognition = Recognition.STOPPED
                        reader?.cancel()
                        reader = null
                        setPhase(Phase.Idle)
                    }
                    val words = if (isBlank(finalText)) text else finalText
                    nonBlank(cut(words))
                }
            }
        }
    }

    /** What released words become: everything said, or words stopped at [maxBytes], which the composer puts in its
     *  field to be read rather than sending (and the mic plays no success). */
    fun outcome(words: String): DictationOutcome =
        if (limitReached) DictationOutcome.CutAtLimit(words) else DictationOutcome.Complete(words)

    /** The user chose the keyboard (the keyboard button, "Type instead"): a dictation in progress is cancelled and its
     *  words dropped, so nothing heard while typing is sent later. A "can't listen" notice stays until typing clears
     *  it ([dismiss]). */
    suspend fun typeInstead() {
        cancel()
    }

    /** Stops listening at once and drops the words: the mic's screen went away, the audio was interrupted or the app
     *  left the foreground. Does nothing while nothing listens. */
    suspend fun cancel() {
        if (phase is Phase.Listening || phase is Phase.CancelArmed) drop()?.let { giveBack(it) }
    }

    /** Clears a denied or unavailable message (the user typed instead, or closed it). */
    fun dismiss() {
        if (phase is Phase.Denied || phase == Phase.Unavailable) setPhase(Phase.Idle)
    }

    // Private

    private fun setPhase(phase: Phase) {
        _state.update { it.copy(phase = phase) }
    }

    /** Ends a press that cannot listen. The reason shows even when the finger is already up (the permission prompt
     *  took it), unless a newer press started. */
    private fun refuse(current: Int, reason: Phase) {
        if (attempt != current) return
        recognition = Recognition.STOPPED
        _state.update { it.copy(phase = reason, wantsKeyboard = if (reason == Phase.Unavailable) true else it.wantsKeyboard) }
    }

    /** A press that left while it started (its caller was cancelled, or a check threw): drops it, and gives its run's
     *  mic back in the model's scope, in case the engine already granted it (review 4 M-2). A newer press, or a
     *  release that already dropped this one, is left alone. */
    private fun abandon(current: Int) {
        if (attempt != current || recognition != Recognition.STARTING) return
        val run = drop() ?: return
        scope.launch { cancelQuietly(run) }
    }

    /** Gives [run]'s mic back in the model's scope and waits for it: a caller cancelled meanwhile still releases the
     *  mic (review 4 I-1). */
    private suspend fun giveBack(run: SpeechRunId) {
        scope.runDetached { cancelQuietly(run) }
    }

    /** The engine's cancel. A failure is logged by code, never thrown (review 4 M-1). */
    private suspend fun cancelQuietly(run: SpeechRunId) {
        try {
            engine.cancel(run)
        } catch (e: Exception) {
            rethrowIfCancelled(e)
            CoreLog.log("voice_cancel_failed")
        }
    }

    /** Stops listening now and drops the words. Returns the run when its recognizer was running or still starting: the
     *  caller cancels it (a run cancelled while it starts never gets the mic). */
    private fun drop(): SpeechRunId? {
        released = true
        val live = recognition == Recognition.RUNNING || recognition == Recognition.STARTING
        recognition = Recognition.STOPPED
        reader?.cancel()
        reader = null
        setPhase(Phase.Idle)
        return if (live) run else null
    }

    /** Takes the run's updates. When the channel closes by itself (an error, a time limit), the words heard stay for
     *  release, and the run is cancelled so the microphone is given back at once. */
    private suspend fun read(channel: ReceiveChannel<String>, current: Int, run: SpeechRunId) {
        try {
            for (update in channel) {
                if (attempt != current || (recognition != Recognition.RUNNING && recognition != Recognition.FINISHING)) return
                take(update)
            }
            if (attempt != current || recognition != Recognition.RUNNING) return
            recognition = Recognition.STOPPED
        } catch (e: Exception) {
            rethrowIfCancelled(e)
            if (attempt != current || recognition != Recognition.RUNNING) return
            recognition = Recognition.STOPPED
            // Nothing heard: no recognizer works right now. Otherwise the words stay to be sent.
            if (isBlank(text) && phase is Phase.Listening) {
                _state.update { it.copy(phase = Phase.Unavailable, wantsKeyboard = true) }
            }
        }
        // A drop() meanwhile cancels this reader; the give-back still finishes.
        withContext(NonCancellable) { cancelQuietly(run) }
    }

    private fun take(update: String) {
        val kept = cut(update)
        text = kept
        val since = elapsed
        if (firstWordLatency == null && !isBlank(kept) && since != null) {
            val duration = since.elapsedNow()
            _state.update { it.copy(firstWordLatency = duration) }
            latency.record(LatencyMetric.FIRST_WORD, duration)
        }
        when (phase) {
            is Phase.Listening -> setPhase(Phase.Listening(kept))
            is Phase.CancelArmed -> setPhase(Phase.CancelArmed(kept))
            else -> Unit
        }
        val run = run
        if (limitReached && recognition == Recognition.RUNNING && run != null) {
            // Stop listening at the limit; the kept words stay until release.
            recognition = Recognition.STOPPED
            scope.launch { cancelQuietly(run) }
        }
    }

    /** [text] cut to [maxBytes] UTF-8 bytes on a character boundary; sets [limitReached] when cut. */
    private fun cut(text: String): String {
        if (text.utf8Size <= maxBytes) return text
        _state.update { it.copy(limitReached = true) }
        return text.cutToUtf8(maxBytes)
    }

    companion object {
        /** How far left (dp) a drag arms cancel. */
        const val CANCEL_DISTANCE = 80.0

        /** How far up (dp) a swipe asks for the keyboard, before any word. */
        const val KEYBOARD_DISTANCE = 60.0

        /** Terms added to every recognition, so Vietnamese mixed with these English words is heard right. */
        val TERMS: List<String> = listOf("PR", "CI", "push", "pull request", "branch", "merge", "deploy", "commit", "Claude")

        /** The workspace names of the live sessions, then [TERMS], trimmed, without blanks or repeats. */
        fun contextualStrings(workspaceTitles: List<String>): List<String> {
            val seen = HashSet<String>()
            val strings = ArrayList<String>()
            for (string in workspaceTitles + TERMS) {
                val trimmed = string.trim()
                if (trimmed.isEmpty() || !seen.add(trimmed)) continue
                strings += trimmed
            }
            return strings
        }

        private fun isBlank(text: String): Boolean = text.isBlank()

        private fun nonBlank(text: String): String? = text.trim().ifEmpty { null }
    }
}
