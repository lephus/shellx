package com.shellx.app.ui.signin

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.account.SignInException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** What the sign-in screen says for each failure (1C's SignInErrorText, Google only). */
@RunWith(AndroidJUnit4::class)
class SignInErrorTextTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun everyFailureHasItsOwnWords() {
        val failures = listOf(
            SignInException.InvalidCredentials(), SignInException.RateLimited(), SignInException.Network(),
            SignInException.Server("x"), SignInException.LocalWipePending(), SignInException.SwitchFromSignedInDevice(),
            SignInException.ReauthRequired(), SignInException.ProviderUnavailable(), SignInException.ProviderFailed(),
        )
        val ids = failures.map { SignInErrorText.message(it) }
        assertTrue(ids.all { it != null })
        val words = ids.map { context.getString(it!!) }
        assertTrue(words.none { it.isEmpty() })
        assertEquals(9, words.toSet().size)
    }

    @Test
    fun closingGoogleSheetSaysNothing() {
        assertNull(SignInErrorText.message(SignInException.Cancelled()))
    }
}
