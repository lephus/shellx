package com.shellx.core.account

import com.shellx.link.account.RelayApiException
import java.io.IOException

/** Why a sign-in or an account deletion failed (SignInError.swift, without the password and Apple cases). */
sealed class SignInException(message: String) : Exception(message) {
    class InvalidCredentials : SignInException("invalid_credentials")

    class RateLimited : SignInException("rate_limited")

    class Network : SignInException("network")

    data class Server(val code: String) : SignInException("server")

    /** The previous account's data could not be removed from this phone yet; nobody can sign in until it is. */
    class LocalWipePending : SignInException("local_wipe_pending")

    /** The user closed Google's sheet: nothing to show. */
    class Cancelled : SignInException("cancelled")

    /** The email belongs to a password account that must switch from a device that is still signed in. */
    class SwitchFromSignedInDevice : SignInException("switch_from_signed_in_device")

    /** Delete Account: the fresh sign-in was another account or too old. */
    class ReauthRequired : SignInException("reauth_required")

    /** This build cannot offer Google sign-in (no client ID). */
    class ProviderUnavailable : SignInException("provider_unavailable")

    /** Google did not finish the sign-in. */
    class ProviderFailed : SignInException("provider_failed")

    companion object {
        /**
         * Maps what the relay and the identity provider threw; the first match wins. Http(401, "invalid_credentials")
         * → InvalidCredentials; Http(401, "reauth_required") → ReauthRequired; Http(409, "switch_from_signed_in_device")
         * → SwitchFromSignedInDevice; Http(429, _) → RateLimited; Http(_, code) → Server(code); BadResponse →
         * Server("bad_response"); IOException → Network; IdentityProviderException Cancelled / NotConfigured / Failed →
         * Cancelled / ProviderUnavailable / ProviderFailed; anything else → Server("unknown").
         */
        fun of(error: Throwable): SignInException = when (error) {
            is RelayApiException.Http -> when {
                error.status == 401 && error.code == "invalid_credentials" -> InvalidCredentials()
                error.status == 401 && error.code == "reauth_required" -> ReauthRequired()
                error.status == 409 && error.code == "switch_from_signed_in_device" -> SwitchFromSignedInDevice()
                error.status == 429 -> RateLimited()
                else -> Server(error.code)
            }
            is RelayApiException.BadResponse -> Server("bad_response")
            is IOException -> Network()
            is IdentityProviderException.Cancelled -> Cancelled()
            is IdentityProviderException.NotConfigured -> ProviderUnavailable()
            is IdentityProviderException.Failed -> ProviderFailed()
            else -> Server("unknown")
        }
    }
}
