package com.shellx.core.account

import com.shellx.core.testing.assertSameCase
import com.shellx.link.account.RelayApiException
import java.io.IOException
import kotlin.test.Test

class SignInExceptionTest {
    /** 1C Task 4's table without email_in_use and identity_in_use, which Android never receives. */
    @Test fun relayAndProviderErrorsMap() {
        val cases: List<Pair<Throwable, SignInException>> = listOf(
            RelayApiException.Http(401, "invalid_credentials") to SignInException.InvalidCredentials(),
            RelayApiException.Http(401, "reauth_required") to SignInException.ReauthRequired(),
            RelayApiException.Http(409, "switch_from_signed_in_device") to SignInException.SwitchFromSignedInDevice(),
            RelayApiException.Http(429, "rate_limited") to SignInException.RateLimited(),
            RelayApiException.Http(400, "invalid_email") to SignInException.InvalidEmail(),
            RelayApiException.Http(400, "disposable_email") to SignInException.DisposableEmail(),
            RelayApiException.Http(401, "invalid_code") to SignInException.InvalidCode(),
            RelayApiException.Http(410, "code_expired") to SignInException.CodeExpired(),
            RelayApiException.Http(502, "email_send_failed") to SignInException.EmailSendFailed(),
            RelayApiException.Http(503, "email_sign_in_disabled") to SignInException.ProviderUnavailable(),
            RelayApiException.Http(500, "boom") to SignInException.Server("boom"),
            RelayApiException.BadResponse() to SignInException.Server("bad_response"),
            IOException("offline") to SignInException.Network(),
            IdentityProviderException.Cancelled() to SignInException.Cancelled(),
            IdentityProviderException.NotConfigured() to SignInException.ProviderUnavailable(),
            IdentityProviderException.Failed() to SignInException.ProviderFailed(),
            IllegalStateException("no such file") to SignInException.Server("unknown"),
        )
        for ((error, expected) in cases) assertSameCase(expected, SignInException.of(error), "$error")
    }

    /** A relay without email sign-in answers the three email calls with a 404 (its own, or a proxy's). */
    @Test fun emailCallsReadA404AsNotAvailable() {
        val cases: List<Pair<Throwable, SignInException>> = listOf(
            RelayApiException.Http(404, "not_found") to SignInException.ProviderUnavailable(),
            RelayApiException.Http(404, "unknown") to SignInException.ProviderUnavailable(),
            RelayApiException.Http(503, "email_sign_in_disabled") to SignInException.ProviderUnavailable(),
            RelayApiException.Http(401, "invalid_code") to SignInException.InvalidCode(),
            RelayApiException.Http(429, "rate_limited") to SignInException.RateLimited(),
            IOException("offline") to SignInException.Network(),
        )
        for ((error, expected) in cases) assertSameCase(expected, SignInException.ofEmail(error), "$error")
        // The Google paths keep their reading of a 404.
        assertSameCase(SignInException.Server("not_found"), SignInException.of(RelayApiException.Http(404, "not_found")))
    }
}
