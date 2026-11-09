@file:OptIn(ExperimentalCoroutinesApi::class)

package com.shellx.app

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.testComposition
import com.shellx.app.testing.waitFor
import com.shellx.app.ui.nav.Routes
import com.shellx.core.account.AppPhase
import com.shellx.core.demo.FakeMac
import com.shellx.core.diagnostics.LatencyMetric
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.NetworkPath
import java.io.File
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith

/** The process lifecycle: the account launches at the first start in front, and the links follow ON_START/ON_STOP. */
@RunWith(AndroidJUnit4::class)
class AppLifecycleTest {
    @get:Rule val folder = TemporaryFolder()

    private fun path(name: String) = NetworkPath("satisfied", listOf(name), listOf("192.168.1.1"))

    @Test
    fun aBackgroundStartConnectsNothing() {
        runTest {
            val mac = FakeMac("MacBook Pro", backgroundScope)
            val t = testComposition(folder.root, macs = listOf(mac))

            advanceUntilIdle()

            assertEquals("a push may start the process; nothing connects", 0, mac.connectCount)
            assertEquals(0, t.network.subscribers)
            assertEquals(AppPhase.Launching, t.composition.real.coordinator.phase.value)
        }
    }

    @Test
    fun theFirstStartLaunchesTheAccountAndWatchesTheNetwork() {
        runTest {
            val mac = FakeMac("MacBook Pro", backgroundScope)
            val t = testComposition(folder.root, macs = listOf(mac))
            val c = t.composition

            c.lifecycle.onStart()

            assertTrue(c.lifecycle.isStarted)
            assertTrue(waitFor { c.root.value == Routes.HOME && online(c) })
            assertEquals(1, mac.connectCount)
            assertEquals(1, t.network.subscribers)
        }
    }

    @Test
    fun stoppingClosesTheLinksAfterTheGrace() {
        runTest {
            val mac = FakeMac("MacBook Pro", backgroundScope)
            val t = testComposition(folder.root, macs = listOf(mac))
            val c = t.composition
            c.lifecycle.onStart()
            assertTrue(waitFor { online(c) })

            c.lifecycle.onStop()

            assertTrue(waitFor { t.network.subscribers == 0 })
            advanceTimeBy(24.seconds)
            assertEquals("the grace is 25 s", 1, mac.liveSessionCount)
            advanceTimeBy(2.seconds)
            assertTrue(waitFor { mac.liveSessionCount == 0 })

            c.lifecycle.onStart()
            assertTrue(waitFor { mac.connectCount == 2 && online(c) })
        }
    }

    @Test
    fun aNetworkChangeWhileStartedReplacesTheLinks() {
        runTest {
            val mac = FakeMac("MacBook Pro", backgroundScope)
            val t = testComposition(folder.root, macs = listOf(mac))
            val c = t.composition
            c.lifecycle.onStart()
            assertTrue(waitFor { online(c) })

            t.network.flow.emit(path("wlan0"))
            t.network.flow.emit(path("rmnet0"))
            advanceTimeBy(301.milliseconds)

            assertTrue(waitFor { mac.connectCount == 2 })
        }
    }

    @Test
    fun aSettlePendingAtStopNeverReconnects() {
        runTest {
            val mac = FakeMac("MacBook Pro", backgroundScope)
            val t = testComposition(folder.root, macs = listOf(mac))
            val c = t.composition
            c.lifecycle.onStart()
            assertTrue(waitFor { online(c) })

            // Two path changes start a 300 ms settle; the app stops before it ends (review B m-3).
            t.network.flow.emit(path("wlan0"))
            t.network.flow.emit(path("rmnet0"))
            advanceTimeBy(100.milliseconds)
            c.lifecycle.onStop()
            advanceTimeBy(1.seconds)

            assertEquals("a settle pending at ON_STOP never reconnects", 1, mac.connectCount)
        }
    }

    @Test
    fun everyStartAsksAgain() {
        runTest {
            val mac = FakeMac("MacBook Pro", backgroundScope)
            val t = testComposition(folder.root, macs = listOf(mac))
            val c = t.composition
            c.lifecycle.onStart()
            assertTrue("the first start has no hub yet, so it asks nothing", waitFor { online(c) })

            c.lifecycle.onStop()
            c.lifecycle.onStart()
            assertTrue(waitFor { t.relay.calls.count { it == "machines" } == 1 })

            c.lifecycle.onStop()
            c.lifecycle.onStart()
            assertTrue(waitFor { t.relay.calls.count { it == "machines" } == 2 })
        }
    }

    @Test
    fun aLaunchWithoutAMacTakesNoLaunchSample() {
        runTest {
            val none = testComposition(File(folder.root, "none")).composition
            none.lifecycle.onStart()
            assertTrue(waitFor { none.root.value == Routes.FIRST_MAC })
            none.real.launch.homeShown()
            assertNull(none.latency.summary(LatencyMetric.LAUNCH_TO_HOME))

            val mac = FakeMac("MacBook Pro", backgroundScope)
            val one = testComposition(File(folder.root, "one"), macs = listOf(mac)).composition
            one.lifecycle.onStart()
            assertTrue(waitFor { one.root.value == Routes.HOME })
            one.real.launch.homeShown()
            assertEquals(1, one.latency.summary(LatencyMetric.LAUNCH_TO_HOME)?.count)
        }
    }

    /** 3D note 8: FCM may start the process in the background; its launch counts from the first start in front. */
    @Test
    fun aProcessAPushStartedMeasuresItsLaunchFromTheFirstStart() {
        runTest {
            val mac = FakeMac("MacBook Pro", backgroundScope)
            val t = testComposition(folder.root, macs = listOf(mac))
            val c = t.composition
            t.clock.advance(30.seconds)

            c.lifecycle.onStart()
            assertTrue(waitFor { c.root.value == Routes.HOME })
            t.clock.advance(400.milliseconds)
            c.real.launch.homeShown()

            assertEquals(400.milliseconds, c.latency.summary(LatencyMetric.LAUNCH_TO_HOME)?.p50)
        }
    }

    @Test
    fun aHubMadeAfterTheAppStoppedClosesItsLinksAfterTheGrace() {
        runTest {
            val mac = FakeMac("MacBook Pro", backgroundScope)
            val t = testComposition(folder.root, macs = listOf(mac))
            val c = t.composition

            // The launch finishes after ON_STOP (3C final review m-7).
            c.lifecycle.onStart()
            c.lifecycle.onStop()
            assertTrue(waitFor { mac.liveSessionCount == 1 })

            advanceTimeBy(26.seconds)
            assertTrue("the new hub got the background grace", waitFor { mac.liveSessionCount == 0 })
        }
    }

    private fun online(c: AppComposition): Boolean {
        val machines = c.real.coordinator.hub.value?.machines.orEmpty()
        return machines.isNotEmpty() && machines.all { it.state == MachineLinkState.Online }
    }
}
