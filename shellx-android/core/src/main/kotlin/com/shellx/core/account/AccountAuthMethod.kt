package com.shellx.core.account

/**
 * How the stored session signed in; mirrors the relay's `tokens.auth_method`. Android never holds a `password` or an
 * `apple` session.
 */
enum class AccountAuthMethod(val wire: String) {
    GOOGLE("google"),

    /** A 6-digit code mailed to the account's address. */
    EMAIL("email");

    companion object {
        /** The method the relay and the vault call [wire]; null for any other. */
        fun ofWire(wire: String): AccountAuthMethod? = entries.firstOrNull { it.wire == wire }
    }
}
