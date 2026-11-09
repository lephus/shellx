package com.shellx.app.voice

import android.content.Context
import android.content.res.Resources
import com.shellx.app.platform.ElapsedRealtimeTimeSource
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.link.MachineHub
import com.shellx.core.platform.Clock
import com.shellx.core.platform.KeyValueStore
import com.shellx.core.voice.FallbackTranscriber
import com.shellx.core.voice.SpeechEngine
import com.shellx.core.voice.SpeechRunSlot
import com.shellx.core.voice.VoiceCapabilityCache
import com.shellx.core.voice.VoiceLanguage
import com.shellx.core.voice.VoicePermissionChecking
import com.shellx.core.voice.VoiceService
import java.lang.ref.WeakReference
import kotlin.time.TimeSource

/**
 * The phone's speech recognition (the iPhone's `VoiceService.system`): the on-device recognizer first, the standard
 * one as the fallback (S3 §7.3). One per process; each signed-in account gets its [VoiceService] from [makeService].
 *
 * Both engines share one [SpeechRunSlot] and the level [meter]. What the phone can do is asked through one
 * process-level [VoiceCapabilityCache], which the fallback's choice, the standard recognizer's "prefer offline" and
 * every account's service read, so a press never waits for the phone's answer more than once (3C final review,
 * consumer fit 13).
 */
class SystemVoice(
    context: Context,
    val probe: VoiceCapabilityProbe = VoiceCapabilityProbe.system(context),
    val meter: AudioLevelMeter = AudioLevelMeter(),
    timeSource: TimeSource.WithComparableMarks = ElapsedRealtimeTimeSource,
) {
    private val app = context.applicationContext
    private val slot = SpeechRunSlot()
    private val known = VoiceCapabilityCache(timeSource = timeSource, ask = probe::capabilities)
    private val intents = RecognizerIntents(app.packageName)

    /** The newest service made: it hears that the on-device recognizer failed, so Settings names the path used. */
    @Volatile private var newest: WeakReference<VoiceService>? = null

    val engine: SpeechEngine = FallbackTranscriber(
        slot = slot,
        primary = SpeechRecognizerEngine(
            RecognizerKind.ON_DEVICE, slot, { SystemRecognizerPort.create(app, RecognizerKind.ON_DEVICE) }, meter, intents,
        ),
        fallback = SpeechRecognizerEngine(
            RecognizerKind.STANDARD, slot, { SystemRecognizerPort.create(app, RecognizerKind.STANDARD) }, meter, intents,
            preferOffline = { known.capabilities(it).standardOnDevice },
        ),
        usePrimary = { known.capabilities(it).onDeviceRecognizer },
        primaryFailed = ::primaryFailed,
    )

    /** The on-device recognizer failed to start for [language] (the fallback's `primaryFailed`): it is not offered
     *  again, and the services hear it, so Settings names the path used. */
    internal suspend fun primaryFailed(language: VoiceLanguage) {
        probe.markFailed(language)
        known.forget(language)
        newest?.get()?.primaryFellBack(language)
    }

    /**
     * The account's voice input over [hub]: [engine], its capabilities through the process-level answers, the hub's
     * scope, and the phone's preferred languages. The newest one made hears `primaryFellBack`.
     */
    fun makeService(
        hub: MachineHub,
        permissions: VoicePermissionChecking,
        latency: LatencyLog,
        settings: KeyValueStore,
        clock: Clock,
    ): VoiceService {
        val service = VoiceService(
            engine = engine,
            permissions = permissions,
            cache = VoiceCapabilityCache(timeSource = clock.monotonic) { known.capabilities(it) },
            latency = latency,
            settings = settings,
            scope = hub.scope,
            timeSource = clock.monotonic,
            preferredLanguages = preferredLanguages(),
            contextualStrings = VoiceService.contextualStrings(hub),
        )
        newest = WeakReference(service)
        return service
    }

    companion object {
        /** The phone's language list (not the app's own language), as BCP 47 tags. */
        fun preferredLanguages(): List<String> {
            val locales = Resources.getSystem().configuration.locales
            return (0 until locales.size()).map { locales[it].toLanguageTag() }
        }
    }
}
