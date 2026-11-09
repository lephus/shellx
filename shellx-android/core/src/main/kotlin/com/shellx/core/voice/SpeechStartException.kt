package com.shellx.core.voice

/** Why a [SpeechEngine] could not start a run. [FallbackTranscriber] gives up the primary for a language only on
 *  [Recognizer]. */
sealed class SpeechStartException(cause: Throwable) : Exception("speech_start", cause) {
    /** The recognizer itself failed (it is missing, its language pack or its start): the fallback gives up the
     *  primary for the language. */
    class Recognizer(cause: Throwable) : SpeechStartException(cause)

    /** The audio could not start (the microphone is busy during a call, no input). Passing: it fails this press
     *  only. */
    class Audio(cause: Throwable) : SpeechStartException(cause)
}
