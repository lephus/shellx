package com.shellx.core.account

/**
 * The phone's identity provider (IdentityProviding.swift, Google only). 3D implements it with Credential Manager:
 * GetSignInWithGoogleOption, serverClientId = the "Web" client, setNonce(nonce) (S1 §6.7). Tests use a fake.
 */
interface IdentityProviding {
    /** Google's ID token for a sign-in carrying the relay's raw [nonce]. Throws [IdentityProviderException]. */
    suspend fun googleIdToken(nonce: String): String
}

sealed class IdentityProviderException(message: String) : Exception(message) {
    /** The user closed Google's sheet. */
    class Cancelled : IdentityProviderException("cancelled")

    /** This build has no usable Google client ID. */
    class NotConfigured : IdentityProviderException("not_configured")

    /** Google did not finish the sign-in. */
    class Failed : IdentityProviderException("failed")
}

/** Every call throws [IdentityProviderException.NotConfigured] (the demo, tests that sign in no other way). */
class UnavailableIdentityProvider : IdentityProviding {
    override suspend fun googleIdToken(nonce: String): String = throw IdentityProviderException.NotConfigured()
}
