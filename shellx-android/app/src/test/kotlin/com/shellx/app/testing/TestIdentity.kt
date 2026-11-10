package com.shellx.app.testing

import com.shellx.core.account.IdentityProviding

/** Google's sheet in tests: answers [result] and records every nonce it was asked with. Thread-safe. */
class TestIdentity(@Volatile var result: Result<String> = Result.success("google-id-token")) : IdentityProviding {
    private val asked = mutableListOf<String>()

    val nonces: List<String> get() = synchronized(asked) { asked.toList() }

    override suspend fun googleIdToken(nonce: String): String {
        synchronized(asked) { asked += nonce }
        return result.getOrThrow()
    }
}
