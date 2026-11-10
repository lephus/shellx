package com.shellx.app.platform

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.link.NetworkChangeFilter
import com.shellx.core.link.NetworkPath
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowNetwork
import org.robolectric.shadows.ShadowNetworkCapabilities

@RunWith(AndroidJUnit4::class)
class NetworkPathWatcherTest {
    @Test
    fun pathsDecideOnInternetInterfaceAndGateways() {
        assertEquals(
            NetworkPath("satisfied", listOf("wlan0"), listOf("192.168.1.1")),
            NetworkPaths.of(true, "wlan0", listOf("192.168.1.1")),
        )
        assertEquals("unsatisfied", NetworkPaths.of(false, null, emptyList()).status)
        assertEquals(NetworkPaths.of(true, "wlan0", listOf("192.168.1.1")), NetworkPaths.of(true, "wlan0", listOf("192.168.1.1")))
        assertNotEquals(NetworkPaths.of(true, "wlan0", listOf("192.168.1.1")), NetworkPaths.of(true, "wlan0", listOf("10.0.0.1")))
    }

    @Test
    fun theWatcherStartsWithTheCurrentPathAndUnregisters() {
        val cm = ApplicationProvider.getApplicationContext<Context>().getSystemService(ConnectivityManager::class.java)
        val path = runBlocking { NetworkPathWatcher(cm).paths.first() }
        assertNotNull(path)
        assertTrue(shadowOf(cm).networkCallbacks.isEmpty())
    }

    private val cm: ConnectivityManager =
        ApplicationProvider.getApplicationContext<Context>().getSystemService(ConnectivityManager::class.java)

    private fun internet(): NetworkCapabilities = ShadowNetworkCapabilities.newInstance().also {
        shadowOf(it).addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    private fun link(name: String) = LinkProperties().apply { interfaceName = name }

    /** Watches through 3C's change filter, as AppLifecycle does; returns the paths seen and the changes reported. */
    private class Watch {
        val paths = mutableListOf<NetworkPath>()
        var changes = 0
    }

    private fun TestScope.watch(): Watch {
        val watch = Watch()
        val filter = NetworkChangeFilter(backgroundScope) { watch.changes++ }
        backgroundScope.launch { NetworkPathWatcher(cm).paths.collect { watch.paths += it; filter.receive(it) } }
        runCurrent()
        return watch
    }

    /** What ConnectivityService sends a default-network callback for [network] (NetworkCallback.onAvailable's order). */
    private fun replay(network: Network, caps: NetworkCapabilities, link: LinkProperties) {
        val callback = shadowOf(cm).networkCallbacks.single()
        callback.onAvailable(network)
        callback.onCapabilitiesChanged(network, caps)
        callback.onLinkPropertiesChanged(network, link)
    }

    @Test
    fun aRegistrationReplayOfTheSameNetworkIsNoChange() { // review A I-1: every ON_START registers again
        runTest {
            val network = cm.activeNetwork!!
            val caps = internet()
            val wifi = link("wlan0")
            shadowOf(cm).setNetworkCapabilities(network, caps)
            shadowOf(cm).setLinkProperties(network, wifi)
            val watch = watch()
            replay(network, caps, wifi)
            runCurrent()
            advanceTimeBy(1_000)
            runCurrent()
            assertEquals(0, watch.changes)
            assertTrue(watch.paths.toString(), watch.paths.all { it.primaryInterface == "wlan0" })
        }
    }

    @Test
    fun aSwitchToAnotherNetworkIsOneChangeWithNoInterfacelessPath() {
        runTest {
            val wifiNetwork = cm.activeNetwork!!
            val caps = internet()
            val wifi = link("wlan0")
            shadowOf(cm).setNetworkCapabilities(wifiNetwork, caps)
            shadowOf(cm).setLinkProperties(wifiNetwork, wifi)
            val watch = watch()
            replay(wifiNetwork, caps, wifi)
            advanceTimeBy(1_000)
            runCurrent()
            replay(ShadowNetwork.newInstance(77), internet(), link("rmnet0"))
            shadowOf(cm).networkCallbacks.single().onLost(wifiNetwork) // the old default's loss, after the new one
            runCurrent()
            advanceTimeBy(1_000)
            runCurrent()
            assertEquals(1, watch.changes)
            assertEquals("rmnet0", watch.paths.last().primaryInterface)
            assertTrue(watch.paths.toString(), watch.paths.none { it.primaryInterface == null })
        }
    }
}
