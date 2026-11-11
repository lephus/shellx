package com.shellx.app.ui.signin

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.core.account.SignInException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** What the sign-in screen says for each failure (1C's SignInErrorText): Google's, and the email code's. */
@RunWith(AndroidJUnit4::class)
class SignInErrorTextTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun everyFailureHasItsOwnWords() {
        val failures = listOf(
            SignInException.InvalidCredentials(), SignInException.RateLimited(), SignInException.Network(),
            SignInException.Server("x"), SignInException.LocalWipePending(), SignInException.SwitchFromSignedInDevice(),
            SignInException.ReauthRequired(), SignInException.ProviderUnavailable(), SignInException.ProviderFailed(),
            SignInException.InvalidEmail(), SignInException.DisposableEmail(), SignInException.InvalidCode(),
            SignInException.CodeExpired(), SignInException.EmailSendFailed(),
        )
        val ids = failures.map { SignInErrorText.message(it) }
        assertTrue(ids.all { it != null })
        val words = ids.map { context.getString(it!!) }
        assertTrue(words.none { it.isEmpty() })
        assertEquals(14, words.toSet().size)
    }

    @Test
    fun theEmailFailuresUseTheirOwnStrings() {
        assertEquals(R.string.signin_error_invalid_email, SignInErrorText.message(SignInException.InvalidEmail()))
        assertEquals(R.string.signin_error_disposable_email, SignInErrorText.message(SignInException.DisposableEmail()))
        assertEquals(R.string.signin_error_invalid_code, SignInErrorText.message(SignInException.InvalidCode()))
        assertEquals(R.string.signin_error_code_expired, SignInErrorText.message(SignInException.CodeExpired()))
        assertEquals(R.string.signin_error_email_send_failed, SignInErrorText.message(SignInException.EmailSendFailed()))
    }

    @Test
    fun closingGoogleSheetSaysNothing() {
        assertNull(SignInErrorText.message(SignInException.Cancelled()))
    }
}
