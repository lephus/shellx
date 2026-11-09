package com.shellx.core.link

import com.shellx.core.account.AccountVault
import com.shellx.core.account.RelayClientFactory
import com.shellx.core.account.StoredSession
import com.shellx.core.testing.InMemorySecretStore
import com.shellx.core.testing.assertSameCase
import com.shellx.link.account.PairedMachine
import com.shellx.link.account.RelayApiException
import java.net.InetAddress
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertTrue
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runTest
import mockwebserver3.Dispatcher
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.RecordedRequest
import okhttp3.OkHttpClient

class RelayMachineConnectorTest {
    private val machine = PairedMachine("m1", "Mac", "s1", ByteArray(32) { 1 })

    @Test fun eachConnectReadsTheLatestTokenFromTheVault() { runTest {
        // Answers every request like a relay that no longer grants the machine, and records what it saw.
        val requests = CopyOnWriteArrayList<Pair<String, String?>>()
        val server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                requests += request.url.encodedPath to request.headers["Authorization"]
                return MockResponse.Builder().code(403).addHeader("Content-Type", "application/json")
                    .body("""{"error":{"code":"not_granted","message":"no"}}""").build()
            }
        }
        server.start(InetAddress.getByName("127.0.0.1"), 0)
        val okHttp = OkHttpClient()
        try {
            val vault = AccountVault(InMemorySecretStore(), StandardTestDispatcher(testScheduler))
            val connector = RelayClientFactory.makeConnector("http://127.0.0.1:${server.port}", "2.0.0", vault, "iPhone", okHttp)

            // Without a session it fails as a refused token would, before any request.
            val signedOut = assertFails { connector.connect(machine) }
            assertEquals(LinkFailure.SIGNED_OUT, LinkFailure.of(signedOut))
            assertTrue(requests.isEmpty())

            for (token in listOf("tok-1", "tok-2")) {
                vault.setSession(StoredSession("u1", "d1", token, "a@b.c"))
                val error = assertFails { connector.connect(machine) }
                assertSameCase(RelayApiException.Http(403, "not_granted"), error)
                assertEquals(LinkFailure.REVOKED, LinkFailure.of(error))
            }
            assertEquals(listOf("/v2/relay/tickets", "/v2/relay/tickets"), requests.map { it.first })
            assertEquals(listOf("Bearer tok-1", "Bearer tok-2"), requests.map { it.second })
        } finally {
            server.close()
            okHttp.dispatcher.executorService.shutdown()
            okHttp.connectionPool.evictAll()
        }
    } }
}
