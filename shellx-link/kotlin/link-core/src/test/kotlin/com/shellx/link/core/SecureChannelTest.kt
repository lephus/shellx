package com.shellx.link.core

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

class SecureChannelTest {
    private val clientKey = NoiseStaticKey.generate()
    private val hostKey = NoiseStaticKey.generate()

    /** A circuit that flips one bit of the next frame it sends once [armed]. */
    private class TamperingCircuit(private val inner: RelayCircuit) : RelayCircuit by inner {
        @Volatile var armed = false

        override suspend fun send(data: ByteArray) {
            if (armed) {
                armed = false
                inner.send(data.copyOf().also { it[it.size - 1] = (it[it.size - 1].toInt() xor 1).toByte() })
            } else {
                inner.send(data)
            }
        }
    }

    @Test
    fun handshakeCarriesMessagesBothWays() {
        runBlocking {
            within {
                val (a, b) = inMemoryCircuitPair()
                val host = async { SecureChannel.open(b, NoiseRole.RESPONDER, hostKey) { it.contentEquals(clientKey.publicKey) } }
                val client = SecureChannel.open(a, NoiseRole.INITIATOR, clientKey) { it.contentEquals(hostKey.publicKey) }
                val server = host.await()
                assertContentEquals(hostKey.publicKey, client.peerKey)
                assertContentEquals(clientKey.publicKey, server.peerKey)

                val hello = LinkMessage.Hello("1.0.0", "Pixel 9")
                client.send(hello)
                assertEquals(hello, server.receive())
                val welcome = LinkMessage.Welcome(1, "h", "m", listOf("attachments"))
                server.send(welcome)
                assertEquals(welcome, client.receive())
                client.close()
            }
        }
    }

    @Test
    fun initiatorRejectsAWrongHostKeyBeforeMessage3() {
        runBlocking {
            within {
                val (a, b) = inMemoryCircuitPair()
                val expected = NoiseStaticKey.generate()
                val impostor = async {
                    val responder = NoiseHandshake(NoiseRole.RESPONDER, hostKey)
                    responder.readMessage(b.receive())
                    b.send(responder.writeMessage())
                }
                assertFailsWith<NoiseException.UntrustedPeer> {
                    SecureChannel.open(a, NoiseRole.INITIATOR, clientKey) { it.contentEquals(expected.publicKey) }
                }
                impostor.await()
                // Message 3 was never sent: it would arrive before the close.
                assertFailsWith<RelayException.Closed> { b.receive() }
            }
        }
    }

    @Test
    fun responderRejectsAnUntrustedClientAfterMessage3() {
        runBlocking {
            within {
                val (a, b) = inMemoryCircuitPair()
                val host = async {
                    assertFailsWith<NoiseException.UntrustedPeer> { SecureChannel.open(b, NoiseRole.RESPONDER, hostKey) { false } }
                }
                // The initiator completes its side; the responder then closes the circuit.
                val client = SecureChannel.open(a, NoiseRole.INITIATOR, clientKey) { true }
                host.await()
                assertFailsWith<RelayException.Closed> { client.receive() }
            }
        }
    }

    @Test
    fun nonEmptyHandshakePayloadAborts() {
        runBlocking {
            within {
                val (a, b) = inMemoryCircuitPair()
                val raw = NoiseHandshake(NoiseRole.INITIATOR, clientKey)
                a.send(raw.writeMessage("hi".encodeToByteArray()))
                assertFailsWith<NoiseException.NonEmptyHandshakePayload> {
                    SecureChannel.open(b, NoiseRole.RESPONDER, hostKey) { true }
                }
                // The responder closed the circuit without sending message 2.
                assertFailsWith<RelayException.Closed> { a.receive() }
            }
        }
    }

    @Test
    fun undecodableFrameKeepsTheChannel() {
        runBlocking {
            within {
                val (client, server) = pair(inMemoryCircuitPair())
                client.sendFrame("""{"v":1,"t":"ping"}""".encodeToByteArray())
                assertEquals(LinkCodecException.BadJson(null), assertFailsWith<LinkCodecException.BadJson> { server.receive() })
                client.send(LinkMessage.Ping(7u))
                assertEquals(LinkMessage.Ping(7u), server.receive())
                client.close()
            }
        }
    }

    @Test
    fun unencodableMessageSendsNothingAndKeepsTheChannel() {
        runBlocking {
            within {
                val (client, server) = pair(inMemoryCircuitPair())
                assertFailsWith<LinkCodecException.BadJson> { client.send(LinkMessage.SnapshotGet("")) }
                assertFailsWith<LinkCodecException.FrameTooLarge> {
                    client.send(LinkMessage.ChatSend("c1", "s-1", "x".repeat(LinkCodec.MAX_FRAME_BYTES)))
                }
                client.send(LinkMessage.Ping(1u))
                assertEquals(LinkMessage.Ping(1u), server.receive())
                client.close()
            }
        }
    }

    @Test
    fun tamperedFrameClosesTheCircuit() {
        runBlocking {
            within {
                val (a, b) = inMemoryCircuitPair()
                val tampering = TamperingCircuit(a)
                val (client, server) = pair(tampering to b)
                tampering.armed = true
                client.send(LinkMessage.Ping(1u))
                assertFailsWith<NoiseException.DecryptFailed> { server.receive() }
                assertFailsWith<RelayException.Closed> { client.send(LinkMessage.Ping(2u)) }
            }
        }
    }

    @Test
    fun concurrentSendsAllDecrypt() {
        runBlocking {
            within {
                // A send that suspends between encryption and delivery: frames still leave in nonce order.
                val (a, b) = inMemoryCircuitPair()
                val (client, server) = pair(SuspendingSendCircuit(a) to b)
                val received = async { List(200) { server.receive() } }
                (0 until 200).map { i -> async(Dispatchers.Default) { client.send(LinkMessage.Ping(i.toULong())) } }.awaitAll()
                val nonces = received.await().map { (it as LinkMessage.Ping).nonce }
                assertEquals((0uL until 200uL).toSet(), nonces.toSet())
                assertEquals(200, nonces.size)
                client.close()
            }
        }
    }

    /**
     * Review Focus 1 at the channel: a sender cancelled while its encrypted frame is suspended in the circuit's send
     * still sends it, so the nonce it spent is never skipped.
     */
    @Test
    fun cancelledSendersNeverDesyncTheCipher() {
        runBlocking {
            within {
                val (a, b) = inMemoryCircuitPair()
                val (client, server) = pair(SuspendingSendCircuit(a) to b)
                // Deterministic: each sender takes the free lock, encrypts, and suspends in the circuit's send;
                // every odd one is cancelled right there.
                for (i in 0 until 50) {
                    val sender = launch(start = CoroutineStart.UNDISPATCHED) { client.send(LinkMessage.Ping(i.toULong())) }
                    if (i % 2 == 1) sender.cancel()
                    sender.join()
                }
                // Concurrent: 200 senders on Dispatchers.Default, every odd one cancelled at once.
                val senders = (50 until 250).map { i ->
                    launch(Dispatchers.Default, start = CoroutineStart.UNDISPATCHED) { client.send(LinkMessage.Ping(i.toULong())) }
                }
                senders.forEachIndexed { k, sender -> if (k % 2 == 1) sender.cancel() }
                senders.joinAll()
                client.send(LinkMessage.Ping(999u))
                val nonces = mutableListOf<ULong>()
                while (true) {
                    val nonce = (server.receive() as LinkMessage.Ping).nonce
                    if (nonce == 999uL) break
                    nonces += nonce
                }
                // Every frame decrypted; each sequential sender sent its frame, cancelled or not.
                assertEquals((0uL until 50uL).toList(), nonces.take(50))
                assertTrue(nonces.drop(50).all { it in 50uL until 250uL } && nonces.drop(50).size >= 100, "$nonces")
                client.close()
            }
        }
    }

    @Test
    fun peerKeyIsACopy() {
        runBlocking {
            within {
                val (client, _) = pair(inMemoryCircuitPair())
                client.peerKey.fill(0)
                assertContentEquals(hostKey.publicKey, client.peerKey)
                client.close()
            }
        }
    }

    /** Opens both ends: the client initiates on `first`, the host responds on `second`. */
    private suspend fun pair(ends: Pair<RelayCircuit, RelayCircuit>): Pair<SecureChannel, SecureChannel> = within {
        val host = async { SecureChannel.open(ends.second, NoiseRole.RESPONDER, hostKey) { true } }
        val client = SecureChannel.open(ends.first, NoiseRole.INITIATOR, clientKey) { it.contentEquals(hostKey.publicKey) }
        client to host.await()
    }
}
