package com.shellx.link.core

import kotlin.coroutines.cancellation.CancellationException

/**
 * `Noise_XX_25519_ChaChaPoly_SHA256` handshake state (Noise spec rev 34 sections 5.3 and 7.5):
 *
 * ```
 *   -> e
 *   <- e, ee, s, es
 *   -> s, se
 * ```
 *
 * The initiator writes messages 1 and 3 and reads message 2; the responder does the reverse. [trusts] is called with
 * the peer's static public key as soon as it is decrypted (message 2 for the initiator, message 3 for the responder);
 * false throws [NoiseException.UntrustedPeer]. Any error ends the handshake: every later call throws
 * [NoiseException.BadMessage]. Use one handshake from one thread at a time.
 *
 * [ephemeralForTesting] fixes the ephemeral key for known-answer vectors only: a fixed ephemeral repeats nonces under
 * one key and removes forward secrecy.
 */
class NoiseHandshake internal constructor(
    private val role: NoiseRole,
    private val local: NoiseStaticKey,
    private val trusts: (ByteArray) -> Boolean,
    private var ephemeralForTesting: NoiseStaticKey?,
) {
    constructor(role: NoiseRole, local: NoiseStaticKey, trusts: (ByteArray) -> Boolean = { true }) :
        this(role, local, trusts, null)

    private enum class Token { E, S, EE, ES, SE }

    private val symmetric = SymmetricState(PROTOCOL_NAME).also { it.mixHash(PROLOGUE) }
    private var localEphemeral: NoiseStaticKey? = null
    private var remoteEphemeral: ByteArray? = null
    private var remote: ByteArray? = null
    private var messageIndex = 0
    private var failed = false
    private var didSplit = false

    /** True after all three messages have been written or read successfully. */
    val isComplete: Boolean get() = !failed && messageIndex == PATTERN.size

    /** The handshake hash `h`, usable for channel binding once [isComplete]; a copy. */
    val handshakeHash: ByteArray get() = symmetric.handshakeHash.copyOf()

    /**
     * The peer's static public key; a copy. Authenticated only once [isComplete]: before that it is the value
     * decrypted from `s`, which the peer has not yet proven it owns. Null after any failure.
     */
    val remoteStatic: ByteArray? get() = remote?.copyOf()

    /** Writes the next handshake message carrying [payload]. */
    fun writeMessage(payload: ByteArray = ByteArray(0)): ByteArray = guarded {
        checkTurn(writing = true)
        var message = ByteArray(0)
        for (token in PATTERN[messageIndex]) {
            when (token) {
                Token.E -> {
                    val ephemeral = ephemeralForTesting ?: NoiseStaticKey.generate()
                    ephemeralForTesting = null
                    localEphemeral = ephemeral
                    val pub = ephemeral.publicKey
                    message += pub
                    symmetric.mixHash(pub)
                }
                Token.S -> message += symmetric.encryptAndHash(local.publicKey)
                else -> mixDiffieHellman(token)
            }
        }
        message += symmetric.encryptAndHash(payload)
        if (message.size > NOISE_MAX_MESSAGE_BYTES) throw NoiseException.BadMessage()
        messageIndex += 1
        message
    }

    /** Reads the peer's next handshake message and returns its payload. */
    fun readMessage(message: ByteArray): ByteArray = guarded {
        checkTurn(writing = false)
        if (message.size > NOISE_MAX_MESSAGE_BYTES) throw NoiseException.BadMessage()
        var offset = 0
        fun take(count: Int): ByteArray {
            if (message.size - offset < count) throw NoiseException.BadMessage()
            return message.copyOfRange(offset, offset + count).also { offset += count }
        }
        for (token in PATTERN[messageIndex]) {
            when (token) {
                Token.E -> {
                    val ephemeral = take(NOISE_DH_BYTES)
                    remoteEphemeral = ephemeral
                    symmetric.mixHash(ephemeral)
                }
                Token.S -> {
                    val length = NOISE_DH_BYTES + if (symmetric.hasKey) NOISE_TAG_BYTES else 0
                    val key = symmetric.decryptAndHash(take(length))
                    remote = key
                    if (!trusts(key.copyOf())) throw NoiseException.UntrustedPeer()
                }
                else -> mixDiffieHellman(token)
            }
        }
        val payload = symmetric.decryptAndHash(message.copyOfRange(offset, message.size))
        messageIndex += 1
        payload
    }

    /** The transport cipher states. Call once, after message 3; otherwise [NoiseException.BadMessage]. */
    fun split(): NoiseTransport {
        if (!isComplete || didSplit) throw NoiseException.BadMessage()
        didSplit = true
        localEphemeral = null
        val (initiatorToResponder, responderToInitiator) = symmetric.split()
        return when (role) {
            NoiseRole.INITIATOR -> NoiseTransport(initiatorToResponder, responderToInitiator)
            NoiseRole.RESPONDER -> NoiseTransport(responderToInitiator, initiatorToResponder)
        }
    }

    /**
     * Runs one message step; any throwable poisons the handshake. Cancellation and JVM errors (an `Error` from
     * `trusts`, for example) are rethrown as they are; other exceptions that are not Noise errors become BadMessage.
     */
    private inline fun <T> guarded(body: () -> T): T {
        if (failed) throw NoiseException.BadMessage()
        try {
            return body()
        } catch (e: Throwable) {
            failed = true
            localEphemeral = null
            ephemeralForTesting = null
            // `s` may have decrypted before the failure without the peer proving it owns the key.
            remote = null
            if (e is CancellationException) throw e
            if (e !is Exception) throw e
            throw e as? NoiseException ?: NoiseException.BadMessage()
        }
    }

    private fun checkTurn(writing: Boolean) {
        if (messageIndex >= PATTERN.size) throw NoiseException.BadMessage()
        val initiatorWrites = messageIndex % 2 == 0
        val weWrite = (role == NoiseRole.INITIATOR) == initiatorWrites
        if (weWrite != writing) throw NoiseException.BadMessage()
    }

    /** `ee`, `es` and `se`: in `xy` the first letter is the initiator's key, the second the responder's. */
    private fun mixDiffieHellman(token: Token) {
        val (localKey, remoteKey) = when {
            token == Token.EE -> localEphemeral to remoteEphemeral
            token == Token.ES && role == NoiseRole.INITIATOR -> localEphemeral to remote
            token == Token.ES -> local to remoteEphemeral
            token == Token.SE && role == NoiseRole.INITIATOR -> local to remoteEphemeral
            token == Token.SE -> localEphemeral to remote
            else -> throw NoiseException.BadMessage()
        }
        if (localKey == null || remoteKey == null) throw NoiseException.BadMessage()
        symmetric.mixKey(localKey.diffieHellman(remoteKey))
    }

    companion object {
        const val PROTOCOL_NAME = "Noise_XX_25519_ChaChaPoly_SHA256"

        /** ASCII `shellx-link/1`; a fresh copy per read. */
        val PROLOGUE: ByteArray get() = "shellx-link/1".encodeToByteArray()

        private val PATTERN = listOf(
            listOf(Token.E),
            listOf(Token.E, Token.EE, Token.S, Token.ES),
            listOf(Token.S, Token.SE),
        )
    }
}
