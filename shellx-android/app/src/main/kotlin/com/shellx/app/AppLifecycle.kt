package com.shellx.app

import com.shellx.core.link.MachineHub
import com.shellx.core.link.NetworkChangeFilter
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

/**
 * The process lifecycle of the real account ("3D's ON_START hook" of plan 3E), fed by `ProcessLifecycleOwner` in
 * [ShellXApplication]; the demo runs in memory and needs none of it. Main-confined.
 *
 * - The account launches at the first start in front, never at process start: a process that a push started in the
 *   background connects nothing and watches no network until then (S3 §4, Spec note 9).
 * - The network is watched only while started. A pending settle ends with the watch, so nothing reconnects after
 *   ON_STOP.
 * - ON_STOP starts the hub's background grace undispatched, so it is recorded before a later ON_START (carry 3D-5); a
 *   hub made while stopped (a launch or sign-in that finished after ON_STOP) gets the grace too (3C final review m-7).
 */
class AppLifecycle(private val composition: AppComposition) {
    var isStarted: Boolean = false
        private set

    private var launched = false
    private var networkJob: Job? = null

    /** The hub ON_STOP or a stopped-time watch already sent to the background. */
    private var backgrounded: MachineHub? = null

    private val real: AccountGraph get() = composition.real

    fun onStart() {
        isStarted = true
        backgrounded = null
        val scope = composition.appScope
        val first = !launched
        if (first) {
            launched = true
            // A process a push started in the background counts its launch from here (3D's 3E-fit note 8).
            real.launch.restart()
            watchHubsWhileStopped()
            scope.launch {
                real.coordinator.launch()
                val hub = real.coordinator.hub.value
                // A launch that had to sign in, or has no Mac yet, takes no launch sample.
                if (hub == null || hub.state.value.machines.isEmpty()) real.launch.skip()
            }
        }
        networkJob?.cancel()
        networkJob = scope.launch {
            coroutineScope {
                val filter = NetworkChangeFilter(this) { real.coordinator.hub.value?.networkChanged() }
                composition.environment.network.paths.collect { filter.receive(it) }
            }
        }
        // The first start's launch reads the store already (3C final review m-2); later starts retry a busy one.
        if (!first) scope.launch { real.coordinator.protectedDataBecameAvailable() }
        real.updatePrompt?.let { prompt -> scope.launch { prompt.check() } }
        real.push?.let { push -> scope.launch { push.appBecameActive() } }
        real.coordinator.hub.value?.let { hub ->
            hub.appDidBecomeActive()
            scope.launch { hub.refreshGrants() }
        }
    }

    fun onStop() {
        isStarted = false
        val scope = composition.appScope
        networkJob?.cancel()
        networkJob = null
        real.coordinator.hub.value?.let { background(it) }
        composition.active.value.scopes.current.value?.voice?.let { voice -> scope.launch { voice.cancelAll() } }
    }

    private fun background(hub: MachineHub) {
        backgrounded = hub
        // Never cancelled: the teardown completes anyway (carry 3D-5).
        composition.appScope.launch(start = CoroutineStart.UNDISPATCHED) { hub.appDidEnterBackground() }
    }

    private fun watchHubsWhileStopped() {
        composition.appScope.launch(start = CoroutineStart.UNDISPATCHED) {
            real.coordinator.hub.collect { hub ->
                if (hub != null && !isStarted && hub !== backgrounded) background(hub)
            }
        }
    }
}
