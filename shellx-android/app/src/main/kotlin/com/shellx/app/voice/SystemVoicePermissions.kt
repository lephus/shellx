package com.shellx.app.voice

import android.Manifest
import com.shellx.app.platform.PermissionRequester
import com.shellx.core.voice.VoicePermissionChecking

/**
 * The mic's permission from Android (`SystemVoicePermissions.swift`): only the microphone (`RECORD_AUDIO`), asked the
 * first time the mic is pressed. Android has no speech-recognition permission, so [speech] is always true (ledger
 * A-24).
 */
class SystemVoicePermissions(private val requester: PermissionRequester) : VoicePermissionChecking {
    override suspend fun needsPrompt(): Boolean = !requester.isGranted(Manifest.permission.RECORD_AUDIO)

    override suspend fun microphone(): Boolean =
        requester.isGranted(Manifest.permission.RECORD_AUDIO) || requester.request(Manifest.permission.RECORD_AUDIO)

    override suspend fun speech(): Boolean = true
}
