package com.shellx.link.account

import com.shellx.link.core.PairingOffer
import com.shellx.link.core.RelayException
import com.shellx.link.core.RelayTicket
import java.io.IOException
import java.net.ServerSocket
import java.net.URI
import java.util.Base64
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import mockwebserver3.MockResponse
import org.junit.jupiter.api.Test

class RelayApiTest {
    private val clientKey = ByteArray(32) { (0x20 + it).toByte() }
    private val hostKey = ByteArray(32) { (0x40 + it).toByte() }
    private val offer = PairingOffer.make("6f1c2b7e-0d4a-4c1e-9a53-3b8e5d2f7a10", "slot-1", hostKey, "Mac")

    private val grants = """{"grants":[{"grant_id":"g1","machine_id":"m1","name":"Mac","platform":"macos",""" +
        """"online":true,"link_slot":"slot-1","fingerprint":"ab:cd"}]}"""

    private fun ticketReply(ticket: String, relayUrl: String = "wss://relay.example.test/v2/relay"): String =
        """{"ticket":"$ticket","expires_at_unix":1900000000,"relay_url":"$relayUrl"}"""

    @Test
    fun requestPairingPostsKeyAndProof() {
        runBlocking {
            ApiServer().use { s ->
                s.reply(201, """{"pairing_id":"p-1"}""")
                assertEquals("p-1", s.api().requestPairing(offer, clientKey, "tok"))
                val request = s.take()
                assertEquals("POST", request.method)
                assertEquals("/v2/phone-pairings", request.url.encodedPath)
                assertEquals("Bearer tok", request.headers["Authorization"])
                assertEquals("application/json", request.headers["Content-Type"])
                val body = request.json()
                assertEquals(offer.machineId, body.text("machine_id"))
                assertEquals(Base64.getEncoder().encodeToString(clientKey), body.text("client_key_b64"))
                assertEquals(Base64.getEncoder().encodeToString(offer.proof(clientKey)), body.text("proof_b64"))
                assertEquals(setOf("machine_id", "client_key_b64", "proof_b64"), body.keys)
            }
        }
    }

    @Test
    fun unsafePairingIdFromTheRelayIsBadResponse() {
        runBlocking {
            ApiServer().use { s ->
                for (id in listOf("../x", "", "a".repeat(65), "p 1")) {
                    s.reply(201, """{"pairing_id":"$id"}""")
                    assertFailsWith<RelayApiException.BadResponse>(id) { s.api().requestPairing(offer, clientKey, "tok") }
                }
            }
        }
    }

    @Test
    fun pairingStatusMapsEveryStatus() {
        runBlocking {
            ApiServer().use { s ->
                val api = s.api()
                s.reply(200, """{"status":"pending"}""")
                assertEquals(PhonePairingStatus.Pending, api.pairingStatus("p-1", "tok"))
                val request = s.take()
                assertEquals("GET", request.method)
                assertEquals("/v2/phone-pairings/p-1", request.url.encodedPath)
                assertEquals("Bearer tok", request.headers["Authorization"])
                s.reply(200, """{"status":"denied"}""")
                assertEquals(PhonePairingStatus.Denied, api.pairingStatus("p-1", "tok"))
                s.reply(200, """{"status":"expired"}""")
                assertEquals(PhonePairingStatus.Expired, api.pairingStatus("p-1", "tok"))
                s.reply(200, """{"status":"approved","machine":{"machine_id":"m1","name":"Mac","link_slot":"slot-1"}}""")
                assertEquals(PhonePairingStatus.Approved("m1", "Mac", "slot-1"), api.pairingStatus("p-1", "tok"))
                s.reply(200, """{"status":"approved"}""")
                assertFailsWith<RelayApiException.BadResponse> { api.pairingStatus("p-1", "tok") }
                s.reply(200, """{"status":"later"}""")
                assertFailsWith<RelayApiException.BadResponse> { api.pairingStatus("p-1", "tok") }
            }
        }
    }

    @Test
    fun cancelPairingPostsDeny() {
        runBlocking {
            ApiServer().use { s ->
                s.reply(204)
                s.api().cancelPairing("p-1", "tok")
                val request = s.take()
                assertEquals("POST", request.method)
                assertEquals("/v2/phone-pairings/p-1/deny", request.url.encodedPath)
                assertEquals("Bearer tok", request.headers["Authorization"])
                assertEquals(0L, request.bodySize)
            }
        }
    }

    @Test
    fun unsafeIdsNeverReachThePath() {
        runBlocking {
            ApiServer().use { s ->
                val api = s.api()
                assertFailsWith<RelayApiException.BadResponse> { api.pairingStatus("../x", "tok") }
                assertFailsWith<RelayApiException.BadResponse> { api.cancelPairing("", "tok") }
                assertFailsWith<RelayApiException.BadResponse> { api.unpair("a/b", "tok") }
                assertFailsWith<RelayApiException.BadResponse> { api.unpair("a".repeat(65), "tok") }
                assertFailsWith<RelayApiException.BadResponse> { api.pairingStatus("é", "tok") }
                assertEquals(0, s.server.requestCount)
            }
        }
    }

    @Test
    fun machinesAndUnpair() {
        runBlocking {
            ApiServer().use { s ->
                val api = s.api()
                s.reply(200, grants)
                assertEquals(
                    listOf(PairedMachineListing("g1", "m1", "Mac", "macos", true, "slot-1", "ab:cd")),
                    api.machines("tok"),
                )
                val list = s.take()
                assertEquals("GET", list.method)
                assertEquals("/v2/phone-grants", list.url.encodedPath)
                s.reply(204)
                api.unpair("g1", "tok")
                val delete = s.take()
                assertEquals("DELETE", delete.method)
                assertEquals("/v2/phone-grants/g1", delete.url.encodedPath)
                assertEquals("Bearer tok", delete.headers["Authorization"])
            }
        }
    }

    @Test
    fun mintChecksPermissionThenSlot() {
        runBlocking {
            ApiServer().use { s ->
                val api = s.api()
                s.reply(200, ticketReply(stubTicket("other-slot")))
                assertFailsWith<RelayApiException.SlotMismatch> { api.mintConnectTicket("m1", "slot-1", "tok") }
                s.reply(200, ticketReply(stubTicket("slot-1", "register", "daemon")))
                assertFailsWith<RelayApiException.NotConnectTicket> { api.mintConnectTicket("m1", "slot-1", "tok") }
                // Permission is checked before the slot.
                s.reply(200, ticketReply(stubTicket("other-slot", "register", "daemon")))
                assertFailsWith<RelayApiException.NotConnectTicket> { api.mintConnectTicket("m1", "slot-1", "tok") }
                s.reply(200, ticketReply("garbage"))
                assertFailsWith<RelayApiException.BadResponse> { api.mintConnectTicket("m1", "slot-1", "tok") }
                s.reply(200, ticketReply(stubTicket("slot-1"), relayUrl = "not a url"))
                assertFailsWith<RelayApiException.BadResponse> { api.mintConnectTicket("m1", "slot-1", "tok") }
                s.reply(200, ticketReply(stubTicket("slot-1"), relayUrl = "relay.example.test/v2/relay"))
                assertFailsWith<RelayApiException.BadResponse> { api.mintConnectTicket("m1", "slot-1", "tok") }
                repeat(6) { s.take() }

                val good = stubTicket("slot-1")
                s.reply(200, ticketReply(good))
                assertEquals(
                    MintedTicket(RelayTicket(good, 1_900_000_000), URI("wss://relay.example.test/v2/relay")),
                    api.mintConnectTicket("m1", "slot-1", "tok"),
                )
                val request = s.take()
                assertEquals("POST", request.method)
                assertEquals("/v2/relay/tickets", request.url.encodedPath)
                assertEquals("Bearer tok", request.headers["Authorization"])
                assertEquals("""{"permission":"connect","lane":"link","target_machine_id":"m1"}""", request.body?.utf8())
            }
        }
    }

    @Test
    fun httpErrorsSurfaceTheirCode() {
        runBlocking {
            ApiServer().use { s ->
                val api = s.api()
                s.reply(403, """{"error":{"code":"not_granted","message":"no"}}""")
                assertEquals(RelayApiException.Http(403, "not_granted"), assertFailsWith<RelayApiException.Http> { api.machines("tok") })
                s.reply(502)
                assertEquals(RelayApiException.Http(502, "unknown"), assertFailsWith<RelayApiException.Http> { api.unpair("g1", "tok") })
                s.reply(500, """{"error":{"code":7}}""")
                assertEquals(RelayApiException.Http(500, "unknown"), assertFailsWith<RelayApiException.Http> { api.machines("tok") })
                // An error body that is not strict JSON has no code.
                s.reply(403, """{"error":{"code":"not_granted"},"x":NaN}""")
                assertEquals(RelayApiException.Http(403, "unknown"), assertFailsWith<RelayApiException.Http> { api.machines("tok") })
            }
        }
    }

    @Test
    fun redirectIsNotFollowed() {
        runBlocking {
            ApiServer().use { s ->
                s.reply(302, location = "${s.base}/steal")
                s.reply(200, grants)
                assertEquals(RelayApiException.Http(302, "unknown"), assertFailsWith<RelayApiException.Http> { s.api().machines("tok") })
                assertEquals(1, s.server.requestCount)
            }
        }
    }

    @Test
    fun plainHttpRefusedForRemoteHost() {
        runBlocking {
            ApiServer().use { s ->
                assertEquals(
                    RelayException.InsecureTransport("http"),
                    assertFailsWith<RelayException.InsecureTransport> { RelayApi("http://api.example.test", s.client, "1") },
                )
                RelayApi("http://127.0.0.1:8080", s.client, "1")
                RelayApi("http://localhost:8080", s.client, "1")
                RelayApi("https://api.example.test", s.client, "1")
            }
        }
    }

    @Test
    fun hostIsCheckedOnTheParsedUrl() {
        runBlocking {
            ApiServer().use { s ->
                // isLoopback would take "127.+0.0.1" as a raw string; java.net.URI finds no host in it.
                for (bad in listOf("http://127.+0.0.1:8080", "not a url", "relay.example.test", "ftp://127.0.0.1")) {
                    assertFailsWith<RelayException.ProtocolViolation>(bad) { RelayApi(bad, s.client, "1") }
                }
                assertEquals(
                    RelayException.InsecureTransport("http"),
                    assertFailsWith<RelayException.InsecureTransport> { RelayApi("http://127.0.0.1@evil.example.test", s.client, "1") },
                )
            }
        }
    }

    @Test
    fun everyRequestCarriesTheVersionHeader() {
        runBlocking {
            ApiServer().use { s ->
                s.reply(200, grants)
                s.api(clientVersion = "9.9.9").machines("tok")
                val request = s.take()
                assertEquals("9.9.9", request.headers["X-ShellX-Version"])
                assertEquals("application/json", request.headers["Accept"])
                assertNull(request.headers["Content-Type"])
            }
        }
    }

    @Test
    fun malformedSuccessBodyIsBadResponse() {
        runBlocking {
            ApiServer().use { s ->
                val api = s.api()
                for (body in listOf(
                    "{",
                    """{"grants":[{"grant_id":1}]}""",
                    """{"grants":{}}""",
                    """{"grants":[1]}""",
                    """{"grants":[],"x":nope}""",
                    """{"grants":[],"x":01}""",
                    "",
                    "[]",
                )) {
                    s.reply(200, body)
                    assertFailsWith<RelayApiException.BadResponse>(body) { api.machines("tok") }
                }
                s.server.enqueue(MockResponse.Builder().code(200).body(okio.Buffer().write(byteArrayOf(0x7B, 0xFF.toByte(), 0x7D))).build())
                assertFailsWith<RelayApiException.BadResponse> { api.machines("tok") }
            }
        }
    }

    @Test
    fun baseUrlPathAndTrailingSlashJoinOnce() {
        runBlocking {
            ApiServer().use { s ->
                val bases = listOf(s.base, "${s.base}/", "${s.base}/api", "${s.base}/api/")
                val paths = bases.map { base ->
                    s.reply(200, grants)
                    s.api(base).machines("tok")
                    s.take().url.encodedPath
                }
                assertEquals(listOf("/v2/phone-grants", "/v2/phone-grants", "/api/v2/phone-grants", "/api/v2/phone-grants"), paths)
                assertEquals("${s.base}/api/", s.api("${s.base}/api/").baseUrl)
            }
        }
    }

    @Test
    fun ioErrorsPassThrough() {
        runBlocking {
            val closedPort = ServerSocket(0).use { it.localPort }
            ApiServer().use { s ->
                assertFailsWith<IOException> { s.api("http://127.0.0.1:$closedPort").machines("tok") }
            }
        }
    }

    @Test
    fun cancellingTheCallerCancelsTheRequest() {
        runBlocking {
            ApiServer().use { s ->
                s.server.enqueue(MockResponse.Builder().code(200).body(grants).headersDelay(30, TimeUnit.SECONDS).build())
                val call = async(Dispatchers.Default, start = CoroutineStart.UNDISPATCHED) { s.api().machines("tok") }
                assertNotNull(s.take())
                within(2.seconds) {
                    call.cancel()
                    call.join()
                    // OkHttp gives up the cancelled exchange instead of waiting out the 30 s delay.
                    while (s.client.dispatcher.runningCallsCount() > 0) delay(5)
                }
                assertTrue(call.isCancelled)
            }
        }
    }

    @Test
    fun apiValuesNeverPrintSecretsOrNames() {
        val session = AccountSession("u1", "d1", "tok-secret")
        val signIn = AccountSignIn(session, "a@b.c")
        val printed = listOf(
            session.toString(),
            signIn.toString(),
            PhonePairingStatus.Approved("m1", "Phu's Mac", "slot-1").toString(),
            PairedMachineListing("g1", "m1", "Phu's Mac", "macos", true, "slot-1", "ab:cd").toString(),
            MintedTicket(RelayTicket(stubTicket("slot-1"), 1), URI("wss://relay.example.test/v2/relay")).toString(),
            RelayApiException.Http(401, "invalid_credentials").toString(),
            RelayApiException.Http(401, "invalid_credentials").message.orEmpty(),
        )
        for (text in printed) {
            for (secret in listOf("tok-secret", "a@b.c", "Phu's Mac", stubTicket("slot-1"))) {
                assertFalse(text.contains(secret), "printed $secret: $text")
            }
        }
        assertEquals("AccountSession(user=u1, device=d1, <redacted>)", session.toString())
        assertEquals("AccountSignIn(user=u1, device=d1, <redacted>)", signIn.toString())
    }
}
