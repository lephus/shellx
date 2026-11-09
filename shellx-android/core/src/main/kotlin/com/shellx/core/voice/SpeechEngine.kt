package com.shellx.core.voice

import java.util.UUID
import kotlinx.coroutines.channels.ReceiveChannel

/** Names one dictation of a [SpeechEngine]. `finish` and `cancel` act on that run only, so a late cancel of a press
 *  that was already released can never stop the next press's run. */
data class SpeechRunId(val raw: String = UUID.randomUUID().toString())

/**
 * One speech recognizer (contracts §5; 3E implements it over `android.speech.SpeechRecognizer`, on-device and
 * standard). Audio and transcripts never leave the phone's recognizer, and transcripts are never logged.
 *
 * A run holds the microphone from [start] until [finish] or [cancel] for it. One that ends by itself (an error, a time
 * limit) gives the microphone back too; the model still cancels it then. Starting a run stops any other run first.
 * Implementations that share the microphone share one [SpeechRunSlot].
 */
interface SpeechEngine {
    /**
     * Starts listening as [run]. The channel carries the whole text heard so far, the tentative part included, the
     * newest replacing the one before (`Channel.CONFLATED` is fine). It closes after [finish] or [cancel], or by
     * itself; a recognizer failure closes it with the error. A start that cannot begin throws
     * [SpeechStartException].
     */
    suspend fun start(run: SpeechRunId, language: VoiceLanguage, contextualStrings: List<String>): ReceiveChannel<String>

    /** Stops listening as [run] and returns its final text: "" when nothing was heard, or for a run that is not the one
     *  listening. Gives the mic back, also when it is cancelled, and should not throw: VoiceInputModel logs a
     *  failure, keeps the words heard and cancels the run. */
    suspend fun finish(run: SpeechRunId): String

    /** Stops listening as [run] and drops what was heard. Does nothing for any other run. Should not throw:
     *  VoiceInputModel logs a failure and goes on. */
    suspend fun cancel(run: SpeechRunId)
}
