package com.shellx.link.core

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds
import kotlinx.serialization.json.jsonPrimitive

class PairingOfferTest {
    private val v = Vectors.pairing
    private fun text(key: String) = v.getValue(key).jsonPrimitive.content
    private fun b64u(key: String) = base64UrlToBytesOrNull(text(key))!!
    private val vectorOffer =
        PairingOffer(text("machine_id"), text("link_slot"), b64u("host_key_b64url"), b64u("code_b64url"), text("machine_name"))
    private val client = b64u("client_key_b64url")
    private val good = vectorOffer.uri

    private fun fails(uri: String, expected: PairingOfferException) =
        assertEquals(expected, assertFailsWith<PairingOfferException>(uri) { PairingOffer.parse(uri) }, uri)

    private fun failsBadUri(uri: String) =
        assertFailsWith<PairingOfferException.BadUri>(uri) { PairingOffer.parse(uri) }

    @Test
    fun uriRoundTrips() {
        assertTrue(good.startsWith("shellx-link://pair?v=1&m=6f1c2b7e-0d4a-4c1e-9a53-3b8e5d2f7a10&s=slot-test-1&k="), good)
        assertFalse("+" in good, good)
        assertTrue(good.endsWith("&n=Phu%27s%20Mac"), good)
        assertEquals(vectorOffer, PairingOffer.parse(good))
        val made = PairingOffer.make(vectorOffer.machineId, vectorOffer.linkSlot, vectorOffer.hostKey, "Mac é ü & =")
        assertEquals(16, made.code.size)
        assertEquals(made, PairingOffer.parse(made.uri))
        assertEquals("Mac é ü & =", PairingOffer.parse(made.uri).machineName)
        val other = PairingOffer.make(vectorOffer.machineId, vectorOffer.linkSlot, vectorOffer.hostKey, "x")
        assertFalse(made.code.contentEquals(other.code))
        assertEquals(300.seconds, PairingOffer.LIFETIME)
    }

    @Test
    fun vietnameseMachineNameRoundTrips() {
        val made = PairingOffer.make(vectorOffer.machineId, vectorOffer.linkSlot, vectorOffer.hostKey, "MacBook của Phú")
        assertEquals("MacBook của Phú", PairingOffer.parse(made.uri).machineName)
    }

    @Test
    fun proofMatchesTheVector() {
        assertEquals(text("proof_hex"), vectorOffer.proof(client).toHex())
        assertEquals(text("proof_b64url"), vectorOffer.proof(client).toBase64Url())
    }

    @Test
    fun proofIsBoundToHostKeySlotAndMachine() {
        val genuine = vectorOffer.proof(client)
        val host = vectorOffer.hostKey.copyOf().also { it[0] = (it[0].toInt() xor 1).toByte() }
        assertFalse(genuine.contentEquals(vectorOffer.copy(hostKey = host).proof(client)))
        assertFalse(genuine.contentEquals(vectorOffer.copy(linkSlot = "attacker-slot").proof(client)))
        assertFalse(genuine.contentEquals(vectorOffer.copy(machineId = "00000000-0000-4000-8000-000000000000").proof(client)))
        val otherClient = client.copyOf().also { it[0] = (it[0].toInt() xor 1).toByte() }
        assertFalse(genuine.contentEquals(vectorOffer.proof(otherClient)))
    }

    @Test
    fun parseRejectsStrictFieldClasses() {
        val m = "m=${text("machine_id")}"
        val s = "s=slot-test-1"
        val n = "n=Phu%27s%20Mac"
        val k = "k=QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8"
        // m: only [A-Za-z0-9-], 1 to 64.
        for (bad in listOf("m=a_b", "m=a%2Fb", "m=" + "a".repeat(65), "m=")) {
            fails(good.replace(m, bad), PairingOfferException.BadField("m"))
        }
        // s: the base64url alphabet only, 1 to 64.
        for (bad in listOf("s=a.b", "s=a%20b", "s=" + "a".repeat(65))) {
            fails(good.replace(s, bad), PairingOfferException.BadField("s"))
        }
        // k and c: the base64url alphabet only (no +, / or =); + is never a space.
        fails(good.replace(k, "k=QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdX+8"), PairingOfferException.BadField("k"))
        fails(good.replace(k, "k=QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdX%2F8"), PairingOfferException.BadField("k"))
        fails(good.replace(k, "$k%3D"), PairingOfferException.BadField("k"))
        fails(good.replace("c=AAECAwQFBgcICQoLDA0ODw", "c=AAECAwQFBgcICQoLDA0OD%2B"), PairingOfferException.BadField("c"))
        // n: 1 to 100 code points, no controls, no bidi overrides or isolates.
        val badNames = listOf("n=", "n=" + "a".repeat(101), "n=a%0Ab", "n=a%00b", "n=a%7Fb") +
            listOf("%E2%80%AA", "%E2%80%AE", "%E2%81%A6", "%E2%81%A9").map { "n=a${it}b" }
        for (bad in badNames) fails(good.replace(n, bad), PairingOfferException.BadField("n"))
        assertEquals("a".repeat(100), PairingOffer.parse(good.replace(n, "n=" + "a".repeat(100))).machineName)
        assertEquals("‏ ok", PairingOffer.parse(good.replace(n, "n=%E2%80%8F%20ok")).machineName)
        // Structure: no path, port, userinfo or fragment, and no repeated key.
        failsBadUri(good.replace("pair?", "pair/x?"))
        failsBadUri(good.replace("pair?", "pair/?"))
        failsBadUri(good.replace("//pair?", "//pair:80?"))
        failsBadUri(good.replace("//pair?", "//user@pair?"))
        failsBadUri("$good#frag")
        fails("$good&n=Other", PairingOfferException.BadField("n"))
        fails("$good&k=${k.drop(2)}", PairingOfferException.BadField("k"))
    }

    @Test
    fun parseRejectsBadFields() {
        failsBadUri("https://example.com/pair?v=1")
        failsBadUri("not a uri")
        assertFailsWith<PairingOfferException.UnsupportedVersion> { PairingOffer.parse(good.replace("v=1", "v=2")) }
        fails(good.replace("?v=1&", "?"), PairingOfferException.BadField("v"))
        val short = vectorOffer.hostKey.copyOf(31).toBase64Url()
        fails(good.replace("k=QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8", "k=$short"), PairingOfferException.BadField("k"))
        val noCode = good.split("&").filter { !it.startsWith("c=") }.joinToString("&")
        fails(noCode, PairingOfferException.BadField("c"))
        fails(good.replace("&s=slot-test-1", ""), PairingOfferException.BadField("s"))
        fails(good.replace("n=Phu%27s%20Mac", "n=a%FFb"), PairingOfferException.BadField("n"))
    }

    @Test
    fun toStringHidesTheCode() {
        val textForm = vectorOffer.toString()
        assertFalse("AAECAwQFBgcICQoLDA0ODw" in textForm, textForm)
        assertFalse(vectorOffer.code.toHex() in textForm, textForm)
        assertTrue("<redacted>" in textForm, textForm)
    }

    @Test
    fun equalityComparesKeyContent() {
        val copy = vectorOffer.copy(hostKey = vectorOffer.hostKey.copyOf(), code = vectorOffer.code.copyOf())
        assertEquals(vectorOffer, copy)
        assertEquals(vectorOffer.hashCode(), copy.hashCode())
        assertNotEquals(vectorOffer, copy.copy(code = ByteArray(16)))
        assertContentEquals(vectorOffer.hostKey, copy.hostKey)
    }
}
