package com.shellx.link.core

import java.io.IOException
import java.net.URI
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

class RelayClientConnectorTest {
    private val relayUrl = URI("wss://relay.example.test/v2/relay")
    private val ticket = RelayTicket("v2.eyJzbG90Ijoic2xvdC0xIn0.sig", 1_900_000_000)
    private val lanePattern = Regex("[A-Za-z0-9_-]{32}")

    /** The lane of the `connect` in [sent]; null for another message. */
    private fun connectLane(sent: String): String? = (RelayControl.decode(sent) as? RelayControl.Connect)?.lane

    /** A control socket that allocates `c-1` for the lane it is asked for, and a circuit socket that is ready. */
    private fun allocating(control: (Int) -> Boolean = { it == 0 }) = ScriptedRelaySockets { index, sent ->
        val decoded = RelayControl.decode(sent)
        when {
            control(index) && decoded is RelayControl.Connect -> listOf(
                text(RelayControl.Ping(9u)),
                text(RelayControl.Allocated("c-1", decoded.lane, 0u, "jt-1")),
            )
            decoded is RelayControl.Join -> listOf(text(RelayControl.Ready("c-1", decoded.lane, 0u)))
            else -> emptyList()
        }
    }

    @Test
    fun connectAllocatesThenJoins() {
        runBlocking {
            within {
                val sockets = allocating()
                val circuit = RelayClientConnector.connect(relayUrl, "slot-1", ticket, sockets)
                assertEquals(2, sockets.opened.size)
                val control = sockets.opened[0]
                assertEquals(URI("wss://relay.example.test/v2/relay"), control.url)
                assertEquals(ticket.ticket, control.bearer)
                assertTrue(control.closed, "the control socket stays open")
                val connect = control.sentControl[0] as RelayControl.Connect
                assertEquals(5, connect.protocol)
                assertEquals("slot-1", connect.slot)
                assertEquals(ticket.ticket, connect.ticket)
                assertEquals(0u, connect.generation)
                assertTrue(lanePattern.matches(connect.lane), connect.lane)
                // The relay's ping is answered on the control socket, before the join.
                assertEquals(listOf(RelayControl.Pong(9u)), control.sentControl.drop(1))

                val join = sockets.opened[1]
                assertEquals(URI("wss://relay.example.test/v2/relay"), join.url)
                assertEquals("jt-1", join.bearer)
                assertEquals(
                    listOf(RelayControl.Join(5, "slot-1", "c-1", connect.lane, 0u, "jt-1", RelayRole.CLIENT)),
                    join.sentControl,
                )

                circuit.send(byteArrayOf(1))
                assertContentEquals(byteArrayOf(1), join.sentBinary.single())
                sockets.push(1, RelaySocketMessage.Binary(byteArrayOf(2)))
                assertContentEquals(byteArrayOf(2), circuit.receive())
                circuit.close()
                assertTrue(join.closed)
            }
        }
    }

    @Test
    fun allocationForAnotherLaneIsIgnored() {
        runBlocking {
            within {
                val sockets = ScriptedRelaySockets { _, sent ->
                    val decoded = RelayControl.decode(sent)
                    when (decoded) {
                        is RelayControl.Connect -> listOf(
                            text(RelayControl.Allocated("c-x", "x", 0u, "jt-x")),
                            text(RelayControl.Allocated("c-1", decoded.lane, 0u, "jt-1")),
                        )
                        is RelayControl.Join -> listOf(text(RelayControl.Ready("c-1", decoded.lane, 0u)))
                        else -> emptyList()
                    }
                }
                RelayClientConnector.connect(relayUrl, "slot-1", ticket, sockets).close()
                assertEquals("jt-1", sockets.opened[1].bearer)
                assertEquals("c-1", (sockets.opened[1].sentControl.single() as RelayControl.Join).circuit)
            }
        }
    }

    @Test
    fun slotOfflineIsRetriedWithTheSameTicket() {
        runBlocking {
            within {
                val sockets = ScriptedRelaySockets { index, sent ->
                    val decoded = RelayControl.decode(sent)
                    when {
                        decoded is RelayControl.Connect && index < 2 ->
                            listOf(text(RelayControl.Error("slot-offline", "", true)))
                        decoded is RelayControl.Connect ->
                            listOf(text(RelayControl.Allocated("c-1", decoded.lane, 0u, "jt-1")))
                        decoded is RelayControl.Join -> listOf(text(RelayControl.Ready("c-1", decoded.lane, 0u)))
                        else -> emptyList()
                    }
                }
                val circuit = RelayClientConnector.connect(
                    relayUrl, "slot-1", ticket, sockets, slotOfflineRetries = listOf(10.milliseconds, 10.milliseconds),
                )
                circuit.close()
                assertEquals(4, sockets.opened.size)
                val controls = sockets.opened.take(3)
                assertTrue(controls.all { it.bearer == ticket.ticket && it.closed })
                assertTrue(controls.all { (it.sentControl.single() as RelayControl.Connect).ticket == ticket.ticket })
                assertEquals("jt-1", sockets.opened[3].bearer)
            }
        }
    }

    @Test
    fun slotOfflineAfterTheRetriesIsReported() {
        runBlocking {
            within {
                val sockets = ScriptedRelaySockets { _, _ -> listOf(text(RelayControl.Error("slot-offline", "", true))) }
                val error = assertFailsWith<RelayException.Server> {
                    RelayClientConnector.connect(relayUrl, "slot-1", ticket, sockets, slotOfflineRetries = emptyList())
                }
                assertEquals(RelayException.Server("slot-offline", true), error)
                assertEquals(1, sockets.opened.size)
                assertTrue(sockets.opened[0].closed)
            }
        }
    }

    @Test
    fun joinErrorIsReportedAndTheSocketClosed() {
        runBlocking {
            within {
                val sockets = ScriptedRelaySockets { _, sent ->
                    when (val decoded = RelayControl.decode(sent)) {
                        is RelayControl.Connect -> listOf(text(RelayControl.Allocated("c-1", decoded.lane, 0u, "jt-1")))
                        is RelayControl.Join -> listOf(text(RelayControl.Error("invalid-ticket", "", false)))
                        else -> emptyList()
                    }
                }
                val error = assertFailsWith<RelayException.Server> {
                    RelayClientConnector.connect(relayUrl, "slot-1", ticket, sockets)
                }
                assertEquals(RelayException.Server("invalid-ticket", false), error)
                assertEquals(2, sockets.opened.size)
                assertTrue(sockets.opened[1].closed)
            }
        }
    }

    @Test
    fun silenceTimesOut() {
        runBlocking {
            within {
                val sockets = ScriptedRelaySockets()
                assertFailsWith<RelayException.TimedOut> {
                    RelayClientConnector.connect(relayUrl, "slot-1", ticket, sockets, controlTimeout = 100.milliseconds)
                }
                assertEquals(1, sockets.opened.size)
                assertTrue(sockets.opened[0].closed)
            }
        }
    }

    @Test
    fun silentJoinTimesOut() {
        runBlocking {
            within {
                val sockets = ScriptedRelaySockets { _, sent ->
                    when (val decoded = RelayControl.decode(sent)) {
                        is RelayControl.Connect -> listOf(text(RelayControl.Allocated("c-1", decoded.lane, 0u, "jt-1")))
                        else -> emptyList()
                    }
                }
                assertFailsWith<RelayException.TimedOut> {
                    RelayClientConnector.connect(relayUrl, "slot-1", ticket, sockets, controlTimeout = 100.milliseconds)
                }
                assertEquals(2, sockets.opened.size)
                assertTrue(sockets.opened[1].closed)
            }
        }
    }

    @Test
    fun binaryBeforeAllocationIsAViolation() {
        runBlocking {
            within {
                val sockets = ScriptedRelaySockets { _, _ -> listOf(RelaySocketMessage.Binary(byteArrayOf(1))) }
                val error = assertFailsWith<RelayException.ProtocolViolation> {
                    RelayClientConnector.connect(relayUrl, "slot-1", ticket, sockets)
                }
                assertEquals(RelayException.ProtocolViolation("relay sent binary data before the circuit was ready"), error)
                assertTrue(sockets.opened[0].closed)
            }
        }
    }

    @Test
    fun socketFailurePassesThroughUnchanged() {
        runBlocking {
            within {
                val failure = IOException("connection refused")
                val sockets = ScriptedRelaySockets()
                launch {
                    eventually { sockets.opened.isNotEmpty() }
                    sockets.opened[0].fail(failure)
                }
                val error = assertFailsWith<IOException> { RelayClientConnector.connect(relayUrl, "slot-1", ticket, sockets) }
                // The same IOException, or (with coroutine stack-trace recovery under -ea) a copy that has it as cause.
                assertTrue(error === failure || error.cause === failure, "got $error")
                assertEquals("connection refused", error.message)
                assertTrue(sockets.opened[0].closed)
            }
        }
    }
}
