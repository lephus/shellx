package com.shellx.app

import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.diagnostics.LatencyMetric
import com.shellx.core.platform.Clock

/**
 * Measures from when the composition was built (`LaunchMark.swift`): `launchToHome`, to when the home first shows, and
 * `launchToWorkspaceList`, to when the default Mac's workspace list first arrives. One sample of each per launch, and
 * none for a launch that had to sign in or pair first ([skip]). Main-confined.
 */
class LaunchMark(private val latency: LatencyLog, clock: Clock) {
    private val start = clock.monotonic.markNow()
    private var homeDone = false
    private var listDone = false

    fun homeShown() {
        if (homeDone) return
        homeDone = true
        latency.record(LatencyMetric.LAUNCH_TO_HOME, start.elapsedNow())
    }

    /** The default Mac's workspace list arrived. */
    fun workspacesListed() {
        if (listDone) return
        listDone = true
        latency.record(LatencyMetric.LAUNCH_TO_WORKSPACE_LIST, start.elapsedNow())
    }

    /** The launch did not go straight to the home (sign-in, or no Mac paired yet): no sample. */
    fun skip() {
        homeDone = true
        listDone = true
    }
}
