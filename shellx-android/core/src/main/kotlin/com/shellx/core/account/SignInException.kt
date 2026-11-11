package com.shellx.core.account

import com.shellx.link.account.RelayApiException
import java.io.IOException

/**
 * Why a sign-in or an account deletion failed (SignInError.swift, without the password and Apple cases), Google's
 * and the emailed code's.
 */
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

    /** This build cannot offer this way in: no Google client ID, or a relay without email sign-in. */
    class ProviderUnavailable : SignInException("provider_unavailable")

    /** Google did not finish the sign-in. */
    class ProviderFailed : SignInException("provider_failed")

    /** The relay does not take the address as an email address. */
    class InvalidEmail : SignInException("invalid_email")

    /** The address is of a throwaway mail service. */
    class DisposableEmail : SignInException("disposable_email")

    /** The code is wrong; the same code may be tried again (five tries in all). */
    class InvalidCode : SignInException("invalid_code")

    /** The code is gone: it expired, was used, or this was the fifth wrong try. Only a new one helps. */
    class CodeExpired : SignInException("code_expired")

    /** The relay could not hand the email to its mail service. */
    class EmailSendFailed : SignInException("email_send_failed")

    companion object {
        /**
         * Maps what the relay and the identity provider threw; the first match wins. Http(401, "invalid_credentials")
         * → InvalidCredentials; Http(401, "reauth_required") → ReauthRequired; Http(409, "switch_from_signed_in_device")
         * → SwitchFromSignedInDevice; Http(429, _) → RateLimited; the email code's Http(400, "invalid_email") →
         * InvalidEmail, Http(400, "disposable_email") → DisposableEmail, Http(401, "invalid_code") → InvalidCode,
         * Http(410, "code_expired") → CodeExpired, Http(502, "email_send_failed") → EmailSendFailed and
         * Http(503, "email_sign_in_disabled") → ProviderUnavailable; Http(_, code) → Server(code); BadResponse →
         * Server("bad_response"); IOException → Network; IdentityProviderException Cancelled / NotConfigured / Failed →
         * Cancelled / ProviderUnavailable / ProviderFailed; anything else → Server("unknown").
         */
        fun of(error: Throwable): SignInException = when (error) {
            is RelayApiException.Http -> when {
                error.status == 401 && error.code == "invalid_credentials" -> InvalidCredentials()
                error.status == 401 && error.code == "reauth_required" -> ReauthRequired()
                error.status == 409 && error.code == "switch_from_signed_in_device" -> SwitchFromSignedInDevice()
                error.status == 429 -> RateLimited()
                error.status == 400 && error.code == "invalid_email" -> InvalidEmail()
                error.status == 400 && error.code == "disposable_email" -> DisposableEmail()
                error.status == 401 && error.code == "invalid_code" -> InvalidCode()
                error.status == 410 && error.code == "code_expired" -> CodeExpired()
                error.status == 502 && error.code == "email_send_failed" -> EmailSendFailed()
                error.status == 503 && error.code == "email_sign_in_disabled" -> ProviderUnavailable()
                else -> Server(error.code)
            }
            is RelayApiException.BadResponse -> Server("bad_response")
            is IOException -> Network()
            is IdentityProviderException.Cancelled -> Cancelled()
            is IdentityProviderException.NotConfigured -> ProviderUnavailable()
            is IdentityProviderException.Failed -> ProviderFailed()
            else -> Server("unknown")
        }

        /**
         * For the three email calls (code request, verify, deletion by code): any Http 404 → ProviderUnavailable, since
         * a relay without the feature answers `404 not_found` and a proxy in front of it a 404 with no JSON; everything
         * else as [of].
         */
        fun ofEmail(error: Throwable): SignInException =
            if (error is RelayApiException.Http && error.status == 404) ProviderUnavailable() else of(error)
    }
}
