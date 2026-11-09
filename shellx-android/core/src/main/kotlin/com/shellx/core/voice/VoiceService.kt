package com.shellx.core.voice

import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.home.ComposerValidation
import com.shellx.core.link.MachineHub
import com.shellx.core.platform.KeyValueStore
import java.lang.ref.WeakReference
import kotlin.time.TimeSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** What Settings › Voice shows (`VoiceService.state`). */
data class VoiceServiceState(val language: VoiceLanguage, val engine: VoiceEngine? = null, val engineKnown: Boolean = false)

/**
 * The signed-in account's voice input (the iPhone app target's VoiceService; on Android its logic is in `:core`). It
 * makes a [VoiceInputModel] for each place with a mic (the composers, the question and plan sheets), keeps the spoken
 * language (Settings › Voice, saved in the settings store) and which recognizer runs for it.
 *
 * [cancelAll] stops every mic at once: the audio was interrupted (a call), the input went away, or the app left the
 * foreground.
 *
 * Main-confined. One per signed-in account (3E builds it with a [FallbackTranscriber] over its two recognizers, and
 * passes [primaryFellBack] as the fallback's `primaryFailed`).
 */
class VoiceService(
    engine: SpeechEngine,
    private val permissions: VoicePermissionChecking,
    private val cache: VoiceCapabilityCache,
    private val latency: LatencyLog,
    private val settings: KeyValueStore,
    private val scope: CoroutineScope,
    private val timeSource: TimeSource.WithComparableMarks,
    preferredLanguages: List<String>,
    private val contextualStrings: () -> List<String>,
) {
    /** The constructor's `engine`: the name [engine] is the recognizer Settings shows. */
    private val speech: SpeechEngine = engine
    private val _state = MutableStateFlow(VoiceServiceState(language = VoiceLanguage.saved(settings, preferredLanguages)))
    val state: StateFlow<VoiceServiceState> = _state.asStateFlow()

    val language: VoiceLanguage get() = state.value.language

    /** The recognizer for [language]; null when none can run. Set by [refreshEngine]. */
    val engine: VoiceEngine? get() = state.value.engine

    /** True once [refreshEngine] answered for the current language. */
    val engineKnown: Boolean get() = state.value.engineKnown

    /** The models made here, held weakly so their language follows Settings. */
    private val made = ArrayList<WeakReference<VoiceInputModel>>()

    /** Some mic made here listens or finishes its words: the workspace screen stops paging, so a drag on the mic (left
     *  is cancel) stays the mic's. Not observable: a screen collects its own mic's state. */
    val isListening: Boolean get() = made.any { it.get()?.isActive == true }

    /** A dictation model for one mic; [maxBytes] is the most its text may take. */
    fun makeModel(maxBytes: Int = ComposerValidation.MAX_BYTES): VoiceInputModel {
        val model = VoiceInputModel(
            speech, permissions, capabilities = { cache.capabilities(it) }, language = language,
            contextualStrings = contextualStrings, latency = latency, timeSource = timeSource, scope = scope,
            maxBytes = maxBytes,
        )
        made.removeAll { it.get() == null }
        made += WeakReference(model)
        return model
    }

    /** Saves the spoken language; every mic uses it from its next press. */
    fun setLanguage(language: VoiceLanguage) {
        if (language == this.language) return
        language.save(settings)
        _state.update { it.copy(language = language, engineKnown = false) }
        for (entry in made) entry.get()?.language = language
    }

    /** Asks the phone which recognizer runs for the current language. */
    suspend fun refreshEngine() {
        val asked = language
        val found = cache.capabilities(asked).engine
        if (asked != language) return
        _state.update { it.copy(engine = found, engineKnown = true) }
    }

    /** Stops every mic that listens now and drops its words. */
    suspend fun cancelAll() {
        for (model in made.mapNotNull { it.get() }) model.cancel()
    }

    /** The on-device recognizer failed to start for [language] (FallbackTranscriber's `primaryFailed`), so presses go
     *  through the standard one: forget the cached answer and ask again, so Settings names the path really used. */
    suspend fun primaryFellBack(language: VoiceLanguage) {
        cache.forget(language)
        if (language == this.language) refreshEngine()
    }

    companion object {
        /** The workspace names of [hub]'s live sessions, then the terms (VoiceInputModel.contextualStrings). Holds the
         *  hub weakly, as the iPhone does. */
        fun contextualStrings(hub: MachineHub): () -> List<String> {
            val reference = WeakReference(hub)
            return {
                VoiceInputModel.contextualStrings(reference.get()?.liveSessions?.map { it.session.workspaceTitle } ?: emptyList())
            }
        }
    }
}
