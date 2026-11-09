package com.shellx.link.core

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NoiseTest {
    private val r = "r".encodeToByteArray()
    private val i = "i".encodeToByteArray()

    /** Runs XX with payloads "", "r" and "i", checking each, and returns the two completed handshakes. */
    private fun handshake(iKey: NoiseStaticKey, rKey: NoiseStaticKey): Pair<NoiseHandshake, NoiseHandshake> {
        val initiator = NoiseHandshake(NoiseRole.INITIATOR, iKey)
        val responder = NoiseHandshake(NoiseRole.RESPONDER, rKey)
        assertContentEquals(ByteArray(0), responder.readMessage(initiator.writeMessage()))
        assertContentEquals(r, initiator.readMessage(responder.writeMessage(r)))
        assertFalse(initiator.isComplete)
        assertContentEquals(i, responder.readMessage(initiator.writeMessage(i)))
        assertTrue(initiator.isComplete)
        assertTrue(responder.isComplete)
        return initiator to responder
    }

    private fun transports(): Pair<NoiseTransport, NoiseTransport> {
        val (initiator, responder) = handshake(NoiseStaticKey.generate(), NoiseStaticKey.generate())
        return initiator.split() to responder.split()
    }

    @Test
    fun roundTripWithRandomKeys() {
        val iKey = NoiseStaticKey.generate()
        val rKey = NoiseStaticKey.generate()
        assertEquals(32, iKey.publicKey.size)
        assertEquals(32, iKey.rawPrivate.size)
        assertFalse(iKey.publicKey.contentEquals(rKey.publicKey))
        assertContentEquals(iKey.publicKey, NoiseStaticKey.fromPrivate(iKey.rawPrivate).publicKey)

        val (initiator, responder) = handshake(iKey, rKey)
        assertContentEquals(rKey.publicKey, initiator.remoteStatic)
        assertContentEquals(iKey.publicKey, responder.remoteStatic)
        assertContentEquals(initiator.handshakeHash, responder.handshakeHash)

        val iT = initiator.split()
        val rT = responder.split()
        val hello = "hello mac".encodeToByteArray()
        assertContentEquals(hello, rT.decrypt(iT.encrypt(hello)))
        val back = "hello phone".encodeToByteArray()
        assertContentEquals(back, iT.decrypt(rT.encrypt(back)))
        assertFailsWith<NoiseException.BadMessage> { initiator.split() }
    }

    @Test
    fun untrustedPeerIsRejectedAndForgotten() {
        val iKey = NoiseStaticKey.generate()
        val rKey = NoiseStaticKey.generate()

        // The initiator distrusts the responder: rejected while reading message 2.
        val seen = mutableListOf<ByteArray>()
        val initiator = NoiseHandshake(NoiseRole.INITIATOR, iKey, trusts = { seen += it; false })
        val responder = NoiseHandshake(NoiseRole.RESPONDER, rKey)
        responder.readMessage(initiator.writeMessage())
        val message2 = responder.writeMessage("hello-r".encodeToByteArray())
        assertFailsWith<NoiseException.UntrustedPeer> { initiator.readMessage(message2) }
        assertEquals(1, seen.size)
        assertContentEquals(rKey.publicKey, seen.single())
        assertFalse(initiator.isComplete)
        assertNull(initiator.remoteStatic, "a rejected key is not kept")
        assertFailsWith<NoiseException.BadMessage> { initiator.writeMessage() }

        // The responder distrusts the initiator: rejected while reading message 3.
        val initiator2 = NoiseHandshake(NoiseRole.INITIATOR, iKey)
        val responder2 = NoiseHandshake(NoiseRole.RESPONDER, rKey, trusts = { !it.contentEquals(iKey.publicKey) })
        responder2.readMessage(initiator2.writeMessage())
        initiator2.readMessage(responder2.writeMessage())
        val message3 = initiator2.writeMessage("hello-i".encodeToByteArray())
        assertFailsWith<NoiseException.UntrustedPeer> { responder2.readMessage(message3) }
        assertFalse(responder2.isComplete)
        assertNull(responder2.remoteStatic, "a rejected key is not kept")
        assertFailsWith<NoiseException.BadMessage> { responder2.split() }
    }

    @Test
    fun throwingTrustsPoisonsTheHandshake() {
        // Whatever `trusts` throws, the decrypted but unproven key is dropped and the handshake is dead.
        val cases: List<Pair<Throwable, (Throwable) -> Boolean>> = listOf(
            AssertionError("boom") to { e -> e is AssertionError },
            NotImplementedError() to { e -> e is NotImplementedError },
            kotlin.coroutines.cancellation.CancellationException("gone") to
                { e -> e is kotlin.coroutines.cancellation.CancellationException },
            IllegalStateException("x") to { e -> e is NoiseException.BadMessage },
        )
        for ((thrown, expected) in cases) {
            val name = thrown::class.simpleName
            val initiator = NoiseHandshake(NoiseRole.INITIATOR, NoiseStaticKey.generate(), trusts = { throw thrown })
            val responder = NoiseHandshake(NoiseRole.RESPONDER, NoiseStaticKey.generate())
            responder.readMessage(initiator.writeMessage())
            val message2 = responder.writeMessage()
            val error = runCatching { initiator.readMessage(message2) }.exceptionOrNull()
            assertTrue(error != null && expected(error), "$name became $error")
            assertNull(initiator.remoteStatic, "$name: an unproven key is not kept")
            assertFalse(initiator.isComplete, "$name")
            assertFailsWith<NoiseException.BadMessage>("$name") { initiator.writeMessage() }
            assertFailsWith<NoiseException.BadMessage>("$name") { initiator.readMessage(message2) }
        }
    }

    @Test
    fun tamperedMessagesFail() {
        // Transport: one flipped bit anywhere fails authentication.
        val (iT, rT) = transports()
        val ciphertext = iT.encrypt("ping".encodeToByteArray())
        for (bit in listOf(0, 7, ciphertext.size * 8 - 1)) {
            val tampered = ciphertext.copyOf()
            tampered[bit / 8] = (tampered[bit / 8].toInt() xor (1 shl (bit % 8))).toByte()
            assertFailsWith<NoiseException.DecryptFailed>("bit $bit") { rT.decrypt(tampered) }
        }
        // A failed decrypt does not consume the nonce: the genuine message still opens.
        assertContentEquals("ping".encodeToByteArray(), rT.decrypt(ciphertext))

        // Handshake: flip a bit in the encrypted static key of message 2.
        val initiator = NoiseHandshake(NoiseRole.INITIATOR, NoiseStaticKey.generate())
        val responder = NoiseHandshake(NoiseRole.RESPONDER, NoiseStaticKey.generate())
        responder.readMessage(initiator.writeMessage())
        val message2 = responder.writeMessage("hello-r".encodeToByteArray())
        message2[40] = (message2[40].toInt() xor 1).toByte()
        assertFailsWith<NoiseException.DecryptFailed> { initiator.readMessage(message2) }
        assertNull(initiator.remoteStatic)

        // Handshake: `s` decrypts and is trusted, but the payload tag fails, so the unproven key is dropped.
        val initiator2 = NoiseHandshake(NoiseRole.INITIATOR, NoiseStaticKey.generate())
        val responder2 = NoiseHandshake(NoiseRole.RESPONDER, NoiseStaticKey.generate())
        responder2.readMessage(initiator2.writeMessage())
        val message2b = responder2.writeMessage("hello-r".encodeToByteArray())
        message2b[message2b.size - 1] = (message2b[message2b.size - 1].toInt() xor 1).toByte()
        assertFailsWith<NoiseException.DecryptFailed> { initiator2.readMessage(message2b) }
        assertNull(initiator2.remoteStatic)
        assertFalse(initiator2.isComplete)
    }

    @Test
    fun nonceCountsPerFrameAndCapsFrameSize() {
        val (iT, rT) = transports()
        val plaintext = "same".encodeToByteArray()
        val first = iT.encrypt(plaintext)
        val second = iT.encrypt(plaintext)
        assertFalse(first.contentEquals(second))
        assertEquals(plaintext.size + 16, first.size)
        assertEquals(plaintext.size + 16, second.size)

        // Out of order: the receiver expects nonce 0, so the second frame does not open yet.
        assertFailsWith<NoiseException.DecryptFailed> { rT.decrypt(second) }
        assertContentEquals(plaintext, rT.decrypt(first))
        assertContentEquals(plaintext, rT.decrypt(second))
        // A replay of a used nonce is rejected.
        assertFailsWith<NoiseException.DecryptFailed> { rT.decrypt(first) }

        // Frames are capped at 65 535 bytes of ciphertext.
        assertEquals(NoiseTransport.MAX_MESSAGE_BYTES, iT.encrypt(ByteArray(65_519)).size)
        assertFailsWith<NoiseException.BadMessage> { iT.encrypt(ByteArray(65_520)) }
        assertFailsWith<NoiseException.BadMessage> { rT.decrypt(ByteArray(65_536)) }
    }

    @Test
    fun exhaustedNonceIsRefused() {
        val state = CipherState(ByteArray(32), ULong.MAX_VALUE - 1u)
        assertEquals(17, state.encrypt(ByteArray(0), "x".encodeToByteArray()).size)
        assertFailsWith<NoiseException.NonceExhausted> { state.encrypt(ByteArray(0), "x".encodeToByteArray()) }
    }

    @Test
    fun fromPrivateRejectsWrongLength() {
        assertFailsWith<IllegalArgumentException> { NoiseStaticKey.fromPrivate(ByteArray(31)) }
    }

    @Test
    fun toStringHidesThePrivateKey() {
        val key = NoiseStaticKey.generate()
        val text = key.toString()
        assertFalse(key.rawPrivate.toHex() in text, text)
        assertFalse(key.rawPrivate.toBase64() in text, text)
        assertFalse(key.rawPrivate.toBase64Url() in text, text)
        assertEquals("NoiseStaticKey(<redacted>)", text)
    }

    @Test
    fun turnsAreEnforced() {
        val initiator = NoiseHandshake(NoiseRole.INITIATOR, NoiseStaticKey.generate())
        val responder = NoiseHandshake(NoiseRole.RESPONDER, NoiseStaticKey.generate())
        assertFailsWith<NoiseException.BadMessage> { responder.writeMessage() }
        assertFailsWith<NoiseException.BadMessage> { responder.split() }
        val initiator2 = NoiseHandshake(NoiseRole.INITIATOR, NoiseStaticKey.generate())
        assertFailsWith<NoiseException.BadMessage> { initiator2.readMessage(ByteArray(32)) }
        // A short message 1 is malformed.
        assertFailsWith<NoiseException.BadMessage> { responder.readMessage(initiator.writeMessage().copyOf(31)) }
    }
}
