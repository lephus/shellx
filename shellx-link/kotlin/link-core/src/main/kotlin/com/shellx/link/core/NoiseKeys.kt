package com.shellx.link.core

import java.security.SecureRandom
import org.bouncycastle.crypto.agreement.X25519Agreement
import org.bouncycastle.crypto.params.X25519PrivateKeyParameters
import org.bouncycastle.crypto.params.X25519PublicKeyParameters

/** Which side of the handshake this party plays. The initiator sends message 1. */
enum class NoiseRole { INITIATOR, RESPONDER }

/** Failures from the Noise handshake, the transport and the secure channel. */
sealed class NoiseException(message: String) : Exception(message) {
    /** The peer's static key was decrypted and `trusts` returned false. */
    class UntrustedPeer : NoiseException("untrusted_peer")

    /** An AEAD tag did not verify: the message was tampered with, replayed, reordered or sent under another key. */
    class DecryptFailed : NoiseException("decrypt_failed")

    /** A malformed or oversized message, a call out of handshake order, or use after a failure. */
    class BadMessage : NoiseException("bad_message")

    /** The 64-bit nonce counter is used up; the session must be established again. */
    class NonceExhausted : NoiseException("nonce_exhausted")

    /** A Link handshake message carried a payload (PROTOCOL.md section 2); thrown by `SecureChannel`. */
    class NonEmptyHandshakePayload : NoiseException("non_empty_handshake_payload")
}

/** Noise's maximum message length (spec section 3). */
internal const val NOISE_MAX_MESSAGE_BYTES = 65_535

/** DHLEN for 25519. */
internal const val NOISE_DH_BYTES = 32

/** The ChaChaPoly authentication tag length. */
internal const val NOISE_TAG_BYTES = 16

/**
 * An X25519 key pair used as a Noise static key (or, in tests, an ephemeral one). It holds the 32 raw private bytes
 * and never prints them.
 */
class NoiseStaticKey private constructor(private val privateBytes: ByteArray, private val publicBytes: ByteArray) {
    /** The 32-byte X25519 private key; a copy. */
    val rawPrivate: ByteArray get() = privateBytes.copyOf()

    /** The 32-byte X25519 public key; a copy. */
    val publicKey: ByteArray get() = publicBytes.copyOf()

    /** Noise `DH(key_pair, public_key)`: the 32-byte shared secret. [NoiseException.BadMessage] on a wrong length or an all-zero result. */
    internal fun diffieHellman(remotePublic: ByteArray): ByteArray {
        if (remotePublic.size != NOISE_DH_BYTES) throw NoiseException.BadMessage()
        val secret = ByteArray(NOISE_DH_BYTES)
        try {
            val agreement = X25519Agreement()
            agreement.init(X25519PrivateKeyParameters(privateBytes, 0))
            agreement.calculateAgreement(X25519PublicKeyParameters(remotePublic, 0), secret, 0)
        } catch (_: IllegalStateException) {
            // BouncyCastle refuses an all-zero shared secret (a low-order public key).
            throw NoiseException.BadMessage()
        }
        return secret
    }

    override fun toString(): String = "NoiseStaticKey(<redacted>)"

    companion object {
        /** A fresh random key pair. */
        fun generate(random: SecureRandom = SecureRandom()): NoiseStaticKey {
            val key = X25519PrivateKeyParameters(random)
            return NoiseStaticKey(key.encoded, key.generatePublicKey().encoded)
        }

        /** The key pair of 32 raw private bytes. [IllegalArgumentException] unless 32 bytes. */
        fun fromPrivate(rawPrivate: ByteArray): NoiseStaticKey {
            require(rawPrivate.size == X25519PrivateKeyParameters.KEY_SIZE) { "an X25519 private key is 32 bytes" }
            val key = X25519PrivateKeyParameters(rawPrivate, 0)
            return NoiseStaticKey(rawPrivate.copyOf(), key.generatePublicKey().encoded)
        }
    }
}
