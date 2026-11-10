package com.shellx.app.demo

import com.shellx.app.AccountGraph
import com.shellx.core.demo.DemoEnvironment
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * "Try without an account" (S1 §6.6, S3 §6.1), as 1C's `DemoSession`: the demo runs over the real app, in memory and
 * its own folder, until Exit. Each run gets a child scope of `appScope`, which Exit cancels. Main-confined.
 */
class DemoSession(
    private val appScope: CoroutineScope,
    private val makeEnvironment: (CoroutineScope) -> DemoEnvironment,
    private val graphOf: (DemoEnvironment, CoroutineScope) -> AccountGraph,
) {
    private class Run(val environment: DemoEnvironment, val scope: CoroutineScope, var starting: Job? = null)

    private val _graph = MutableStateFlow<AccountGraph?>(null)

    /** The demo's account while it runs; null otherwise. */
    val graph: StateFlow<AccountGraph?> = _graph.asStateFlow()

    private var run: Run? = null

    /**
     * No-op while one runs. Makes the run's child scope and its graph first (the screens switch to the demo), then
     * `prepare()` and `coordinator.launch()`, detached in that scope: cancelling the caller only ends its wait. It never
     * writes the clipboard (Spec note 4).
     */
    suspend fun start() {
        if (run != null) return
        val scope = CoroutineScope(appScope.coroutineContext + SupervisorJob(appScope.coroutineContext[Job]))
        val environment = makeEnvironment(scope)
        val current = Run(environment, scope)
        run = current
        _graph.value = graphOf(environment, scope)
        val starting = scope.launch {
            environment.prepare()
            environment.coordinator.launch()
        }
        current.starting = starting
        starting.join()
    }

    /** "Demo · Exit": the graph goes first (the screens leave), then the script and the hub stop, then the run's scope
     *  ends. Detached in the app scope, like [start]. */
    suspend fun exit() {
        val current = run ?: return
        run = null
        _graph.value = null
        appScope.launch {
            try {
                current.starting?.cancel()
                current.environment.exit()
            } finally {
                current.scope.cancel()
            }
        }.join()
    }
}
