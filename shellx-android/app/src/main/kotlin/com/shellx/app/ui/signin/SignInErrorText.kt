package com.shellx.app.ui.signin

import androidx.annotation.StringRes
import com.shellx.app.R
import com.shellx.core.account.SignInException

/** What the sign-in screen and Delete Account say for each failure (1C's `SignInErrorText`): Google's, and the emailed code's. */
object SignInErrorText {
    /** Null for Cancelled: closing Google's sheet is not an error, and nothing is shown. */
    @StringRes
    fun message(error: SignInException): Int? = when (error) {
        is SignInException.InvalidCredentials -> R.string.signin_error_invalid_credentials
        is SignInException.RateLimited -> R.string.signin_error_rate_limited
        is SignInException.Network -> R.string.signin_error_network
        is SignInException.Server -> R.string.signin_error_server
        is SignInException.LocalWipePending -> R.string.signin_error_local_wipe_pending
        is SignInException.Cancelled -> null
        is SignInException.SwitchFromSignedInDevice -> R.string.signin_error_switch_from_signed_in_device
        is SignInException.ReauthRequired -> R.string.signin_error_reauth_required
        is SignInException.ProviderUnavailable -> R.string.signin_error_provider_unavailable
        is SignInException.ProviderFailed -> R.string.signin_error_provider_failed
        is SignInException.InvalidEmail -> R.string.signin_error_invalid_email
        is SignInException.DisposableEmail -> R.string.signin_error_disposable_email
        is SignInException.InvalidCode -> R.string.signin_error_invalid_code
        is SignInException.CodeExpired -> R.string.signin_error_code_expired
        is SignInException.EmailSendFailed -> R.string.signin_error_email_send_failed
    }
}
