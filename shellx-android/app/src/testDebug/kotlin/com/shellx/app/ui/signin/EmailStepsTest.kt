package com.shellx.app.ui.signin

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasProgressBarRangeInfo
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performImeAction
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.testing.autofillHints
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.account.EmailSignInState
import com.shellx.core.account.EmailSignInState.Step
import com.shellx.core.account.SignInException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The email step and the code step drawn from a state: what each shows, what is on and off, and what a tap reports. */
@RunWith(AndroidJUnit4::class)
class EmailStepsTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()

    private val emails = mutableListOf<String>()
    private val codes = mutableListOf<String>()
    private var sends = 0
    private var verifies = 0
    private var resends = 0
    private var changes = 0
    private val calls = EmailStepCalls(
        setEmail = { emails += it },
        send = { sends++ },
        setCode = { codes += it },
        verify = { verifies++ },
        resend = { resends++ },
        changeEmail = { changes++ },
    )

    private fun string(id: Int) = context.getString(id)

    private fun show(content: @Composable () -> Unit) = rule.setContent { ShellXTheme { content() } }

    private fun emailStep(state: EmailSignInState, enabled: Boolean = true) =
        show { EmailStep(state, calls, autoFocus = false, enabled = enabled) }

    private fun codeStep(state: EmailSignInState) = show { CodeStep(state, calls, autoFocus = false) }

    private fun code(
        code: String = "",
        step: Step = Step.CODE,
        resendInSeconds: Int = 42,
        codeDead: Boolean = false,
        error: SignInException? = null,
    ) = EmailSignInState(step, "phu@example.com", code, resendInSeconds, codeDead = codeDead, error = error)

    /** What the field shows: its editable text. */
    private fun fieldText(tag: String): String =
        rule.onNodeWithTag(tag).fetchSemanticsNode().config[SemanticsProperties.EditableText].text

    private fun contentHints(tag: String): Set<String> =
        autofillHints(rule.onNodeWithTag(tag).fetchSemanticsNode().config[SemanticsProperties.ContentType])

    @Test
    fun theEmailStepSendsOnlyWhatLooksLikeAnEmail() {
        var state by mutableStateOf(EmailSignInState(Step.EMAIL, email = "phu@"))
        show { EmailStep(state, calls, autoFocus = false) }
        rule.onNodeWithTag("signin.email.send").assertIsNotEnabled()

        state = EmailSignInState(Step.EMAIL, email = "phu@example.com")
        rule.onNodeWithTag("signin.email.send").assertIsEnabled().assertTextEquals(string(R.string.signin_email_send)).performClick()
        assertEquals(1, sends)
        rule.onNodeWithTag("signin.email.field").performImeAction()
        assertEquals(2, sends)
        assertEquals("phu@example.com", fieldText("signin.email.field"))
    }

    @Test
    fun typingReportsTheAddressCutAt254() {
        emailStep(EmailSignInState(Step.EMAIL))
        rule.onNodeWithTag("signin.email.field").performTextInput("a".repeat(300))
        assertEquals(254, emails.last().length)
        assertEquals(254, fieldText("signin.email.field").length)
    }

    @Test
    fun theFieldsCarryTheirAutofillTypes() {
        var state by mutableStateOf(EmailSignInState(Step.EMAIL))
        show {
            if (state.step == Step.EMAIL) EmailStep(state, calls, autoFocus = false) else CodeStep(state, calls, autoFocus = false)
        }
        assertEquals(setOf("username", "emailAddress"), contentHints("signin.email.field"))
        state = code()
        assertEquals(setOf("smsOTPCode", "emailOTPCode"), contentHints("signin.email.code"))
    }

    @Test
    fun aFailureStandsUnderItsField() {
        var state by mutableStateOf(EmailSignInState(Step.EMAIL, email = "phu@example", error = SignInException.InvalidEmail()))
        show { EmailStep(state, calls, autoFocus = false) }
        rule.onNodeWithTag("signin.email.error")
            .assertTextEquals(string(R.string.signin_error_invalid_email))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite))
        val field = rule.onNodeWithTag("signin.email.field").getUnclippedBoundsInRoot()
        val error = rule.onNodeWithTag("signin.email.error").getUnclippedBoundsInRoot()
        val send = rule.onNodeWithTag("signin.email.send").getUnclippedBoundsInRoot()
        assertTrue("the failure $error is under the field $field", error.top >= field.bottom)
        assertTrue("and above the button $send", error.bottom <= send.top)

        state = EmailSignInState(Step.EMAIL, email = "phu@example.com", error = SignInException.ProviderUnavailable())
        rule.onNodeWithTag("signin.email.error").assertTextEquals(string(R.string.signin_error_provider_unavailable))

        state = EmailSignInState(Step.EMAIL, email = "phu@example.com")
        rule.onNodeWithTag("signin.email.error").assertDoesNotExist()
    }

    @Test
    fun sendingShowsASpinnerAndTurnsTheStepOff() {
        emailStep(EmailSignInState(Step.SENDING, email = "phu@example.com"))
        rule.onNodeWithTag("signin.email.field").assertIsNotEnabled()
        rule.onNodeWithTag("signin.email.send").assertIsNotEnabled()
        rule.onNode(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate), useUnmergedTree = true).assertExists()
        // TalkBack still hears the button's name.
        rule.onNodeWithTag("signin.email.send")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf(string(R.string.signin_email_send))))
    }

    /** The first screen turns its field off while Google signs in: neither the button nor the keyboard's Send sends. */
    @Test
    fun anEmailStepTurnedOffSendsNothing() {
        emailStep(EmailSignInState(Step.EMAIL, email = "phu@example.com"), enabled = false)
        rule.onNodeWithTag("signin.email.field").assertIsNotEnabled()
        rule.onNodeWithTag("signin.email.send").assertIsNotEnabled()
        assertEquals("phu@example.com", fieldText("signin.email.field"))
        assertEquals(0, sends)
    }

    /** The steps start idle until the screen starts them: the field already takes an address. */
    @Test
    fun anIdleStepIsTheEmailStep() {
        emailStep(EmailSignInState())
        rule.onNodeWithTag("signin.email.field").assertIsEnabled().performTextInput("phu@example.com")
        assertEquals("phu@example.com", emails.last())
    }

    @Test
    fun theCodeFieldShowsOnlySixDigits() {
        codeStep(code())
        rule.onNodeWithTag("signin.email.code").performTextInput("12 34-56 78")
        assertEquals("123456", codes.last())
        assertEquals("123456", fieldText("signin.email.code"))
    }

    @Test
    fun theCodeStepSaysWhereTheCodeWent() {
        codeStep(code())
        rule.onNodeWithTag("signin.email.sentTo")
            .assertTextEquals(context.getString(R.string.signin_email_sent_to, "phu@example.com"))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite))
    }

    @Test
    fun resendCountsDownThenOpens() {
        var state by mutableStateOf(code(resendInSeconds = 42))
        show { CodeStep(state, calls, autoFocus = false) }
        rule.onNodeWithTag("signin.email.resend").assertTextEquals("Resend code in 42 s").assertIsNotEnabled()

        state = code(resendInSeconds = 0)
        rule.onNodeWithTag("signin.email.resend").assertTextEquals("Resend code").assertIsEnabled().performClick()
        assertEquals(1, resends)
        rule.onNodeWithTag("signin.email.change").assertIsEnabled().performClick()
        assertEquals(1, changes)
    }

    @Test
    fun aDeadCodeTurnsTheFieldOffAndKeepsResend() {
        codeStep(code(resendInSeconds = 0, codeDead = true, error = SignInException.CodeExpired()))
        rule.onNodeWithTag("signin.email.code").assertIsNotEnabled()
        rule.onNodeWithTag("signin.email.verify").assertIsNotEnabled()
        rule.onNodeWithTag("signin.email.resend").assertIsEnabled()
        rule.onNodeWithTag("signin.email.error").assertTextEquals(string(R.string.signin_error_code_expired))
    }

    @Test
    fun theModelsClearedCodeEmptiesTheField() {
        var state by mutableStateOf(code(code = "123456"))
        show { CodeStep(state, calls, autoFocus = false) }
        assertEquals("123456", fieldText("signin.email.code"))
        rule.onNodeWithTag("signin.email.verify").assertIsEnabled().performClick()
        assertEquals(1, verifies)

        state = code(code = "", error = SignInException.InvalidCode())
        rule.waitForIdle()
        assertEquals("", fieldText("signin.email.code"))
        rule.onNodeWithTag("signin.email.verify").assertIsNotEnabled()
    }

    @Test
    fun verifyingTurnsEverythingOff() {
        codeStep(code(code = "123456", step = Step.VERIFYING))
        for (tag in listOf("signin.email.code", "signin.email.verify", "signin.email.resend", "signin.email.change")) {
            rule.onNodeWithTag(tag).assertIsNotEnabled()
        }
        rule.onNode(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate), useUnmergedTree = true).assertExists()
    }
}
