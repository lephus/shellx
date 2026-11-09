package com.shellx.app.testing

import com.shellx.core.voice.VoicePermissionChecking

/** The mic's permissions as the test sets them. Android has no speech permission: [speech] is always true. */
class FakeVoicePermissions(var microphone: Boolean = true, var needsPrompt: Boolean = false) : VoicePermissionChecking {
    override suspend fun needsPrompt(): Boolean = needsPrompt

    override suspend fun microphone(): Boolean = microphone

    override suspend fun speech(): Boolean = true
}
