package com.shellx.core.testing

import com.shellx.core.account.IdentityProviding

/** An identity provider that answers [googleResult] and records each nonce it was asked for. Thread-safe. */
class FakeIdentityProvider : IdentityProviding {
    private val lock = Any()
    private val nonces = ArrayList<String>()

    @Volatile var googleResult: Result<String> = Result.success("google-id-token")

    val googleNonces: List<String> get() = synchronized(lock) { nonces.toList() }

    override suspend fun googleIdToken(nonce: String): String {
        synchronized(lock) { nonces += nonce }
        return googleResult.getOrThrow()
    }
}
