package com.shellx.app

import android.app.Application
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ProcessLifecycleOwner
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.shellx.app.platform.FcmPushRegistrar
import com.shellx.app.platform.PermissionRequester
import com.shellx.app.platform.PlayUpdateChecker
import com.shellx.app.platform.PushNotifier
import com.shellx.app.platform.PushTapInbox
import com.shellx.app.ui.composer.AttachmentPreparer
import com.shellx.app.voice.SystemVoice
import com.shellx.app.voice.SystemVoicePermissions
import com.shellx.core.account.AccountVault
import com.shellx.core.composer.AttachmentReader
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.link.MachineHub
import com.shellx.core.platform.Clock
import com.shellx.core.platform.KeyValueStore
import com.shellx.core.push.PushRegistrar
import com.shellx.core.update.UpdateChecker
import com.shellx.core.voice.SpeechEngine
import com.shellx.core.voice.VoicePermissionChecking
import com.shellx.core.voice.VoiceService
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/**
 * Plan 3E's platform pieces (contracts §5, §15; the iPhone's `VoiceService.system`, `PushAppDelegate`, the update
 * prompt only in release), made once per process before [AppComposition]: [ShellXApplication] passes them to it by
 * type, and `MainActivity` attaches [permissions] and [playUpdates] to its result registry.
 */
class PlatformServices(private val app: Application, debugBuild: Boolean) {
    val permissions: PermissionRequester = PermissionRequester(app)
    val voice: SystemVoice = SystemVoice(app)
    val voicePermissions: VoicePermissionChecking = SystemVoicePermissions(permissions)
    val speechEngine: SpeechEngine get() = voice.engine
    val pushRegistrar: PushRegistrar = FcmPushRegistrar()
    val pushTaps: PushTapInbox = PushTapInbox()

    /** Null in debug builds: never there (S3 §6.1). */
    val playUpdates: PlayUpdateChecker? = if (debugBuild) null else PlayUpdateChecker(AppUpdateManagerFactory.create(app))
    val updateChecker: UpdateChecker? get() = playUpdates
    val attachmentReader: AttachmentReader = AttachmentPreparer(app.contentResolver, Dispatchers.IO)

    /** One signed-in account's voice input (AppComposition's `makeVoice`, for the real account and the demo). */
    fun makeVoice(hub: MachineHub, latency: LatencyLog, settings: KeyValueStore, clock: Clock): VoiceService =
        voice.makeService(hub, voicePermissions, latency, settings, clock)

    /**
     * The FCM service's notifier: in front means the process is at least STARTED; the known Macs are [vault]'s, null on
     * any failure (the alert then posts). [vault] suspends: FCM can start the process before the composition exists.
     */
    fun makeNotifier(vault: suspend () -> AccountVault): PushNotifier = PushNotifier(
        app,
        inForeground = { ProcessLifecycleOwner.get().lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED) },
        knownMachines = {
            try {
                vault().machines().map { it.machineId }.toSet()
            } catch (e: CancellationException) {
                currentCoroutineContext().ensureActive()
                null
            } catch (e: Exception) {
                null
            }
        },
    )
}
