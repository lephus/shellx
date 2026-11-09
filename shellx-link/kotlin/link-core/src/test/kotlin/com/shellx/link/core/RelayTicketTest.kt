package com.shellx.link.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RelayTicketTest {
    private fun ticket(claimsJson: String) = "v2." + claimsJson.encodeToByteArray().toBase64Url() + ".c2ln"

    @Test
    fun claimsParse() {
        val full = ticket("""{"slot":"slot-a","permission":"register","role":"daemon","expires_at_unix":1090,"issued_at_unix":1000}""")
        assertEquals(RelayTicketClaims("slot-a", "register", "daemon", 1090, 1000), RelayTicket(full, 1090).claims)
        val older = ticket("""{"slot":"s","permission":"register","role":"daemon","expires_at_unix":5}""")
        assertEquals(RelayTicketClaims("s", "register", "daemon", 5, null), RelayTicket(older, 5).claims)
        // The middle segment may also carry base64 padding.
        val padded = "v2." + java.util.Base64.getUrlEncoder().encodeToString(
            """{"slot":"s","permission":"connect","role":"client","expires_at_unix":7}""".encodeToByteArray(),
        ) + ".c2ln"
        assertEquals(RelayTicketClaims("s", "connect", "client", 7), RelayTicket(padded, 7).claims)
    }

    @Test
    fun claimsNullForMalformed() {
        val valid = """{"slot":"s","permission":"register","role":"daemon","expires_at_unix":5}""".encodeToByteArray().toBase64Url()
        val notJson = "not json".encodeToByteArray().toBase64Url()
        val missing = """{"slot":"s"}""".encodeToByteArray().toBase64Url()
        val malformed = listOf(
            "", "garbage", "v2.only", "v2..sig", "v1.$valid.sig", "v2.$notJson.sig", "v2.$missing.sig", "v2.!!!.sig",
            "v2.$valid.sig.extra",
        )
        for (text in malformed) assertNull(RelayTicket(text, 0).claims, text)
    }

    @Test
    fun ticketNeverPrints() {
        val signature = "dGVzdC1zaWduYXR1cmUtbm90LWEtc2VjcmV0"
        val secret = "v2.eyJzbG90Ijoic2hlbGx4LWxpbmstdGVzdCJ9.$signature"
        val ticket = RelayTicket(secret, 1_900_000_000)
        val text = ticket.toString()
        assertFalse(secret in text, "toString printed the ticket")
        assertFalse(signature in text, "toString printed the ticket's signature")
        assertTrue("1900000000" in text, text)
        assertEquals(secret, ticket.ticket)
    }
}
