package com.shellx.core.account

/** The signed-in account as kept in the secret store. The token is a bearer secret and never prints; nor does the
 *  email. */
data class StoredSession(val userId: String, val deviceId: String, val token: String, val email: String) {
    override fun toString(): String = "StoredSession(user=$userId, device=$deviceId, <redacted>)"
}
