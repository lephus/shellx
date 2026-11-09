package com.shellx.app

import com.shellx.core.composer.AttachmentPick
import com.shellx.core.composer.AttachmentReadException
import com.shellx.core.composer.AttachmentReader
import com.shellx.core.composer.OutgoingAttachment
import com.shellx.core.push.PushRegistrar
import com.shellx.core.voice.SpeechEngine
import com.shellx.core.voice.SpeechRunId
import com.shellx.core.voice.VoiceLanguage
import com.shellx.core.voice.VoicePermissionChecking
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ReceiveChannel

// What AppComposition uses until plan 3E passes its real pieces (contracts §15).

/** No recognizer: a start hears nothing. */
object NoSpeechEngine : SpeechEngine {
    override suspend fun start(run: SpeechRunId, language: VoiceLanguage, contextualStrings: List<String>): ReceiveChannel<String> =
        Channel<String>().apply { close() }

    override suspend fun finish(run: SpeechRunId): String = ""

    override suspend fun cancel(run: SpeechRunId) {}
}

/** No microphone and no speech permission, and nothing to ask. */
object NoVoicePermissions : VoicePermissionChecking {
    override suspend fun needsPrompt(): Boolean = false

    override suspend fun microphone(): Boolean = false

    override suspend fun speech(): Boolean = false
}

/** No FCM token. */
object NoPushRegistrar : PushRegistrar {
    override suspend fun currentToken(): String? = null
}

/** Reads nothing. */
object NoAttachmentReader : AttachmentReader {
    override suspend fun read(pick: AttachmentPick, taken: List<String>): OutgoingAttachment =
        throw AttachmentReadException.Unreadable("")
}
