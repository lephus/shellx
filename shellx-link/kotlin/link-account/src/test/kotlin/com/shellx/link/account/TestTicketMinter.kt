package com.shellx.link.account

import com.shellx.link.core.RelayTicket
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Test-only stand-in for the ShellX API that mints relay tickets for a slot (`TestTicketMinter.swift`).
 *
 * Format: `v2.<base64url(claims JSON)>.<base64url(HMAC-SHA256(secret, payload))>`, where the payload is the
 * newline-joined canonical claim list the relay recomputes on verify.
 */
class TestTicketMinter(secret: String) {
    private val key = secret.encodeToByteArray()

    companion object {
        const val ISSUER = "shellx-relay"
        const val LIFETIME_SECONDS = 120L
    }

    /** [permission] is `register` (role `daemon`) or `connect` (role `client`). */
    fun mint(
        permission: String,
        slot: String,
        nowUnix: Long = System.currentTimeMillis() / 1000,
        lifetime: Long = LIFETIME_SECONDS,
    ): RelayTicket {
        val role = if (permission == "register") "daemon" else "client"
        val expires = nowUnix + lifetime
        // Sorted keys, as the Swift minter writes them. Circuit, lane and generation stay null, as the ShellX API mints them.
        val claims = buildJsonObject {
            put("circuit", JsonNull)
            put("expires_at_unix", expires)
            put("generation", JsonNull)
            put("issued_at_unix", nowUnix)
            put("issuer", ISSUER)
            put("lane", JsonNull)
            put("permission", permission)
            put("role", role)
            put("slot", slot)
            put("version", 2)
        }
        val payload = listOf(
            "cmux-relay-ticket-v2", "2", ISSUER, permission, role, slot, "", "", "", nowUnix.toString(), expires.toString(),
        ).joinToString("\n")
        val mac = Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(key, "HmacSHA256")) }.doFinal(payload.encodeToByteArray())
        val encoder = Base64.getUrlEncoder().withoutPadding()
        return RelayTicket("v2.${encoder.encodeToString(claims.toString().encodeToByteArray())}.${encoder.encodeToString(mac)}", expires)
    }
}
