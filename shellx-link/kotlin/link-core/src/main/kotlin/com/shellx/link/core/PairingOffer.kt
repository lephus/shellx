package com.shellx.link.core

import java.io.ByteArrayOutputStream
import java.net.URI
import java.net.URISyntaxException
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.security.SecureRandom
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/** Why a pairing URI was refused. */
sealed class PairingOfferException(message: String) : Exception(message) {
    /** Not a `shellx-link://pair` URI. */
    class BadUri : PairingOfferException("bad_uri")

    /** The `v` field is not `1`. */
    class UnsupportedVersion : PairingOfferException("unsupported_version")

    /** The named query field is missing, empty, repeated or malformed. */
    data class BadField(val field: String) : PairingOfferException("bad_field")
}

/**
 * What a Mac shows as a QR code so a phone can pair with it (PROTOCOL.md section 9). The offer carries the host key
 * the phone will trust: it travels only through the QR code, never through the relay. [code] is a one-time secret
 * that keys the pairing proof; it is never printed.
 */
data class PairingOffer(
    val machineId: String,
    val linkSlot: String,
    /** The host's 32-byte Noise static public key. */
    val hostKey: ByteArray,
    /** The 16-byte one-time pairing code. */
    val code: ByteArray,
    val machineName: String,
) {
    /** `shellx-link://pair?v=1&m=…&s=…&k=…&c=…&n=…`: keys and code in base64url without padding, the rest percent-encoded. */
    val uri: String
        get() = "shellx-link://pair?v=1&m=${percentEncode(machineId)}&s=${percentEncode(linkSlot)}" +
            "&k=${hostKey.toBase64Url()}&c=${code.toBase64Url()}&n=${percentEncode(machineName)}"

    /** HMAC-SHA256(code, "shellx-link-pair/1" 0x00 machineId 0x00 linkSlot 0x00 hostKey clientKey). */
    fun proof(clientKey: ByteArray): ByteArray {
        val message = ByteArrayOutputStream()
        message.write(PROOF_LABEL.encodeToByteArray())
        message.write(0)
        message.write(machineId.encodeToByteArray())
        message.write(0)
        message.write(linkSlot.encodeToByteArray())
        message.write(0)
        message.write(hostKey)
        message.write(clientKey)
        return hmacSha256(code, message.toByteArray())
    }

    override fun equals(other: Any?): Boolean = other is PairingOffer && machineId == other.machineId &&
        linkSlot == other.linkSlot && hostKey.contentEquals(other.hostKey) && code.contentEquals(other.code) &&
        machineName == other.machineName

    override fun hashCode(): Int {
        var result = machineId.hashCode()
        result = 31 * result + linkSlot.hashCode()
        result = 31 * result + hostKey.contentHashCode()
        result = 31 * result + code.contentHashCode()
        return 31 * result + machineName.hashCode()
    }

    override fun toString(): String = "PairingOffer(machine=$machineId, slot=$linkSlot, <redacted>)"

    companion object {
        /** How long an offer stays valid. */
        val LIFETIME: Duration = 300.seconds

        private const val PROOF_LABEL = "shellx-link-pair/1"
        private const val HOST_KEY_BYTES = 32
        private const val CODE_BYTES = 16
        private const val MAX_ID_CHARS = 64
        private const val MAX_NAME_CODE_POINTS = 100
        private val MACHINE_ID = Regex("[A-Za-z0-9-]{1,$MAX_ID_CHARS}")
        private val LINK_SLOT = Regex("[A-Za-z0-9_-]{1,$MAX_ID_CHARS}")
        private const val UNRESERVED = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        private const val UPPER_HEX = "0123456789ABCDEF"

        /** Parses an offer URI. Throws [PairingOfferException]. */
        fun parse(uri: String): PairingOffer {
            val parsed = try {
                URI(uri)
            } catch (_: URISyntaxException) {
                throw PairingOfferException.BadUri()
            }
            // rawAuthority "pair" also rules out userinfo and a port.
            if (parsed.scheme != "shellx-link" || parsed.rawAuthority != "pair" || !parsed.rawPath.isNullOrEmpty() ||
                parsed.rawFragment != null
            ) {
                throw PairingOfferException.BadUri()
            }
            val fields = queryFields(parsed.rawQuery)
            val version = fields["v"] ?: throw PairingOfferException.BadField("v")
            if (version != "1") throw PairingOfferException.UnsupportedVersion()

            fun text(name: String): String {
                val value = fields[name]
                if (value.isNullOrEmpty()) throw PairingOfferException.BadField(name)
                return value
            }

            fun matching(name: String, pattern: Regex): String =
                text(name).also { if (!pattern.matches(it)) throw PairingOfferException.BadField(name) }

            fun bytes(name: String, count: Int): ByteArray {
                val decoded = base64UrlToBytesOrNull(text(name))
                if (decoded == null || decoded.size != count) throw PairingOfferException.BadField(name)
                return decoded
            }

            val machineId = matching("m", MACHINE_ID)
            val linkSlot = matching("s", LINK_SLOT)
            val hostKey = bytes("k", HOST_KEY_BYTES)
            val code = bytes("c", CODE_BYTES)
            val name = text("n")
            if (name.codePointCount(0, name.length) > MAX_NAME_CODE_POINTS || name.codePoints().anyMatch(::isForbiddenInName)) {
                throw PairingOfferException.BadField("n")
            }
            return PairingOffer(machineId, linkSlot, hostKey, code, name)
        }

        /** A new offer with a random 16-byte code (test and demo Macs). */
        fun make(
            machineId: String,
            linkSlot: String,
            hostKey: ByteArray,
            machineName: String,
            random: SecureRandom = SecureRandom(),
        ): PairingOffer {
            val code = ByteArray(CODE_BYTES).also(random::nextBytes)
            return PairingOffer(machineId, linkSlot, hostKey.copyOf(), code, machineName)
        }

        /** Query items, each split at its first `=` and percent-decoded as strict UTF-8; `+` stays `+`. */
        private fun queryFields(rawQuery: String?): Map<String, String> {
            val fields = LinkedHashMap<String, String>()
            if (rawQuery == null) return fields
            for (item in rawQuery.split('&')) {
                val at = item.indexOf('=')
                val rawName = if (at < 0) item else item.substring(0, at)
                val rawValue = if (at < 0) "" else item.substring(at + 1)
                val name = percentDecodeOrNull(rawName) ?: throw PairingOfferException.BadField(rawName)
                val value = percentDecodeOrNull(rawValue) ?: throw PairingOfferException.BadField(name)
                if (name in fields) throw PairingOfferException.BadField(name)
                fields[name] = value
            }
            return fields
        }

        private fun percentDecodeOrNull(text: String): String? {
            val bytes = ByteArrayOutputStream(text.length)
            var i = 0
            while (i < text.length) {
                val c = text[i]
                if (c == '%') {
                    if (i + 2 >= text.length) return null
                    val high = Character.digit(text[i + 1], 16)
                    val low = Character.digit(text[i + 2], 16)
                    if (high < 0 || low < 0) return null
                    bytes.write((high shl 4) or low)
                    i += 3
                } else {
                    val end = if (Character.isHighSurrogate(c) && i + 1 < text.length) i + 2 else i + 1
                    bytes.write(text.substring(i, end).encodeToByteArray())
                    i = end
                }
            }
            return try {
                Charsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes.toByteArray()))
                    .toString()
            } catch (_: CharacterCodingException) {
                null
            }
        }

        private fun percentEncode(text: String): String {
            val out = StringBuilder()
            for (byte in text.encodeToByteArray()) {
                val b = byte.toInt() and 0xFF
                val c = b.toChar()
                if (b < 0x80 && c in UNRESERVED) {
                    out.append(c)
                } else {
                    out.append('%').append(UPPER_HEX[b ushr 4]).append(UPPER_HEX[b and 0x0F])
                }
            }
            return out.toString()
        }

        /** Control characters and the bidi overrides and isolates, which could disguise a name in the approval prompt. */
        private fun isForbiddenInName(codePoint: Int): Boolean =
            Character.getType(codePoint) == Character.CONTROL.toInt() ||
                codePoint in 0x202A..0x202E || codePoint in 0x2066..0x2069
    }
}
