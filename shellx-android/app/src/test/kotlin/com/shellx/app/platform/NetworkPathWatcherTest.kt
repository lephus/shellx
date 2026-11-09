package com.shellx.app.platform

import android.content.Context
import android.net.ConnectivityManager
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.link.NetworkPath
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

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
}
