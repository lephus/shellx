package com.shellx.link.core

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class BytesTest {
    @Test
    fun hexIsLowercaseAndStrict() {
        assertEquals("00ff10", byteArrayOf(0, -1, 16).toHex())
        assertContentEquals(byteArrayOf(0, -1, 16), hexToBytesOrNull("00ff10"))
        for (bad in listOf("00FF10", "0", "zz")) assertNull(hexToBytesOrNull(bad), bad)
    }

    @Test
    fun base64UrlHasNoPaddingAndOnlyItsAlphabet() {
        val key = byteArrayOf(0xFB.toByte(), 0xFF.toByte(), 0xBF.toByte()) + ByteArray(29)
        assertEquals("-_-_" + "A".repeat(39), key.toBase64Url())
        assertContentEquals(key, base64UrlToBytesOrNull("-_-_" + "A".repeat(39)))
        assertNull(base64UrlToBytesOrNull("+/+/" + "A".repeat(39)))
        assertNull(base64UrlToBytesOrNull("QQ=="))
    }

    @Test
    fun canonicalBase64RejectsEverythingButPaddedStandardText() {
        assertContentEquals("hello world".encodeToByteArray(), canonicalBase64ToBytesOrNull("aGVsbG8gd29ybGQ="))
        assertContentEquals(ByteArray(0), canonicalBase64ToBytesOrNull(""))
        for (bad in listOf("QQ", "QQ=", "Q Q==", "QQ==\n", "-_8=", "QR==", "%%%")) {
            assertNull(canonicalBase64ToBytesOrNull(bad), bad)
        }
    }

    @Test
    fun sha256AndHmacMatchPublishedVectors() {
        assertEquals(
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            sha256("abc".encodeToByteArray()).toHex(),
        )
        // RFC 4231 test case 1
        assertEquals(
            "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
            hmacSha256(ByteArray(20) { 0x0b }, "Hi There".encodeToByteArray()).toHex(),
        )
    }

    @Test
    fun constantTimeEqualsComparesLengthAndContent() {
        assertTrue(constantTimeEquals(byteArrayOf(1, 2), byteArrayOf(1, 2)))
        assertFalse(constantTimeEquals(byteArrayOf(1, 2), byteArrayOf(1, 3)))
        assertFalse(constantTimeEquals(byteArrayOf(1, 2), byteArrayOf(1)))
    }

    @Test
    fun utf8SizeCountsBytes() {
        assertEquals(3, "abc".utf8Size)
        assertEquals(3, "ệ".utf8Size)
        assertEquals(4, "🚀".utf8Size)
    }
}
