package com.shellx.app.ui.signin

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.account.SignInException
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Continue with Google: one sign-in at a time, the failures in words, and "Try without an account". */
@RunWith(AndroidJUnit4::class)
class SignInViewTest {
    @get:Rule val rule = createComposeRule()
    private val context: Context = ApplicationProvider.getApplicationContext()

    private fun show(expired: Boolean = false, signIn: suspend () -> Unit, startDemo: (() -> Unit)? = {}) {
        rule.setContent { ShellXTheme { SignInView(expired = expired, signIn = signIn, startDemo = startDemo) } }
    }

    @Test
    fun continueWithGoogleSignsInOnceAndWaits() {
        val answer = CompletableDeferred<Unit>()
        var calls = 0
        show(signIn = {
            calls++
            answer.await()
        })

        rule.onNodeWithTag("signin.google").performClick()
        rule.onNodeWithTag("signin.google").performClick()
        rule.waitForIdle()
        assertEquals(1, calls)
        rule.onNodeWithTag("signin.demo").assertIsNotEnabled()

        answer.complete(Unit)
        rule.waitForIdle()
        rule.onNodeWithTag("signin.demo").assertIsEnabled()
        rule.onNodeWithTag("signin.google").assertIsEnabled()
    }

    @Test
    fun aClosedGoogleSheetShowsNothing() {
        show(signIn = { throw SignInException.Cancelled() })

        rule.onNodeWithTag("signin.google").performClick()
        rule.waitForIdle()

        rule.onNodeWithTag("signin.error").assertDoesNotExist()
        rule.onNodeWithTag("signin.google").assertIsEnabled()
    }

    @Test
    fun aFailureShowsItsWordsInALiveRegion() {
        show(signIn = { throw SignInException.Network() })

        rule.onNodeWithTag("signin.google").performClick()
        rule.waitForIdle()

        rule.onNodeWithTag("signin.error")
            .assertTextEquals(context.getString(R.string.signin_error_network))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite))
    }

    @Test
    fun anExpiredSessionSaysSo() {
        show(expired = true, signIn = {})

        rule.onNodeWithTag("signin.expired").assertTextEquals(context.getString(R.string.signin_expired))
    }

    @Test
    fun tryWithoutAnAccountStartsTheDemo() {
        var demos = 0
        var offersDemo by mutableStateOf(true)
        rule.setContent {
            ShellXTheme { SignInView(expired = false, signIn = {}, startDemo = if (offersDemo) ({ demos++ }) else null) }
        }

        rule.onNodeWithText("Try without an account").performClick()
        assertEquals(1, demos)

        offersDemo = false
        rule.waitForIdle()
        rule.onNodeWithTag("signin.demo").assertDoesNotExist()
    }
}
