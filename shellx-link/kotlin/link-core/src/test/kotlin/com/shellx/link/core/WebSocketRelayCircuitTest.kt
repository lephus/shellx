package com.shellx.link.core

import java.io.IOException
import java.net.URI
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

class WebSocketRelayCircuitTest {
    private fun socket() = Opened(URI("wss://relay.example.test/v2/relay"), "jt-1")

    @Test
    fun relayPingIsAnsweredAndNotDelivered() {
        runBlocking {
            within {
                val socket = socket()
                val circuit = WebSocketRelayCircuit(socket)
                socket.push(text(RelayControl.Ping(4u)))
                socket.push(text(RelayControl.Pong(3u)))
                socket.push(RelaySocketMessage.Binary(byteArrayOf(7)))
                assertContentEquals(byteArrayOf(7), circuit.receive())
                assertEquals(listOf<RelayControl>(RelayControl.Pong(4u)), socket.sentControl)
            }
        }
    }

    @Test
    fun peerDisconnectedIsAPlainClose() {
        runBlocking {
            within {
                val socket = socket()
                val circuit = WebSocketRelayCircuit(socket)
                socket.push(text(RelayControl.Error("peer-disconnected", "", false)))
                assertFailsWith<RelayException.Closed> { circuit.receive() }
                assertTrue(socket.closed)
            }
        }
    }

    @Test
    fun otherRelayErrorIsServer() {
        runBlocking {
            within {
                val socket = socket()
                val circuit = WebSocketRelayCircuit(socket)
                socket.push(text(RelayControl.Error("capacity", "", true)))
                assertEquals(RelayException.Server("capacity", true), assertFailsWith<RelayException.Server> { circuit.receive() })
                assertTrue(socket.closed)
            }
        }
    }

    @Test
    fun unexpectedControlIsAViolation() {
        runBlocking {
            within {
                for (frame in listOf(text(RelayControl.Registered(60)), RelaySocketMessage.Text("not json"))) {
                    val socket = socket()
                    val circuit = WebSocketRelayCircuit(socket)
                    socket.push(frame)
                    val error = assertFailsWith<RelayException.ProtocolViolation> { circuit.receive() }
                    assertEquals(RelayException.ProtocolViolation("relay sent unexpected circuit control"), error)
                    assertTrue(socket.closed)
                }
            }
        }
    }

    @Test
    fun socketFailuresBecomeClosed() {
        runBlocking {
            within {
                val socket = socket()
                val circuit = WebSocketRelayCircuit(socket)
                socket.fail(IOException("reset"))
                assertFailsWith<RelayException.Closed> { circuit.receive() }

                val sending = socket()
                sending.failSends = IOException("broken pipe")
                assertFailsWith<RelayException.Closed> { WebSocketRelayCircuit(sending).send(byteArrayOf(1)) }

                val closed = socket()
                closed.close()
                assertFailsWith<RelayException.Closed> { WebSocketRelayCircuit(closed).send(byteArrayOf(1)) }
                assertFailsWith<RelayException.Closed> { WebSocketRelayCircuit(closed).receive() }
            }
        }
    }

    @Test
    fun cancellingAPendingReceiveClosesTheSocket() {
        runBlocking {
            within {
                val socket = socket()
                val circuit = WebSocketRelayCircuit(socket)
                // Undispatched: the job runs until its receive() suspends.
                val waiting = launch(start = CoroutineStart.UNDISPATCHED) { circuit.receive() }
                assertFalse(socket.closed)
                waiting.cancelAndJoin()
                assertTrue(socket.closed)
            }
        }
    }

    @Test
    fun socketMessagesNeverPrintTheirContent() {
        val ticket = "v2.secret-ticket.sig"
        val text = RelaySocketMessage.Text(RelayControl.Connect(5, "slot-1", ticket, "lane", 0u).encodeText())
        assertFalse(ticket in text.toString(), text.toString())
        assertEquals("Binary(<3 bytes>)", RelaySocketMessage.Binary(byteArrayOf(1, 2, 3)).toString())
        assertEquals(RelaySocketMessage.Binary(byteArrayOf(1, 2)), RelaySocketMessage.Binary(byteArrayOf(1, 2)))
        assertEquals(
            RelaySocketMessage.Binary(byteArrayOf(1, 2)).hashCode(),
            RelaySocketMessage.Binary(byteArrayOf(1, 2)).hashCode(),
        )
        assertNotEquals(RelaySocketMessage.Binary(byteArrayOf(1)), RelaySocketMessage.Binary(byteArrayOf(2)))
    }
}
