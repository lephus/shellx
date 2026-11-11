package com.shellx.core.account

/** Which account screen the app shows (AppPhase.swift; Android has no Apple link phase). */
sealed interface AppPhase {
    /** The session has not been read yet (or the secret store is locked for now). */
    data object Launching : AppPhase

    /** [expired] is true when the relay refused the stored token. */
    data class SignedOut(val expired: Boolean) : AppPhase

    /** [authMethod]: how the session signed in (Settings names it, and Delete Account follows it). The email never prints. */
    data class SignedIn(val email: String, val authMethod: AccountAuthMethod = AccountAuthMethod.GOOGLE) : AppPhase {
        override fun toString(): String = "SignedIn(email=<redacted>, method=${authMethod.wire})"
    }
}
