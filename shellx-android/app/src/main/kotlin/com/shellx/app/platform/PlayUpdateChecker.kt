package com.shellx.app.platform

import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import com.shellx.core.platform.CoreLog
import com.shellx.core.update.AvailableUpdate
import com.shellx.core.update.UpdateChecker
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * 3C's [UpdateChecker] over Play In-App Updates, flexible flow only (S3 §7.3; ledger A-27): Play's own dialog is the
 * prompt, the download runs in the background, and [completeUpdate] restarts into the new version. One per process,
 * made only in release builds. Main thread.
 */
class PlayUpdateChecker(private val manager: AppUpdateManager) : UpdateChecker {
    enum class InstallPhase { NONE, DOWNLOADING, DOWNLOADED, INSTALLING, FAILED }

    private val _installs = MutableStateFlow(InstallPhase.NONE)

    /** Where Play's download stands, from its install listener (registered here, for the process's life). */
    val installs: StateFlow<InstallPhase> = _installs.asStateFlow()

    private var launcher: ActivityResultLauncher<IntentSenderRequest>? = null

    /** The newest info, until a start uses it (Play takes each [AppUpdateInfo] once). */
    private var latest: AppUpdateInfo? = null

    init {
        manager.registerListener { state -> _installs.value = phase(state.installStatus()) }
    }

    /** A StartIntentSenderForResult launcher (key [KEY]) for Play's dialog; call in `MainActivity.onCreate`. */
    fun attach(registry: ActivityResultRegistry, owner: LifecycleOwner) {
        val registered = registry.register(KEY, owner, ActivityResultContracts.StartIntentSenderForResult()) { result ->
            // Update or No thanks; Play's install listener reports the download.
            CoreLog.log("update_flow_result ${result.resultCode}")
        }
        launcher = registered
        owner.lifecycle.addObserver(
            LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_DESTROY && launcher === registered) launcher = null
            },
        )
    }

    /**
     * `AvailableUpdate(availableVersionCode)` when an update is available, the flexible flow is allowed and nothing is
     * pending, downloading, downloaded or installing; else null. Also sets [installs] from the install status, so a
     * download that finished while the app was away asks to restart.
     */
    override suspend fun check(): AvailableUpdate? {
        val info = manager.appUpdateInfo.await()
        latest = info
        val phase = phase(info.installStatus())
        _installs.value = phase
        val offered = info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE &&
            info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE) &&
            phase != InstallPhase.DOWNLOADING && phase != InstallPhase.DOWNLOADED && phase != InstallPhase.INSTALLING
        return if (offered) AvailableUpdate(info.availableVersionCode().toLong()) else null
    }

    /** Play's flexible-update dialog for the newest info; nothing without an attached activity. */
    override suspend fun startUpdate(update: AvailableUpdate) {
        val current = launcher ?: return
        val info = latest ?: manager.appUpdateInfo.await()
        latest = null
        manager.startUpdateFlowForResult(info, current, AppUpdateOptions.newBuilder(AppUpdateType.FLEXIBLE).build())
    }

    /** Play installs the downloaded update and restarts the app into the new version. */
    fun completeUpdate() {
        manager.completeUpdate().addOnFailureListener { CoreLog.log("update_complete_failed ${it.javaClass.simpleName}") }
    }

    companion object {
        const val KEY = "shellx.update"

        fun phase(installStatus: Int): InstallPhase = when (installStatus) {
            InstallStatus.PENDING, InstallStatus.DOWNLOADING -> InstallPhase.DOWNLOADING
            InstallStatus.DOWNLOADED -> InstallPhase.DOWNLOADED
            InstallStatus.INSTALLING -> InstallPhase.INSTALLING
            InstallStatus.FAILED -> InstallPhase.FAILED
            else -> InstallPhase.NONE
        }
    }
}
