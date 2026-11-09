package com.shellx.link.core

import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Noise over a [RelayCircuit]: one [LinkMessage] per Noise transport message (PROTOCOL.md sections 1 to 3).
 *
 * [send] may be called from several coroutines; frames go out in the order the calls take the send lock. [receive]
 * must be called from one coroutine at a time.
 */
class SecureChannel private constructor(
    private val circuit: RelayCircuit,
    private val transport: NoiseTransport,
    peerKey: ByteArray,
) {
    private val peer = peerKey.copyOf()

    /** A fair (FIFO) lock: a frame's nonce is spent and its ciphertext sent under it, in one step. */
    private val sendLock = Mutex()

    /** The peer's static public key, authenticated by the completed handshake; a copy. */
    val peerKey: ByteArray get() = peer.copyOf()

    /**
     * Encodes, encrypts and sends one message. A [LinkCodecException] means nothing was sent and the channel stays
     * usable; otherwise the circuit's error passes through.
     */
    suspend fun send(message: LinkMessage) = sendFrame(LinkCodec.encode(message))

    /**
     * Sends an already encoded frame; tests use it for frames [LinkCodec] cannot produce.
     *
     * A cancellation can land only while waiting for the lock (nothing spent) or after the send: encrypting spends
     * a nonce, so a frame that was encrypted is always sent, and a cancelled caller never desyncs the cipher stream.
     */
    internal suspend fun sendFrame(frame: ByteArray) {
        sendLock.withLock {
            withContext(NonCancellable) {
                circuit.send(transport.encrypt(frame))
            }
        }
    }

    /**
     * Receives, decrypts and decodes the next frame. A [LinkCodecException] means the frame was dropped and the channel
     * stays usable (the caller applies PROTOCOL.md section 7). A frame that fails to decrypt closes the circuit and
     * throws [NoiseException.DecryptFailed]; the circuit's errors pass through.
     */
    suspend fun receive(): LinkMessage {
        val ciphertext = circuit.receive()
        val plaintext = try {
            transport.decrypt(ciphertext)
        } catch (e: Exception) {
            circuit.close()
            throw e
        }
        return LinkCodec.decode(plaintext)
    }

    /** Closes the circuit. Idempotent. */
    fun close() = circuit.close()

    override fun toString(): String = "SecureChannel(<redacted>)"

    companion object {
        /**
         * Runs the XX handshake with empty payloads (PROTOCOL.md section 2). The client is the initiator.
         *
         * [trusts] is called once, with the peer's static key only after the handshake has authenticated it: the
         * initiator checks after message 2, before message 3 reveals its own key; the responder after message 3.
         * False throws [NoiseException.UntrustedPeer]; a non-empty payload throws
         * [NoiseException.NonEmptyHandshakePayload]. On any failure, cancellation included, the circuit is closed
         * and the error rethrown.
         */
        suspend fun open(
            circuit: RelayCircuit,
            role: NoiseRole,
            key: NoiseStaticKey,
            trusts: (ByteArray) -> Boolean,
        ): SecureChannel {
            // NoiseHandshake would call its own `trusts` before the peer has proven the key; the decision is made
            // below, once the key is authenticated.
            val handshake = NoiseHandshake(role, key)
            try {
                when (role) {
                    NoiseRole.INITIATOR -> {
                        circuit.send(handshake.writeMessage())
                        requireEmpty(handshake.readMessage(circuit.receive()))
                        requireTrusted(handshake.remoteStatic, trusts)
                        circuit.send(handshake.writeMessage())
                    }
                    NoiseRole.RESPONDER -> {
                        requireEmpty(handshake.readMessage(circuit.receive()))
                        circuit.send(handshake.writeMessage())
                        requireEmpty(handshake.readMessage(circuit.receive()))
                        requireTrusted(handshake.remoteStatic, trusts)
                    }
                }
                val peer = handshake.remoteStatic
                if (!handshake.isComplete || peer == null) throw NoiseException.BadMessage()
                return SecureChannel(circuit, handshake.split(), peer)
            } catch (e: Throwable) {
                circuit.close()
                throw e
            }
        }

        private fun requireTrusted(peer: ByteArray?, trusts: (ByteArray) -> Boolean) {
            if (peer == null || !trusts(peer.copyOf())) throw NoiseException.UntrustedPeer()
        }

        private fun requireEmpty(payload: ByteArray) {
            if (payload.isNotEmpty()) throw NoiseException.NonEmptyHandshakePayload()
        }
    }
}
