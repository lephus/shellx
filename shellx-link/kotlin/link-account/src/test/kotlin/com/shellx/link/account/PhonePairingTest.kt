package com.shellx.link.account

import com.shellx.link.core.PairingOffer
import com.shellx.link.core.PairingOfferException
import java.util.Base64
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import mockwebserver3.Dispatcher
import mockwebserver3.MockResponse
import mockwebserver3.RecordedRequest
import mockwebserver3.SocketEffect
import org.junit.jupiter.api.Test

class PhonePairingTest {
    private val clientKey = ByteArray(32) { (0x20 + it).toByte() }
    private val hostKey = ByteArray(32) { (0x40 + it).toByte() }
    private val machineId = "6f1c2b7e-0d4a-4c1e-9a53-3b8e5d2f7a10"
    private val offer = PairingOffer.make(machineId, "slot-1", hostKey, "Mac")

    /** Serves `POST /v2/phone-pairings`, the polls of `p-1` (answered by poll index) and its `deny`. */
    private class PairingRelay(private val poll: (Int) -> MockResponse) : Dispatcher() {
        val posts = CopyOnWriteArrayList<RecordedRequest>()
        val gets = CopyOnWriteArrayList<RecordedRequest>()
        val denyCalls = AtomicInteger()
        private val polls = AtomicInteger()

        override fun dispatch(request: RecordedRequest): MockResponse {
            val path = request.url.encodedPath
            return when {
                request.method == "POST" && path == "/v2/phone-pairings" -> {
                    posts += request
                    json(201, """{"pairing_id":"p-1"}""")
                }
                request.method == "GET" && path == "/v2/phone-pairings/p-1" -> {
                    gets += request
                    poll(polls.getAndIncrement())
                }
                request.method == "POST" && path == "/v2/phone-pairings/p-1/deny" -> {
                    denyCalls.incrementAndGet()
                    MockResponse.Builder().code(204).build()
                }
                else -> json(404, """{"error":{"code":"not_found","message":"x"}}""")
            }
        }
    }

    private companion object {
        fun json(status: Int, body: String): MockResponse =
            MockResponse.Builder().code(status).addHeader("Content-Type", "application/json").body(body).build()

        val pending = json(200, """{"status":"pending"}""")

        fun approved(machineId: String = "6f1c2b7e-0d4a-4c1e-9a53-3b8e5d2f7a10", slot: String = "slot-1"): MockResponse =
            json(200, """{"status":"approved","machine":{"machine_id":"$machineId","name":"Relay Name","link_slot":"$slot"}}""")

        /** Pending twice, then [final]. */
        fun afterTwoPolls(final: MockResponse): (Int) -> MockResponse = { if (it < 2) pending else final }
    }

    private suspend fun ApiServer.pair(
        relay: PairingRelay,
        offerUri: String = offer.uri,
        pollInterval: Duration = 5.milliseconds,
        timeout: Duration = PairingOffer.LIFETIME,
        api: RelayApi = api(),
        onRequested: (String) -> Unit = {},
    ): PairedMachine {
        server.dispatcher = relay
        return PhonePairing.pair(offerUri, clientKey, api, "tok", pollInterval, timeout, onRequested)
    }

    @Test
    fun pollsUntilApproved() {
        runBlocking {
            ApiServer().use { s ->
                val relay = PairingRelay(afterTwoPolls(approved()))
                val machine = s.pair(relay)
                assertEquals(machineId, machine.machineId)
                assertEquals("slot-1", machine.linkSlot)
                assertEquals("Mac", machine.name)
                assertContentEquals(hostKey, machine.hostKey)
                assertEquals(3, relay.gets.size)
                assertEquals(0, relay.denyCalls.get())
                val body = relay.posts.single().json()
                assertEquals(machineId, body.text("machine_id"))
                assertEquals(Base64.getEncoder().encodeToString(clientKey), body.text("client_key_b64"))
                assertEquals(Base64.getEncoder().encodeToString(offer.proof(clientKey)), body.text("proof_b64"))
                assertEquals("Bearer tok", relay.gets.first().headers["Authorization"])
            }
        }
    }

    @Test
    fun deniedThrowsWithoutCancel() {
        runBlocking {
            ApiServer().use { s ->
                val relay = PairingRelay(afterTwoPolls(json(200, """{"status":"denied"}""")))
                assertFailsWith<PhonePairingException.Denied> { s.pair(relay) }
                assertEquals(0, relay.denyCalls.get())
            }
        }
    }

    @Test
    fun expiredThrows() {
        runBlocking {
            ApiServer().use { s ->
                val relay = PairingRelay(afterTwoPolls(json(200, """{"status":"expired"}""")))
                assertFailsWith<PhonePairingException.Expired> { s.pair(relay) }
                assertEquals(0, relay.denyCalls.get())
            }
        }
    }

    @Test
    fun hostKeyComesFromTheOffer() {
        runBlocking {
            ApiServer().use { s ->
                // Even if the relay offered a key, the stored host key is the one in the QR offer.
                val answer = json(
                    200,
                    """{"status":"approved","machine":{"machine_id":"$machineId","name":"Relay Name","link_slot":"slot-1",""" +
                        """"host_key":"AAAA","fingerprint":"ff"}}""",
                )
                val machine = s.pair(PairingRelay(afterTwoPolls(answer)))
                assertContentEquals(hostKey, machine.hostKey)
                assertEquals("Mac", machine.name)
            }
        }
    }

    @Test
    fun mismatchedApprovalCancelsOnce() {
        runBlocking {
            for (answer in listOf(approved(slot = "evil-slot"), approved(machineId = "00000000-0000-4000-8000-000000000000"))) {
                ApiServer().use { s ->
                    val relay = PairingRelay(afterTwoPolls(answer))
                    assertFailsWith<RelayApiException.BadResponse> { s.pair(relay) }
                    assertEquals(1, relay.denyCalls.get())
                }
            }
        }
    }

    @Test
    fun clientDeadlineExpiresAndCancels() {
        runBlocking {
            ApiServer().use { s ->
                val relay = PairingRelay { pending }
                assertFailsWith<PhonePairingException.Expired> { s.pair(relay, timeout = 60.milliseconds) }
                assertEquals(1, relay.denyCalls.get())
                assertTrue(relay.gets.size >= 2, "polled ${relay.gets.size} times")
            }
        }
    }

    @Test
    fun cancellationCancelsThePairing() {
        runBlocking {
            ApiServer().use { s ->
                val relay = PairingRelay { pending }
                val job = launch(Dispatchers.Default) { s.pair(relay, pollInterval = 20.milliseconds) }
                delay(80)
                within { job.cancelAndJoin() }
                assertTrue(job.isCancelled)
                assertEquals(1, relay.denyCalls.get())
            }
        }
    }

    @Test
    fun transientErrorsAreRetried() {
        runBlocking {
            ApiServer().use { s ->
                val dropped = MockResponse.Builder().code(200).body("{}").onResponseStart(SocketEffect.CloseSocket()).build()
                val relay = PairingRelay {
                    when (it) {
                        0 -> json(503, """{"error":{"code":"relay_v2_unavailable","message":"x"}}""")
                        1 -> MockResponse.Builder().code(502).build()
                        2 -> dropped
                        else -> approved()
                    }
                }
                // OkHttp would retry the dropped GET on its own and hide the IOException from PhonePairing.
                val noRetry = s.client.newBuilder().retryOnConnectionFailure(false).build()
                assertEquals(machineId, s.pair(relay, api = RelayApi(s.base, noRetry, "9.9.9")).machineId)
                assertEquals(4, relay.gets.size, "each transient failure is its own poll")
                assertEquals(0, relay.denyCalls.get())
            }
        }
    }

    @Test
    fun clientErrorAborts() {
        runBlocking {
            ApiServer().use { s ->
                val relay = PairingRelay { json(404, """{"error":{"code":"pairing_not_found","message":"x"}}""") }
                assertEquals(
                    RelayApiException.Http(404, "pairing_not_found"),
                    assertFailsWith<RelayApiException.Http> { s.pair(relay) },
                )
                assertEquals(1, relay.gets.size)
                assertEquals(1, relay.denyCalls.get())
            }
        }
    }

    @Test
    fun reportsTheIdBeforeItPolls() {
        runBlocking {
            ApiServer().use { s ->
                var reported: Pair<String, Int>? = null
                s.pair(PairingRelay(afterTwoPolls(approved())), onRequested = { reported = it to s.server.requestCount })
                assertEquals("p-1" to 1, reported)
            }
        }
    }

    @Test
    fun throwingOnRequestedCancelsThePairing() {
        runBlocking {
            ApiServer().use { s ->
                val relay = PairingRelay(afterTwoPolls(approved()))
                val error = assertFailsWith<IllegalStateException> { s.pair(relay, onRequested = { error("the UI is gone") }) }
                assertEquals("the UI is gone", error.message)
                assertEquals(0, relay.gets.size)
                assertEquals(1, relay.denyCalls.get())
            }
        }
    }

    @Test
    fun badOfferNeverReachesTheRelay() {
        runBlocking {
            ApiServer().use { s ->
                val relay = PairingRelay { pending }
                assertFailsWith<PairingOfferException.BadUri> { s.pair(relay, offerUri = "https://example.com") }
                assertEquals(0, s.server.requestCount)
            }
        }
    }

    @Test
    fun pairedMachineEqualityUsesKeyContent() {
        val a = PairedMachine("m1", "Mac", "slot-1", hostKey.copyOf())
        val b = PairedMachine("m1", "Mac", "slot-1", hostKey.copyOf())
        assertEquals(a, b)
        assertEquals(a.hashCode(), b.hashCode())
        assertNotEquals(a, b.copy(hostKey = ByteArray(32)))
        assertTrue(a.toString().contains("<32 bytes>"), a.toString())
    }

    @Test
    fun pairingTypesNeverPrintNamesOrKeys() {
        val printed = listOf(
            PairedMachine("m1", "Phu's Mac", "slot-1", hostKey).toString(),
            PhonePairingException.Denied().toString(),
            PhonePairingException.Expired().toString(),
        )
        for (text in printed) {
            assertFalse(text.contains("Phu's Mac"), text)
            assertFalse(text.contains(hostKey.contentToString()) || text.contains(Base64.getEncoder().encodeToString(hostKey)), text)
        }
    }
}
