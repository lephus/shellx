package com.shellx.core.voice

/** The two permissions the mic needs on the iPhone. Android asks for [MICROPHONE] only. */
enum class VoicePermission { MICROPHONE, SPEECH }

/**
 * Asks the phone for the mic's permissions. Each call asks the user when they were never asked, and otherwise answers
 * with what they chose. 3E implements it with RECORD_AUDIO. Android has no separate speech permission, so [speech]
 * returns true.
 */
interface VoicePermissionChecking {
    /** True when [microphone] or [speech] would show the system prompt (never asked yet). The time a prompt stays up
     *  is not speech latency, so that press records no `firstWord` sample. */
    suspend fun needsPrompt(): Boolean

    suspend fun microphone(): Boolean

    suspend fun speech(): Boolean
}
