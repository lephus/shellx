package com.shellx.core.account

import com.shellx.link.account.AccountSession
import com.shellx.link.account.AccountSignIn
import java.net.InetAddress
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlinx.coroutines.test.runTest
import mockwebserver3.Dispatcher
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.RecordedRequest
import okhttp3.OkHttpClient

class RelayAccountClientTest {
    private fun json(status: Int, body: String): MockResponse =
        MockResponse.Builder().code(status).addHeader("Content-Type", "application/json").body(body).build()

    @Test fun everyCallReachesTheRelayApi() { runTest {
        val server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when ("${request.method} ${request.url.encodedPath}") {
                "POST /v1/auth/nonce" -> json(201, """{"nonce":"n1","expires_in":600}""")
                "POST /v1/auth/google" -> json(200, """{"user_id":"u1","device_id":"d1","token":"t1","email":"a@b.c"}""")
                "GET /v2/phone-grants" -> json(200, """{"grants":[]}""")
                else -> MockResponse.Builder().code(204).build()
            }
        }
        server.start(InetAddress.getByName("127.0.0.1"), 0)
        val okHttp = OkHttpClient()
        try {
            val relay = RelayClientFactory.make("http://127.0.0.1:${server.port}", "2.0.0", okHttp)

            assertEquals("n1", relay.nonce())
            val signIn = relay.signInWithGoogle("id", "n1", "Pixel", ByteArray(32))
            assertEquals(emptyList(), relay.machines("t1"))
            relay.unpair("g1", "t1")
            relay.setPushToken("fcm", "t1")
            relay.unsetPushToken("t1")
            relay.logout("t1")
            relay.deleteAccount("id2", "n2", "t1")

            val seen = List(8) {
                val request = assertNotNull(server.takeRequest(5, TimeUnit.SECONDS))
                "${request.method} ${request.url.encodedPath}"
            }
            assertEquals(
                listOf(
                    "POST /v1/auth/nonce", "POST /v1/auth/google", "GET /v2/phone-grants", "DELETE /v2/phone-grants/g1",
                    "PUT /v1/devices/me/push-token", "DELETE /v1/devices/me/push-token", "POST /v1/auth/logout",
                    "DELETE /v1/account",
                ),
                seen,
            )
            assertEquals(AccountSignIn(AccountSession("u1", "d1", "t1"), "a@b.c"), signIn)
        } finally {
            server.close()
            okHttp.dispatcher.executorService.shutdown()
            okHttp.connectionPool.evictAll()
        }
    } }
}
