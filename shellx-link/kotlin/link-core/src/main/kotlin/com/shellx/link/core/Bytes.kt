package com.shellx.link.core

import java.security.MessageDigest
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

// Byte helpers. Android API 26 has java.util.Base64, MessageDigest("SHA-256") and Mac("HmacSHA256").

private const val HEX_DIGITS = "0123456789abcdef"

/** Lower-case hex. */
internal fun ByteArray.toHex(): String {
    val out = CharArray(size * 2)
    for (i in indices) {
        val b = this[i].toInt() and 0xFF
        out[2 * i] = HEX_DIGITS[b ushr 4]
        out[2 * i + 1] = HEX_DIGITS[b and 0x0F]
    }
    return String(out)
}

/** Even-length lower-case hex (`[0-9a-f]` only) to bytes; anything else is null. */
internal fun hexToBytesOrNull(text: String): ByteArray? {
    if (text.length % 2 != 0) return null
    val out = ByteArray(text.length / 2)
    for (i in out.indices) {
        val high = hexNibble(text[2 * i])
        val low = hexNibble(text[2 * i + 1])
        if (high < 0 || low < 0) return null
        out[i] = ((high shl 4) or low).toByte()
    }
    return out
}

private fun hexNibble(c: Char): Int = when (c) {
    in '0'..'9' -> c - '0'
    in 'a'..'f' -> c - 'a' + 10
    else -> -1
}

/** Base64url (RFC 4648 section 5) without padding. */
internal fun ByteArray.toBase64Url(): String = Base64.getUrlEncoder().withoutPadding().encodeToString(this)

/** Base64url without padding to bytes: only `[A-Za-z0-9_-]`, no `=`; anything else is null. */
internal fun base64UrlToBytesOrNull(text: String): ByteArray? {
    for (c in text) {
        val ok = c in 'A'..'Z' || c in 'a'..'z' || c in '0'..'9' || c == '-' || c == '_'
        if (!ok) return null
    }
    return try {
        Base64.getUrlDecoder().decode(text)
    } catch (_: IllegalArgumentException) {
        null
    }
}

/** Standard base64 (RFC 4648 section 4) with padding. */
internal fun ByteArray.toBase64(): String = Base64.getEncoder().encodeToString(this)

/**
 * Standard padded base64 to bytes, accepting only the text that encoding the bytes gives back: no missing
 * padding, whitespace, line breaks, url-safe characters or non-zero trailing bits. Anything else is null.
 */
internal fun canonicalBase64ToBytesOrNull(text: String): ByteArray? {
    val bytes = try {
        Base64.getDecoder().decode(text)
    } catch (_: IllegalArgumentException) {
        return null
    }
    return if (bytes.toBase64() == text) bytes else null
}

/** SHA-256 through JCA. */
internal fun sha256(data: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(data)

/** HMAC-SHA256 through JCA; [key] is never empty. */
internal fun hmacSha256(key: ByteArray, data: ByteArray): ByteArray {
    val mac = Mac.getInstance("HmacSHA256")
    mac.init(SecretKeySpec(key, "HmacSHA256"))
    return mac.doFinal(data)
}

/** Compares length and content without stopping at the first difference. */
internal fun constantTimeEquals(a: ByteArray, b: ByteArray): Boolean {
    if (a.size != b.size) return false
    var diff = 0
    for (i in a.indices) diff = diff or (a[i].toInt() xor b[i].toInt())
    return diff == 0
}

/** The number of bytes this string takes in UTF-8, as [String.encodeToByteArray] writes it. */
internal val String.utf8Size: Int
    get() = encodeToByteArray().size
