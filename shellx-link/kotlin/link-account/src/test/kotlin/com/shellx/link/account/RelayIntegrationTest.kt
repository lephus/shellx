package com.shellx.link.account

import com.shellx.link.core.LinkClient
import com.shellx.link.core.LinkMessage
import com.shellx.link.core.NoiseRole
import com.shellx.link.core.NoiseStaticKey
import com.shellx.link.core.RelayCircuit
import com.shellx.link.core.RelayClientConnector
import com.shellx.link.core.RelayException
import com.shellx.link.core.SecureChannel
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.job
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.OkHttpClient
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable

/**
 * End to end against a real `cmux-relay serve` process. Run with
 * `CMUX_RELAY_BIN=<path to cmux-relay> gw :link-account:test --tests 'com.shellx.link.account.RelayIntegrationTest'`.
 * Without the variable every test is skipped.
 */
@EnabledIfEnvironmentVariable(named = "CMUX_RELAY_BIN", matches = ".+")
class RelayIntegrationTest {
    private companion object {
        const val SECRET = "0123456789abcdef0123456789abcdef"
        const val OTHER_SECRET = "fedcba9876543210fedcba9876543210"
    }

    private val http = OkHttpClient()
    private val sockets = OkHttpRelaySockets(http)
    private val minter = TestTicketMinter(SECRET)
    private val hosts = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private lateinit var relay: RelayProcess

    @BeforeEach
    fun startRelay() {
        relay = RelayProcess.start(System.getenv("CMUX_RELAY_BIN"), SECRET)
    }

    @AfterEach
    fun stopRelay() {
        runBlocking {
            // A host that ignores cancellation must not hang the suite.
            withTimeoutOrNull(10.seconds) { hosts.coroutineContext.job.cancelAndJoin() }
        }
        relay.stop()
        http.dispatcher.executorService.shutdown()
        http.connectionPool.evictAll()
    }

    private fun startHost(slot: String, onCircuit: suspend (RelayCircuit) -> Unit) {
        TestRelayHost(sockets, relay.url, slot, minter).start(hosts, onCircuit)
    }

    private suspend fun echo(circuit: RelayCircuit) {
        try {
            while (true) circuit.send(circuit.receive())
        } catch (e: CancellationException) {
            throw e
        } catch (_: RelayException) {
            // The client left.
        }
    }

    /** Connects as a client, retrying while the host has not registered the slot yet (up to 10 s). */
    private suspend fun connectWhenOnline(slot: String): RelayCircuit {
        val deadline = TimeSource.Monotonic.markNow() + 10.seconds
        while (true) {
            try {
                return RelayClientConnector.connect(
                    relay.url, slot, minter.mint("connect", slot), sockets, slotOfflineRetries = emptyList(),
                )
            } catch (e: RelayException.Server) {
                if (e != RelayException.Server("slot-offline", true) || deadline.hasPassedNow()) throw e
                delay(50)
            }
        }
    }

    @Test
    fun clientAndHostExchangeBytes() {
        runBlocking {
            startHost("s1", ::echo)
            val client = within(15.seconds) { connectWhenOnline("s1") }
            client.send(byteArrayOf(1, 2))
            assertContentEquals(byteArrayOf(1, 2), within { client.receive() })
            client.close()
        }
    }

    @Test
    fun badTicketSurfacesServerError() {
        runBlocking {
            startHost("s1") { }
            // The slot is online, so the failure below is about the ticket only.
            within(15.seconds) { connectWhenOnline("s1") }.close()
            val forged = TestTicketMinter(OTHER_SECRET).mint("connect", "s1")
            val error = within {
                assertFailsWith<RelayException.Server> { RelayClientConnector.connect(relay.url, "s1", forged, sockets) }
            }
            assertEquals(RelayException.Server("invalid-ticket", false), error)
        }
    }

    @Test
    fun connectRetriesSlotOffline() {
        runBlocking {
            val ticket = minter.mint("connect", "s1")
            val connecting = async { RelayClientConnector.connect(relay.url, "s1", ticket, sockets) }
            delay(300)
            startHost("s1", ::echo)
            val circuit = within(15.seconds) { connecting.await() }
            circuit.send(byteArrayOf(9))
            assertContentEquals(byteArrayOf(9), within { circuit.receive() })
            circuit.close()

            // With no retries the same situation is reported, not hidden.
            val error = within {
                assertFailsWith<RelayException.Server> {
                    RelayClientConnector.connect(relay.url, "nobody", minter.mint("connect", "nobody"), sockets, slotOfflineRetries = emptyList())
                }
            }
            assertEquals(RelayException.Server("slot-offline", true), error)
        }
    }

    @Test
    fun linkSessionRunsOverTheRealRelay() {
        runBlocking {
            val hostKey = NoiseStaticKey.generate()
            startHost("s1") { circuit ->
                val channel = SecureChannel.open(circuit, NoiseRole.RESPONDER, hostKey) { true }
                channel.receive() as LinkMessage.Hello
                channel.send(LinkMessage.Welcome(1, "test-host", "Test Mac", emptyList()))
                while (true) {
                    val request = channel.receive()
                    if (request is LinkMessage.SnapshotGet) channel.send(LinkMessage.Snapshot(request.callId, 3, emptyList()))
                }
            }
            val client = within(15.seconds) {
                LinkClient.connect(connectWhenOnline("s1"), NoiseStaticKey.generate(), hostKey.publicKey, "1.0.0", "Pixel 9")
            }
            assertEquals(3, within { client.snapshot() }.revision)
            client.close()
        }
    }
}
