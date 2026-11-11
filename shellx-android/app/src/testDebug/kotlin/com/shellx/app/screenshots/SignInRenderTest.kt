package com.shellx.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.demo.DemoBanner
import com.shellx.app.ui.onboarding.FirstMacView
import com.shellx.app.ui.signin.SignInContent
import com.shellx.app.ui.signin.SignInView
import com.shellx.core.account.EmailSignInState
import com.shellx.core.account.EmailSignInState.Step
import com.shellx.core.account.SignInException
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Sign-in (its first screen is the email step, Google below) with the code step, the first-Mac screen and the demo
 * banner (SignInRenderTests, MachinesRenderTests, DemoRenderTests). No render focuses a field: a cursor blinks, and a
 * capture never settles; "keyboard up" draws the screen as it stands with a keyboard, in the room the keyboard leaves.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
class SignInRenderTest {
    @Test
    fun signIn() {
        assertRenders("signin") { SignInView(expired = false, signIn = {}, startDemo = {}) }
    }

    @Test
    fun signInError() {
        assertRenders("signin-error") {
            SignInView(expired = false, signIn = {}, startDemo = {}, initialError = SignInException.SwitchFromSignedInDevice())
        }
    }

    @Test
    fun signInExpired() {
        assertRenders("signin-expired") { SignInView(expired = true, signIn = {}, startDemo = {}) }
    }

    /** The Pixel 3's window between its status bar and its three-button bar (393 × 713 dp). */
    @Test
    @Config(qualifiers = "w393dp-h713dp-xxhdpi")
    fun signInOnThePixel3() {
        assertRenders("signin-pixel3") { SignInView(expired = false, signIn = {}, startDemo = {}) }
    }

    @Test
    @Config(fontScale = 1.3f)
    fun signInWithLargeText() {
        assertRenders("signin-large-font") { SignInView(expired = false, signIn = {}, startDemo = {}) }
    }

    @Test
    @Config(qualifiers = "w393dp-h713dp-xxhdpi", fontScale = 1.3f)
    fun signInOnThePixel3WithLargeText() {
        assertRenders("signin-pixel3-large-font") { SignInView(expired = false, signIn = {}, startDemo = {}) }
    }

    /** A phone turned: the logo and the words beside the buttons, no steps (under 400 dp of height). */
    @Test
    @Config(qualifiers = "w785dp-h393dp-land-xxhdpi")
    fun signInInLandscape() {
        assertRenders("signin-landscape", width = 2355) { SignInView(expired = false, signIn = {}, startDemo = {}) }
    }

    @Test
    @Config(qualifiers = "w785dp-h393dp-land-xxhdpi", fontScale = 1.3f)
    fun signInInLandscapeWithLargeText() {
        assertRenders("signin-landscape-large-font", width = 2355) {
            SignInView(expired = true, signIn = {}, startDemo = {})
        }
    }

    /** A window under 600 dp tall: the small logo, and the taglines stand in for the subtitle. */
    @Test
    @Config(qualifiers = "w360dp-h592dp-xxhdpi")
    fun signInOnAShortPhone() {
        assertRenders("signin-short-phone", width = 1080) { SignInView(expired = false, signIn = {}, startDemo = {}) }
    }

    /** A tablet turned: the steps stand beside the logo, above the buttons. */
    @Test
    @Config(qualifiers = "w1280dp-h752dp-land-mdpi")
    fun signInOnATabletInLandscape() {
        assertRenders("signin-tablet-landscape", width = 1280) { SignInView(expired = false, signIn = {}, startDemo = {}) }
    }

    // The first screen and the code step, drawn from a state.

    @Composable
    private fun EmailSteps(state: EmailSignInState, keyboardUp: Boolean = false) {
        SignInContent(
            expired = false, error = null, busy = false, continueWithGoogle = {}, startDemo = {}, introMs = null, email = state,
            keyboardUp = keyboardUp,
        )
    }

    /** The screen in the room a keyboard [keyboard] tall leaves, the keyboard's place drawn as a plain block. */
    @Composable
    private fun AboveAKeyboard(keyboard: Dp, content: @Composable () -> Unit) {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f).fillMaxWidth()) { content() }
            Box(Modifier.fillMaxWidth().height(keyboard).background(MaterialTheme.colorScheme.surfaceVariant))
        }
    }

    private fun code(
        code: String = "123",
        step: Step = Step.CODE,
        resendInSeconds: Int = 42,
        codeDead: Boolean = false,
        error: SignInException? = null,
    ) = EmailSignInState(step, "phu@example.com", code, resendInSeconds, codeDead = codeDead, error = error)

    /** An address typed and the keyboard down: the intro stays folded. */
    @Test
    fun emailStep() {
        assertRenders("signin-email") { EmailSteps(EmailSignInState(Step.EMAIL, email = "phu@example.com")) }
    }

    @Test
    fun emailStepSending() {
        assertRenders("signin-email-sending") { EmailSteps(EmailSignInState(Step.SENDING, email = "phu@example.com")) }
    }

    @Test
    fun emailStepError() {
        assertRenders("signin-email-error") {
            EmailSteps(EmailSignInState(Step.EMAIL, email = "phu@example", error = SignInException.InvalidEmail()))
        }
    }

    @Test
    fun codeStep() {
        assertRenders("signin-code") { EmailSteps(code()) }
    }

    @Test
    fun codeStepError() {
        assertRenders("signin-code-error") { EmailSteps(code(code = "", error = SignInException.InvalidCode())) }
    }

    @Test
    fun codeStepExpired() {
        assertRenders("signin-code-expired") {
            EmailSteps(code(code = "", resendInSeconds = 0, codeDead = true, error = SignInException.CodeExpired()))
        }
    }

    @Test
    fun codeStepVerifying() {
        assertRenders("signin-code-verifying") { EmailSteps(code(code = "123456", step = Step.VERIFYING)) }
    }

    @Test
    @Config(qualifiers = "w393dp-h713dp-xxhdpi")
    fun emailStepOnThePixel3() {
        assertRenders("signin-email-pixel3") { EmailSteps(EmailSignInState(Step.EMAIL, email = "phu@example.com")) }
    }

    @Test
    @Config(qualifiers = "w393dp-h713dp-xxhdpi")
    fun codeStepOnThePixel3() {
        assertRenders("signin-code-pixel3") { EmailSteps(code()) }
    }

    @Test
    @Config(qualifiers = "w393dp-h713dp-xxhdpi", fontScale = 1.3f)
    fun codeStepOnThePixel3WithLargeText() {
        assertRenders("signin-code-pixel3-large-font") { EmailSteps(code()) }
    }

    @Test
    @Config(qualifiers = "w785dp-h393dp-land-xxhdpi")
    fun codeStepInLandscape() {
        assertRenders("signin-code-landscape", width = 2355) { EmailSteps(code()) }
    }

    /** The Pixel 3 just after a tap on the field: a 300 dp keyboard up, the intro folded (the keyboard is a plain block). */
    @Test
    @Config(qualifiers = "w393dp-h713dp-xxhdpi")
    fun firstScreenAboveTheKeyboard() {
        assertRenders("signin-keyboard") { AboveAKeyboard(300.dp) { EmailSteps(EmailSignInState(Step.EMAIL), keyboardUp = true) } }
    }

    @Test
    @Config(qualifiers = "w393dp-h713dp-xxhdpi", fontScale = 1.3f)
    fun firstScreenAboveTheKeyboardWithLargeText() {
        assertRenders("signin-keyboard-large-font") {
            AboveAKeyboard(300.dp) { EmailSteps(EmailSignInState(Step.EMAIL), keyboardUp = true) }
        }
    }

    @Test
    @Config(qualifiers = "w393dp-h713dp-xxhdpi")
    fun emailStepAboveTheKeyboard() {
        assertRenders("signin-email-keyboard") {
            AboveAKeyboard(300.dp) { EmailSteps(EmailSignInState(Step.EMAIL, email = "phu@example.com"), keyboardUp = true) }
        }
    }

    @Test
    @Config(qualifiers = "w393dp-h713dp-xxhdpi")
    fun codeStepAboveTheKeyboard() {
        assertRenders("signin-code-keyboard") {
            AboveAKeyboard(300.dp) { EmailSteps(code(error = SignInException.InvalidCode()), keyboardUp = true) }
        }
    }

    @Test
    @Config(qualifiers = "w393dp-h713dp-xxhdpi", fontScale = 1.3f)
    fun codeStepAboveTheKeyboardWithLargeText() {
        assertRenders("signin-code-keyboard-large-font") { AboveAKeyboard(300.dp) { EmailSteps(code(), keyboardUp = true) } }
    }

    /** A phone turned with its 251 dp keyboard up: the email field is what is left to see. */
    @Test
    @Config(qualifiers = "w785dp-h393dp-land-xxhdpi")
    fun emailStepInLandscapeAboveTheKeyboard() {
        assertRenders("signin-email-keyboard-landscape", width = 2355) {
            AboveAKeyboard(251.dp) { EmailSteps(EmailSignInState(Step.EMAIL), keyboardUp = true) }
        }
    }

    @Test
    fun firstMac() {
        assertRenders("first-mac") { FirstMacView(pair = {}, tryDemo = null, openSettings = {}) }
    }

    @Test
    fun firstMacDemo() {
        assertRenders("first-mac-demo") { FirstMacView(pair = {}, tryDemo = {}, openSettings = {}) }
    }

    @Test
    fun demoBanner() {
        assertRenders("demo-banner") {
            Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
                DemoBanner(exit = {})
                Spacer(Modifier.weight(1f))
            }
        }
    }
}
