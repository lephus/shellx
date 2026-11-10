package com.shellx.app.voice

import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.staticCompositionLocalOf
import com.shellx.core.voice.VoiceService
import java.util.Collections
import java.util.IdentityHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * What a mic needs (the iPhone's `VoiceService` in the environment): the account's [service] (null shows no mic), the
 * level [meter], and the [scope] mic actions run in so they outlive a composable (the hub's).
 */
class VoiceEnvironment(
    val service: VoiceService?,
    val meter: AudioLevelMeter,
    val scope: CoroutineScope,
    val activity: MicActivity = MicActivity(),
)

/** Which mics are active now (`VoiceService.isListening` is not observable): the workspace pager stops paging while one
 *  is, so a drag on the mic stays the mic's. Thread-safe. */
class MicActivity {
    private val active: MutableSet<Any> = Collections.newSetFromMap(IdentityHashMap())
    private val _anyActive = MutableStateFlow(false)
    val anyActive: StateFlow<Boolean> = _anyActive.asStateFlow()

    fun update(mic: Any, active: Boolean) {
        synchronized(this.active) {
            if (active) this.active.add(mic) else this.active.remove(mic)
            _anyActive.value = this.active.isNotEmpty()
        }
    }
}

/** The signed-in account's mic for every screen below (plan 3E's `SignedInWork` provides it). */
val LocalVoice: ProvidableCompositionLocal<VoiceEnvironment?> = staticCompositionLocalOf { null }
