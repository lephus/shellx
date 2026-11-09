package com.shellx.core.voice

import kotlinx.coroutines.channels.ReceiveChannel

/**
 * The on-device recognizer first, the standard `SpeechRecognizer` otherwise (S3 §7.3): a run starts on [primary] when
 * [usePrimary] says it can run the language now, else on [fallback].
 *
 * - The press begins in the shared [SpeechRunSlot] at entry, before any suspension, so which press is the newest is
 *   decided by the order of the presses, never by which readiness check returns first.
 * - A [SpeechStartException.Recognizer] from [primary] makes this press fall back, and [primaryFailed] is told, so the
 *   app stops offering the primary for the language and Settings names the path really used.
 * - Any other error ([SpeechStartException.Audio]: a passing audio problem) fails the press and keeps the primary for
 *   the next one.
 * - A primary's error for a run that was cancelled meanwhile (a quick tap while the primary waits to be ready) is the
 *   cancel's: it is rethrown, the run never starts on the fallback, and the primary stays offered (final review I-3).
 * - [finish] and [cancel] go through the slot, which holds the handlers of whichever engine claimed the run, so a run
 *   can never be left holding the microphone.
 *
 * Both engines share [slot], so one run holds the microphone across them.
 */
class FallbackTranscriber(
    private val slot: SpeechRunSlot,
    private val primary: SpeechEngine,
    private val fallback: SpeechEngine,
    private val usePrimary: suspend (VoiceLanguage) -> Boolean,
    private val primaryFailed: suspend (VoiceLanguage) -> Unit,
) : SpeechEngine {
    override suspend fun start(run: SpeechRunId, language: VoiceLanguage, contextualStrings: List<String>): ReceiveChannel<String> {
        slot.begin(run)
        if (usePrimary(language)) {
            try {
                return primary.start(run, language, contextualStrings)
            } catch (e: SpeechStartException.Recognizer) {
                if (slot.wasCancelled(run)) throw e
                primaryFailed(language)
            }
        }
        return fallback.start(run, language, contextualStrings)
    }

    override suspend fun finish(run: SpeechRunId): String = slot.takeForFinish(run)?.finish?.invoke() ?: ""

    override suspend fun cancel(run: SpeechRunId) {
        slot.cancel(run)?.teardown?.invoke()
    }
}
