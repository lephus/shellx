package com.shellx.link.core

import java.util.Base64
import kotlinx.serialization.json.JsonObject

/**
 * A relay ticket minted for one slot by the ShellX API: a connect ticket for a phone. The relay checks the signature,
 * scope and expiry. The ticket is a bearer secret and never prints.
 */
data class RelayTicket(val ticket: String, val expiresAtUnix: Long) {
    /**
     * The claims of the ticket's middle segment, `v2.<base64url JSON>.<signature>`. The signature is not checked (the
     * relay does that). Null for any other shape.
     */
    val claims: RelayTicketClaims?
        get() {
            val parts = ticket.split('.')
            if (parts.size != 3 || parts[0] != "v2" || parts[1].isEmpty()) return null
            val bytes = try {
                Base64.getUrlDecoder().decode(parts[1])
            } catch (_: IllegalArgumentException) {
                return null
            }
            val o = parseJsonOrNull(bytes) as? JsonObject ?: return null
            return try {
                RelayTicketClaims(
                    slot = o.str("slot"),
                    permission = o.str("permission"),
                    role = o.str("role"),
                    expiresAtUnix = o.long("expires_at_unix"),
                    issuedAtUnix = o.optLong("issued_at_unix"),
                )
            } catch (_: FieldError) {
                null
            }
        }

    override fun toString(): String = "RelayTicket(expires=$expiresAtUnix, <redacted>)"
}

/**
 * The claims of a relay ticket that matter to the client (`relay/src/v2/tickets.ts`). [issuedAtUnix] is the server's
 * clock when it minted the ticket; null for a ticket that does not carry it.
 */
data class RelayTicketClaims(
    val slot: String,
    val permission: String,
    val role: String,
    val expiresAtUnix: Long,
    val issuedAtUnix: Long? = null,
)
