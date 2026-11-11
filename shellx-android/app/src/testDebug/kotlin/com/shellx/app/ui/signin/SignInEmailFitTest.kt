package com.shellx.app.ui.signin

import androidx.activity.ComponentActivity
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.assertIsNotFocused
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpRect
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.ManualClock
import com.shellx.app.testing.imeInset
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.account.EmailCodeActions
import com.shellx.core.account.EmailSignInModel
import com.shellx.link.account.EmailChallenge
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The first screen's email field and the code step with the keyboard up, where a phone is smallest: the Pixel 3 (393 ×
 * 713 dp between its bars), with Vietnamese and with large text, and turned (737 × 369 dp). A tap on the field brings
 * the keyboard, and the intro folds to the small logo and the title: the field and Send code stand above the keyboard
 * and keep the focus. The keyboard going down with an empty field brings the whole intro back; with an address typed
 * the intro stays folded and the keyboard moves nothing. Robolectric shows no keyboard: its room comes as the system's
 * inset ([imeInset]); the test hands it in after the tap, as a phone does.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE) // Real text metrics, so the lines are as long and as tall as on a phone.
class SignInEmailFitTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()

    private val requests = mutableListOf<String>()
    private val email = EmailCodeActions(
        requestCode = { address, _ ->
            requests += address
            EmailChallenge("c1", 600, 60, address)
        },
        verify = { _, _ -> },
    )

    private fun show() {
        val restore = mutableStateOf<EmailSignInModel.Saved?>(null)
        rule.setContent {
            ShellXTheme {
                SignInView(expired = false, signIn = {}, startDemo = {}, email = email, clock = ManualClock(), emailRestore = restore)
            }
        }
    }

    /** Shows the first screen and taps its field, as a phone does: the field has the focus, the keyboard is not up yet. */
    private fun tapTheField() {
        show()
        rule.onNodeWithTag("signin.email.field").assertIsNotFocused().performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("signin.email.field").assertIsFocused()
    }

    private fun openTheCodeStep(address: String = "phu@example.com") {
        tapTheField()
        rule.onNodeWithTag("signin.email.field").performTextInput(address)
        rule.onNodeWithTag("signin.email.send").performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("signin.email.code").assertIsFocused()
    }

    private fun bounds(tag: String): DpRect = rule.onNodeWithTag(tag).getUnclippedBoundsInRoot()

    private fun exists(tag: String): Boolean = rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()

    private fun window(): DpRect = rule.onRoot().getUnclippedBoundsInRoot()

    /** Each of [tags] is whole inside the window and ends above a keyboard [keyboard] tall, as the screen stands. */
    private fun assertAboveTheKeyboard(keyboard: Dp, vararg tags: String) {
        val window = window()
        for (tag in tags) {
            val box = bounds(tag)
            assertTrue("$tag has a size ($box)", box.width > 0.dp && box.height > 0.dp)
            assertTrue(
                "$tag $box is whole inside the window $window",
                box.left >= window.left && box.top >= window.top && box.right <= window.right && box.bottom <= window.bottom,
            )
            assertTrue(
                "$tag ends at ${box.bottom}, above the keyboard's top at ${window.bottom - keyboard}",
                box.bottom <= window.bottom - keyboard,
            )
        }
    }

    private fun logoWidth(): Dp = bounds("signin.logo").width

    private fun assertFolded() {
        assertTrue("the logo is ${logoWidth()} wide", abs((logoWidth() - 72.dp).value) < 0.5f)
        for (gone in listOf("signin.tagline", "signin.subtitle", "signin.guide.1")) {
            assertFalse("$gone folds away while the keyboard is up", exists(gone))
        }
    }

    private fun assertTheFieldStandsAboveTheKeyboard() {
        tapTheField()
        rule.imeInset(KEYBOARD)

        assertFolded()
        assertAboveTheKeyboard(KEYBOARD, "signin.logo", "signin.title", "signin.email.field", "signin.email.send")
        rule.onNodeWithTag("signin.email.field").assertIsFocused()
        // Google and the demo link stay on the screen, under the keyboard if they must.
        for (tag in listOf("signin.or", "signin.google", "signin.demo")) rule.onNodeWithTag(tag).assertExists()
    }

    @Test
    @Config(qualifiers = PIXEL_3)
    fun onThePixel3TheFieldStandsAboveTheKeyboard() = assertTheFieldStandsAboveTheKeyboard()

    @Test
    @Config(qualifiers = "vi-$PIXEL_3")
    fun onThePixel3TheFieldStandsAboveTheKeyboardInVietnamese() = assertTheFieldStandsAboveTheKeyboard()

    @Test
    @Config(qualifiers = PIXEL_3, fontScale = 1.3f)
    fun onThePixel3TheFieldStandsAboveTheKeyboardWithLargeText() = assertTheFieldStandsAboveTheKeyboard()

    @Test
    @Config(qualifiers = "vi-$PIXEL_3", fontScale = 1.3f)
    fun onThePixel3TheFieldStandsAboveTheKeyboardWithLargeVietnameseText() = assertTheFieldStandsAboveTheKeyboard()

    @Test
    @Config(qualifiers = PIXEL_3)
    fun theKeyboardGoingDownWithAnEmptyFieldBringsTheWholeIntroBack() {
        tapTheField()
        assertTrue("whole before the keyboard comes", abs((logoWidth() - 96.dp).value) < 0.5f)
        rule.imeInset(KEYBOARD)
        assertFolded()

        // The system's Back puts the keyboard down and leaves the focus where it was.
        rule.imeInset(0.dp)
        assertTrue("the big logo is back: ${logoWidth()}", abs((logoWidth() - 96.dp).value) < 0.5f)
        for (tag in listOf("signin.tagline", "signin.guide.1", "signin.guide.3")) rule.onNodeWithTag(tag).assertIsDisplayed()
        rule.onNodeWithTag("signin.email.field").assertIsFocused()

        // The keyboard again: folded again, and the same field still has the focus.
        rule.imeInset(KEYBOARD)
        assertFolded()
        rule.onNodeWithTag("signin.email.field").assertIsFocused()
    }

    @Test
    @Config(qualifiers = PIXEL_3)
    fun withAnAddressTypedTheKeyboardMovesNothing() {
        tapTheField()
        rule.imeInset(KEYBOARD)
        rule.onNodeWithTag("signin.email.field").performTextInput("phu@example.com")
        rule.waitForIdle()
        val still = listOf("signin.logo", "signin.title", "signin.email.field", "signin.email.send")
        val before = still.associateWith { bounds(it) }
        assertFolded()

        rule.imeInset(0.dp)
        assertEquals("with the keyboard down", before, still.associateWith { bounds(it) })
        assertFolded()
        rule.imeInset(KEYBOARD)
        assertEquals("with the keyboard up again", before, still.associateWith { bounds(it) })
        rule.onNodeWithTag("signin.email.field").assertIsFocused()
    }

    private fun assertTheCodeStepStandsAboveTheKeyboard() {
        openTheCodeStep()
        rule.imeInset(KEYBOARD)
        assertAboveTheKeyboard(KEYBOARD, "signin.email.sentTo", "signin.email.code", "signin.email.verify")
    }

    @Test
    @Config(qualifiers = PIXEL_3)
    fun onThePixel3TheCodeStepStandsAboveTheKeyboard() = assertTheCodeStepStandsAboveTheKeyboard()

    @Test
    @Config(qualifiers = "vi-$PIXEL_3")
    fun onThePixel3TheCodeStepStandsAboveTheKeyboardInVietnamese() = assertTheCodeStepStandsAboveTheKeyboard()

    @Test
    @Config(qualifiers = PIXEL_3, fontScale = 1.3f)
    fun largeTextInTheCodeStepKeepsTheFieldAboveTheKeyboard() {
        openTheCodeStep()
        rule.imeInset(KEYBOARD)

        assertAboveTheKeyboard(KEYBOARD, "signin.email.code")
        for (tag in listOf("signin.email.verify", "signin.email.resend", "signin.email.change")) {
            rule.onNodeWithTag(tag).performScrollTo().assertIsDisplayed()
        }
    }

    @Test
    @Config(qualifiers = PIXEL_3_TURNED)
    fun inLandscapeTheFocusedFieldComesAboveTheKeyboard() {
        tapTheField()
        rule.imeInset(LANDSCAPE_KEYBOARD)
        assertAboveTheKeyboard(LANDSCAPE_KEYBOARD, "signin.email.field")
        assertTrue("the logo is beside the field", bounds("signin.logo").right <= bounds("signin.email.field").left)

        rule.onNodeWithTag("signin.email.field").performTextInput("phu@example.com")
        rule.onNodeWithTag("signin.email.send").performScrollTo().performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("signin.email.code").assertIsFocused()
        // The keyboard stays up from one field to the next, as on a phone.
        rule.imeInset(LANDSCAPE_KEYBOARD)
        assertAboveTheKeyboard(LANDSCAPE_KEYBOARD, "signin.email.code")
        assertTrue("the logo is beside the field", bounds("signin.logo").right <= bounds("signin.email.code").left)
    }

    /** Review Focus 6. */
    @Test
    @Config(qualifiers = PIXEL_3)
    fun aVeryLongEmailWrapsInsideTheWindow() {
        val address = "a".repeat(60) + "@example-company-mail.com"
        openTheCodeStep(address)
        assertEquals(listOf(address), requests)

        val sentTo = bounds("signin.email.sentTo")
        assertTrue("the line $sentTo wraps inside the window ${window()}", sentTo.left >= window().left && sentTo.right <= window().right)
        assertTrue("it takes more lines, not more width: $sentTo", sentTo.height > 60.dp)
        for (tag in listOf("signin.email.code", "signin.email.verify")) {
            rule.onNodeWithTag(tag).performScrollTo().assertIsDisplayed()
        }
    }

    private companion object {
        /** The Pixel 3's window between its status bar (24 dp) and its three-button bar (48 dp). */
        const val PIXEL_3 = "w393dp-h713dp-440dpi"

        /** The same phone turned: the three-button bar is at the side. */
        const val PIXEL_3_TURNED = "w737dp-h369dp-land-440dpi"

        /**
         * Gboard in portrait above the navigation bar, with room to spare: measured on the API 36 emulator (1080 × 2340,
         * 440 dpi) at 255 dp above a three-button bar (the Pixel 3's) and 279 dp above the gesture bar. 300 dp stands for
         * a taller keyboard (Gboard's number row, a larger keyboard height), so the field is checked above more than the
         * default keyboard takes.
         */
        val KEYBOARD = 300.dp

        /** Gboard on a phone held sideways (measured on the API 36 emulator, ledger A-36). */
        val LANDSCAPE_KEYBOARD = 251.dp
    }
}
