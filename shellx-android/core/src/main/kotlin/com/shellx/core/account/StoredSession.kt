package com.shellx.core.account

/** The signed-in account as kept in the secret store, with how it signed in. The token is a bearer secret and never
 *  prints; nor does the email. */
data class StoredSession(
    val userId: String,
    val deviceId: String,
    val token: String,
    val email: String,
    val authMethod: AccountAuthMethod = AccountAuthMethod.GOOGLE,
) {
    override fun toString(): String = "StoredSession(user=$userId, device=$deviceId, method=${authMethod.wire}, <redacted>)"
}
