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
}
