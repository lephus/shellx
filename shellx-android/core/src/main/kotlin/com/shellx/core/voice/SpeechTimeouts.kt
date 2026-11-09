package com.shellx.core.voice

import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

/** For 3E's recognizers (S3 §6.2, ledger 6.2-20): how long `finish()` waits for the final result. */
object SpeechTimeouts {
    /** The standard `SpeechRecognizer` (the iPhone's `LegacyTranscriber.finalResultTimeout`). */
    val STANDARD_FINAL_RESULT: Duration = 1500.milliseconds

    /** The on-device recognizer (the iPhone's `AnalyzerTranscriber.finalizeTimeout`). */
    val ON_DEVICE_FINALIZE: Duration = 2.seconds
}
