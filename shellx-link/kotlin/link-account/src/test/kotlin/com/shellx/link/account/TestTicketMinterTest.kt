package com.shellx.link.account

import com.shellx.link.core.RelayTicketClaims
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import org.junit.jupiter.api.Test

/** The minter the gated integration test signs with: checked here without a relay, so its format is not untested. */
class TestTicketMinterTest {
    @Test
    fun mintedTicketsCarryTheirClaimsAndASignatureOverTheCanonicalPayload() {
        val ticket = TestTicketMinter("0123456789abcdef0123456789abcdef").mint("register", "s1", nowUnix = 1_000, lifetime = 120)
        assertEquals(1_120, ticket.expiresAtUnix)
        assertEquals(RelayTicketClaims("s1", "register", "daemon", 1_120, 1_000), ticket.claims)
        assertEquals("client", TestTicketMinter("k").mint("connect", "s1").claims?.role)

        val (version, claims, signature) = ticket.ticket.split('.')
        assertEquals("v2", version)
        assertEquals(
            """{"circuit":null,"expires_at_unix":1120,"generation":null,"issued_at_unix":1000,"issuer":"shellx-relay",""" +
                """"lane":null,"permission":"register","role":"daemon","slot":"s1","version":2}""",
            Base64.getUrlDecoder().decode(claims).decodeToString(),
        )
        val payload = "cmux-relay-ticket-v2\n2\nshellx-relay\nregister\ndaemon\ns1\n\n\n\n1000\n1120"
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec("0123456789abcdef0123456789abcdef".encodeToByteArray(), "HmacSHA256"))
        assertContentEquals(mac.doFinal(payload.encodeToByteArray()), Base64.getUrlDecoder().decode(signature))
    }
}
