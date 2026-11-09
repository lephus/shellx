package com.shellx.core.testing

import com.shellx.core.voice.VoicePermissionChecking

/** [VoicePermissionChecking] with answers the test sets, counting each request (port of FakeVoicePermissions).
 *  [promptPending] says whether asking would show the system prompt. Thread-safe. */
class FakeVoicePermissions(microphone: Boolean = true, speech: Boolean = true) : VoicePermissionChecking {
    private val lock = Any()
    private var microphoneAnswer = microphone
    private var speechAnswer = speech
    private var prompting = false
    private var microphoneCount = 0
    private var speechCount = 0

    var microphoneGranted: Boolean
        get() = synchronized(lock) { microphoneAnswer }
        set(value) { synchronized(lock) { microphoneAnswer = value } }

    var speechGranted: Boolean
        get() = synchronized(lock) { speechAnswer }
        set(value) { synchronized(lock) { speechAnswer = value } }

    var promptPending: Boolean
        get() = synchronized(lock) { prompting }
        set(value) { synchronized(lock) { prompting = value } }

    val microphoneRequests: Int get() = synchronized(lock) { microphoneCount }
    val speechRequests: Int get() = synchronized(lock) { speechCount }

    override suspend fun needsPrompt(): Boolean = promptPending

    override suspend fun microphone(): Boolean = synchronized(lock) {
        microphoneCount += 1
        microphoneAnswer
    }

    override suspend fun speech(): Boolean = synchronized(lock) {
        speechCount += 1
        speechAnswer
    }
}
