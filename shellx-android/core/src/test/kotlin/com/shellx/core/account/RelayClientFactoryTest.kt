package com.shellx.core.account

import com.shellx.link.core.RelayException
import java.net.InetAddress
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlinx.coroutines.test.runTest
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.OkHttpClient

class RelayClientFactoryTest {
    @Test fun versionHeaderIsTheBareVersion() { runTest {
        val server = MockWebServer().apply { start(InetAddress.getByName("127.0.0.1"), 0) }
        val okHttp = OkHttpClient()
        try {
            server.enqueue(MockResponse.Builder().code(204).build())
            val relay = RelayClientFactory.make("http://127.0.0.1:${server.port}", "2.0.0", okHttp)
            relay.logout("t")
            val request = assertNotNull(server.takeRequest(5, TimeUnit.SECONDS))
            assertEquals("/v1/auth/logout", request.url.encodedPath)
            assertEquals("2.0.0", request.headers["X-ShellX-Version"])
        } finally {
            server.close()
            okHttp.dispatcher.executorService.shutdown()
            okHttp.connectionPool.evictAll()
        }
    } }

    @Test fun headerVersionMatchesTheRelayPattern() {
        assertEquals("2.10.3", RelayClientFactory.headerVersion("2.10.3"))
        for (bad in listOf("ios/2.0.0", "2.0", "2.0.0-beta", "1234567.0.0", "", "?")) {
            assertEquals("0.0.0", RelayClientFactory.headerVersion(bad), bad)
        }
    }

    @Test fun insecureBaseIsRefused() {
        assertIs<RelayException.InsecureTransport>(assertFails { RelayClientFactory.make("http://relay.example.test", "2.0.0") })
    }
}
