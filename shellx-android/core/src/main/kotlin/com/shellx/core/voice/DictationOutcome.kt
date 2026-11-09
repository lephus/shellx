package com.shellx.core.voice

/** What a released dictation becomes (`VoiceInputModel.outcome(words)`). The words never print. */
sealed interface DictationOutcome {
    val words: String

    /** Everything said: the composer sends it, a sheet takes it; the mic plays the success haptic. */
    data class Complete(override val words: String) : DictationOutcome {
        override fun toString(): String = "Complete(<redacted>)"
    }

    /** Stopped at the byte limit, so the last sentence may be cut: the composer puts it in its field to be read before
     *  sending; no success haptic. */
    data class CutAtLimit(override val words: String) : DictationOutcome {
        override fun toString(): String = "CutAtLimit(<redacted>)"
    }
}
