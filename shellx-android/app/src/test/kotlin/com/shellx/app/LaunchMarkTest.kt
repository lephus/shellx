package com.shellx.app

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.ManualClock
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.diagnostics.LatencyMetric
import kotlin.time.Duration.Companion.milliseconds
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

/** The launch's two latencies: one sample each per launch, none for a launch that signed in or paired first. */
@RunWith(AndroidJUnit4::class)
class LaunchMarkTest {
    @Test
    fun theWorkspaceListIsMeasuredOncePerLaunch() {
        val latency = LatencyLog()
        val clock = ManualClock()
        val launch = LaunchMark(latency, clock)

        clock.advance(400.milliseconds)
        launch.homeShown()
        assertNull("the home showed; no Mac has listed yet", latency.summary(LatencyMetric.LAUNCH_TO_WORKSPACE_LIST))
        clock.advance(300.milliseconds)
        launch.workspacesListed()
        launch.workspacesListed()

        assertEquals(1, latency.summary(LatencyMetric.LAUNCH_TO_HOME)?.count)
        assertEquals(400.milliseconds, latency.summary(LatencyMetric.LAUNCH_TO_HOME)?.p50)
        assertEquals("a list after the first is not a launch", 1, latency.summary(LatencyMetric.LAUNCH_TO_WORKSPACE_LIST)?.count)
        assertEquals(700.milliseconds, latency.summary(LatencyMetric.LAUNCH_TO_WORKSPACE_LIST)?.p50)
    }

    @Test
    fun aLaunchThatSignedInFirstHasNoSample() {
        val latency = LatencyLog()
        val launch = LaunchMark(latency, ManualClock())

        launch.skip()
        launch.homeShown()
        launch.workspacesListed()

        assertNull(latency.summary(LatencyMetric.LAUNCH_TO_HOME))
        assertNull(latency.summary(LatencyMetric.LAUNCH_TO_WORKSPACE_LIST))
    }
}
