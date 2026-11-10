package com.shellx.app.testing

import com.shellx.app.voice.AudioLevelMeter
import com.shellx.app.voice.VoiceEnvironment
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.home.ComposerValidation
import com.shellx.core.platform.MemoryKeyValueStore
import com.shellx.core.voice.VoiceCapabilities
import com.shellx.core.voice.VoiceCapabilityCache
import com.shellx.core.voice.VoiceInputModel
import com.shellx.core.voice.VoiceLanguage
import com.shellx.core.voice.VoiceService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/** A [VoiceService] over [FakeSpeechEngine] and [FakeVoicePermissions] on the main looper (the iPhone
 *  MicButtonRenderTests' rig), and the [VoiceEnvironment] a mic reads. */
class VoiceRig(
    val engine: FakeSpeechEngine,
    val permissions: FakeVoicePermissions,
    val service: VoiceService,
    val env: VoiceEnvironment,
) {
    fun model(maxBytes: Int = ComposerValidation.MAX_BYTES): VoiceInputModel = service.makeModel(maxBytes)

    companion object {
        /** Only the speech service can recognize: the mic works, nothing on the phone. */
        val SERVER_ONLY: VoiceCapabilities = VoiceCapabilities(onDeviceRecognizer = false, standardOnDevice = false, standardAvailable = true)

        /** Vietnamese saved in the settings; the meter at [level]. */
        fun make(capabilities: VoiceCapabilities = SERVER_ONLY, microphone: Boolean = true, level: Float = 0.6f): VoiceRig {
            val engine = FakeSpeechEngine()
            val permissions = FakeVoicePermissions(microphone = microphone)
            val settings = MemoryKeyValueStore().also { VoiceLanguage.VIETNAMESE.save(it) }
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
            val service = VoiceService(
                engine, permissions, VoiceCapabilityCache(timeSource = TestClock.monotonic) { capabilities }, LatencyLog(), settings,
                scope, TestClock.monotonic, listOf("vi-VN"), { emptyList() },
            )
            return VoiceRig(engine, permissions, service, VoiceEnvironment(service, AudioLevelMeter(level), scope))
        }
    }
}
