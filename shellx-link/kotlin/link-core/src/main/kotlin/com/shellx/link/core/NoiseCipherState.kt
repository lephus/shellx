package com.shellx.link.core

import java.security.MessageDigest
import org.bouncycastle.crypto.InvalidCipherTextException
import org.bouncycastle.crypto.modes.ChaCha20Poly1305
import org.bouncycastle.crypto.params.AEADParameters
import org.bouncycastle.crypto.params.KeyParameter

private val EMPTY = ByteArray(0)

/**
 * Noise `CipherState` (spec rev 34 section 5.1) for ChaChaPoly, through BouncyCastle's lightweight API: Android API 26
 * has no JCA ChaCha20-Poly1305. [nonce] lets a test start near 2^64.
 */
internal class CipherState(key: ByteArray?, nonce: ULong = 0u) {
    private val key: ByteArray? = key?.copyOf()
    private var n: ULong = nonce

    val hasKey: Boolean get() = key != null

    /** `EncryptWithAd`. Without a key the plaintext passes through unchanged. */
    fun encrypt(ad: ByteArray, plaintext: ByteArray): ByteArray {
        val k = key ?: return plaintext
        val cipher = ChaCha20Poly1305()
        cipher.init(true, AEADParameters(KeyParameter(k), NOISE_TAG_BYTES * 8, currentNonce(), ad))
        val out = ByteArray(cipher.getOutputSize(plaintext.size))
        var length = cipher.processBytes(plaintext, 0, plaintext.size, out, 0)
        length += cipher.doFinal(out, length)
        n += 1u
        return if (length == out.size) out else out.copyOf(length)
    }

    /** `DecryptWithAd`. A failed decryption leaves the nonce unchanged, as the spec requires. */
    fun decrypt(ad: ByteArray, ciphertext: ByteArray): ByteArray {
        val k = key ?: return ciphertext
        val nonce = currentNonce()
        if (ciphertext.size < NOISE_TAG_BYTES) throw NoiseException.DecryptFailed()
        val cipher = ChaCha20Poly1305()
        cipher.init(false, AEADParameters(KeyParameter(k), NOISE_TAG_BYTES * 8, nonce, ad))
        val out = ByteArray(cipher.getOutputSize(ciphertext.size))
        val length = try {
            val written = cipher.processBytes(ciphertext, 0, ciphertext.size, out, 0)
            written + cipher.doFinal(out, written)
        } catch (_: InvalidCipherTextException) {
            throw NoiseException.DecryptFailed()
        }
        n += 1u
        return if (length == out.size) out else out.copyOf(length)
    }

    /** 32 bits of zeros, then the 64-bit counter little-endian (spec section 12.3). 2^64-1 is reserved. */
    private fun currentNonce(): ByteArray {
        if (n == ULong.MAX_VALUE) throw NoiseException.NonceExhausted()
        val bytes = ByteArray(12)
        var value = n
        for (i in 4 until 12) {
            bytes[i] = (value and 0xFFu).toByte()
            value = value shr 8
        }
        return bytes
    }
}

/** Noise `SymmetricState` (spec section 5.2) with SHA-256. */
internal class SymmetricState(protocolName: String) {
    var chainingKey: ByteArray
        private set
    var handshakeHash: ByteArray
        private set
    private var cipher = CipherState(null)

    init {
        val name = protocolName.encodeToByteArray()
        handshakeHash = if (name.size <= 32) name.copyOf(32) else sha256(name)
        chainingKey = handshakeHash
    }

    val hasKey: Boolean get() = cipher.hasKey

    fun mixKey(inputKeyMaterial: ByteArray) {
        val (newChainingKey, tempKey) = noiseHkdf(chainingKey, inputKeyMaterial)
        chainingKey = newChainingKey
        cipher = CipherState(tempKey)
    }

    fun mixHash(data: ByteArray) {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(handshakeHash)
        digest.update(data)
        handshakeHash = digest.digest()
    }

    fun encryptAndHash(plaintext: ByteArray): ByteArray {
        val ciphertext = cipher.encrypt(handshakeHash, plaintext)
        mixHash(ciphertext)
        return ciphertext
    }

    fun decryptAndHash(ciphertext: ByteArray): ByteArray {
        val plaintext = cipher.decrypt(handshakeHash, ciphertext)
        mixHash(ciphertext)
        return plaintext
    }

    /** `Split()`: the initiator-to-responder and responder-to-initiator cipher states. */
    fun split(): Pair<CipherState, CipherState> {
        val (k1, k2) = noiseHkdf(chainingKey, EMPTY)
        return CipherState(k1) to CipherState(k2)
    }
}

/** Noise `HKDF(chaining_key, input_key_material, 2)` (spec section 4.3), built from HMAC-SHA256. */
internal fun noiseHkdf(chainingKey: ByteArray, inputKeyMaterial: ByteArray): Pair<ByteArray, ByteArray> {
    val tempKey = hmacSha256(chainingKey, inputKeyMaterial)
    val output1 = hmacSha256(tempKey, byteArrayOf(0x01))
    val output2 = hmacSha256(tempKey, output1 + byteArrayOf(0x02))
    return output1 to output2
}

/**
 * The two cipher states of a completed handshake. Frames must be decrypted in the order they were encrypted; the
 * receive counter only advances on a successful decryption.
 */
class NoiseTransport internal constructor(private val send: CipherState, private val receive: CipherState) {
    /** Encrypts one frame: `plaintext.size + 16` bytes, at most [MAX_MESSAGE_BYTES]. */
    @Synchronized
    fun encrypt(plaintext: ByteArray): ByteArray {
        if (plaintext.size + TAG_BYTES > MAX_MESSAGE_BYTES) throw NoiseException.BadMessage()
        return send.encrypt(EMPTY, plaintext)
    }

    /** Decrypts the peer's next frame. [NoiseException.DecryptFailed] keeps the nonce. */
    @Synchronized
    fun decrypt(ciphertext: ByteArray): ByteArray {
        if (ciphertext.size > MAX_MESSAGE_BYTES) throw NoiseException.BadMessage()
        return receive.decrypt(EMPTY, ciphertext)
    }

    companion object {
        const val MAX_MESSAGE_BYTES = NOISE_MAX_MESSAGE_BYTES
        const val TAG_BYTES = NOISE_TAG_BYTES
    }
}
