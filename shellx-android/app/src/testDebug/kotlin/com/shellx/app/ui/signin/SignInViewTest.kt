package com.shellx.app.ui.signin

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusManager
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.input.InputModeManager
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.SoftwareKeyboardController
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsNotFocused
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasProgressBarRangeInfo
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.text.AnnotatedString
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.shellx.app.R
import com.shellx.app.screenshots.ShellXSnapshots
import com.shellx.app.testing.ManualClock
import com.shellx.app.ui.components.TapOutsideHidesKeyboard
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.account.EmailCodeActions
import com.shellx.core.account.EmailSignInModel
import com.shellx.core.account.SignInException
import com.shellx.link.account.EmailChallenge
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Continue with Google: one sign-in at a time, the failures in words, and "Try without an account"; the intro around
 * them (the logo, the typed taglines, the three steps), which never holds the buttons back; and Continue with email:
 * the email step and the code step in the same screen, over a relay the test scripts.
 */
@RunWith(AndroidJUnit4::class)
class SignInViewTest {
    /**
     * A phone's window is in touch mode, and Robolectric's is not: outside it Android hands the focus a field gave up
     * straight back to the window's first focusable, which on an email step is that field. Set before the window is made.
     */
    @get:Rule(order = 0) val touchMode = object : ExternalResource() {
        override fun before() = InstrumentationRegistry.getInstrumentation().setInTouchMode(true)
    }

    @get:Rule(order = 1) val rule = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()

    private val clock = ManualClock()

    /** The code requests and the verifies the screen made, in order. */
    private val requests = mutableListOf<Pair<String, String>>()
    private val verifies = mutableListOf<Pair<String, String>>()

    /** What the next code requests and verifies throw, one each; then they succeed. */
    private val requestFailures = ArrayDeque<SignInException>()
    private val verifyFailures = ArrayDeque<SignInException>()

    /** While set, a verify waits for it. */
    private var heldVerify: CompletableDeferred<Unit>? = null

    /** While set, a code request waits for it. */
    private var heldRequest: CompletableDeferred<Unit>? = null

    /** The relay as the test scripts it: every challenge is "c1", for the address trimmed and in lower case. */
    private val email = EmailCodeActions(
        requestCode = { address, locale ->
            requests += address to locale
            heldRequest?.await()
            requestFailures.removeFirstOrNull()?.let { throw it }
            EmailChallenge("c1", 600, 60, address.trim().lowercase())
        },
        verify = { challengeId, code ->
            verifies += challengeId to code
            heldVerify?.await()
            verifyFailures.removeFirstOrNull()?.let { throw it }
        },
    )

    private fun show(
        expired: Boolean = false,
        signIn: suspend () -> Unit = {},
        startDemo: (() -> Unit)? = {},
        emailRestore: MutableState<EmailSignInModel.Saved?> = mutableStateOf(null),
    ) {
        rule.setContent { ShellXTheme { Screen(expired, signIn, startDemo, emailRestore) } }
    }

    @Composable
    private fun Screen(
        expired: Boolean = false,
        signIn: suspend () -> Unit = {},
        startDemo: (() -> Unit)? = {},
        emailRestore: MutableState<EmailSignInModel.Saved?>,
    ) {
        SignInView(
            expired = expired, signIn = signIn, startDemo = startDemo, email = email, clock = clock, emailRestore = emailRestore,
        )
    }

    private fun string(id: Int) = context.getString(id)

    /** What a field shows: its editable text. */
    private fun fieldText(tag: String): String =
        rule.onNodeWithTag(tag).fetchSemanticsNode().config[SemanticsProperties.EditableText].text

    /** From the first screen to the code step for [address], by taps and typing. */
    private fun reachTheCodeStep(address: String = "phu@example.com") {
        rule.onNodeWithTag("signin.email.field").performClick()
        rule.onNodeWithTag("signin.email.field").performTextInput(address)
        rule.onNodeWithTag("signin.email.send").performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("signin.email.code").assertExists()
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
    fun aSignInInProgressSurvivesARotation() {
        // Review B m-3 (carry 3D-3): the progress lives in a ViewModel, so a recreated activity still waits.
        val answer = CompletableDeferred<Unit>()
        var calls = 0
        val screen: @Composable () -> Unit = {
            ShellXTheme {
                SignInView(expired = false, signIn = {
                    calls++
                    answer.await()
                }, startDemo = {})
            }
        }
        rule.setContent(screen)
        rule.onNodeWithTag("signin.google").performClick()
        rule.waitForIdle()
        assertEquals(1, calls)

        rule.activityRule.scenario.recreate()
        rule.activityRule.scenario.onActivity { it.setContent(content = screen) }
        rule.waitForIdle()

        rule.onNode(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate), useUnmergedTree = true).assertExists()
        rule.onNodeWithTag("signin.demo").assertIsNotEnabled()
        rule.onNodeWithTag("signin.google").performClick()
        rule.waitForIdle()
        assertEquals("a tap after the rotation joins nothing new", 1, calls)

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

    /** The tagline's text: the whole line, as TalkBack reads it. */
    private fun taglineLine(): AnnotatedString =
        rule.onNodeWithTag("signin.tagline").fetchSemanticsNode().config[SemanticsProperties.Text].single()

    /** The letters typed so far: the line up to its unseen rest. */
    private fun typed(): String {
        val line = taglineLine()
        val unseenFrom = line.spanStyles.firstOrNull { it.item.color == Color.Transparent }?.start ?: line.length
        return line.text.substring(0, unseenFrom)
    }

    @Test
    @Config(qualifiers = WITH_THE_STEPS)
    fun theButtonsWorkFromTheFirstFrame() {
        // Not one frame of the intro passes: the clock stands still.
        rule.mainClock.autoAdvance = false
        var signIns = 0
        var demos = 0
        show(signIn = { signIns++ }, startDemo = { demos++ })

        assertEquals("nothing is typed yet", "", typed())
        rule.onNodeWithTag("signin.google").assertIsDisplayed().assertIsEnabled().performClick()
        rule.onNodeWithTag("signin.demo").assertIsDisplayed().assertIsEnabled().performClick()
        assertEquals(1, signIns)
        assertEquals(1, demos)
    }

    @Test
    fun theTaglinesAreTypedOneAfterAnother() {
        rule.mainClock.autoAdvance = false
        show(signIn = {})
        val first = context.getString(R.string.signin_tagline_1)
        val second = context.getString(R.string.signin_tagline_2)

        assertEquals("the whole line is there for TalkBack from the start", first, taglineLine().text)
        assertEquals("", typed())

        // The first frame starts the clock; typing starts when the logo's chevrons are in place.
        rule.mainClock.advanceTimeBy(TypedTagline.START_MS + 10 * TypedTagline.TYPE_MS)
        val some = typed()
        assertTrue("some of the first tagline is typed: \"$some\"", some.isNotEmpty() && some.length < first.length)
        assertTrue(first.startsWith(some))

        rule.mainClock.advanceTimeBy(first.length * TypedTagline.TYPE_MS + 100)
        assertEquals("typed to the end, and held", first, typed())
        rule.mainClock.advanceTimeBy(TypedTagline.HOLD_MS / 2)
        assertEquals(first, typed())

        rule.mainClock.advanceTimeBy(
            TypedTagline.HOLD_MS / 2 + first.length * TypedTagline.ERASE_MS + TypedTagline.PAUSE_MS + 10 * TypedTagline.TYPE_MS,
        )
        assertEquals("erased, and the second one follows", second, taglineLine().text)
        val next = typed()
        assertTrue("some of the second tagline is typed: \"$next\"", next.isNotEmpty() && next.length < second.length)
    }

    @Test
    @Config(qualifiers = WITH_THE_STEPS)
    fun withAnimationsOffTheFirstTaglineAndTheStepsAreThereAtOnce() {
        ShellXSnapshots.withoutAnimations {
            rule.mainClock.autoAdvance = false
            show(signIn = {})
            val first = context.getString(R.string.signin_tagline_1)

            assertEquals("whole, without a frame passing", first, typed())
            for (step in 1..3) rule.onNodeWithTag("signin.guide.$step").assertIsDisplayed()

            rule.mainClock.advanceTimeBy(20_000)
            assertEquals("no typewriter: it stays", first, typed())
            assertEquals(first, taglineLine().text)
        }
    }

    @Test
    fun theClockCountsFromTheFirstFrameAndStopsWhenTheScreenLeaves() {
        rule.mainClock.autoAdvance = false
        var clock: (() -> Long)? = null
        var shown by mutableStateOf(true)
        rule.setContent { if (shown) clock = rememberSignInIntroClock() }

        rule.mainClock.advanceTimeBy(500)
        val early = clock!!()
        assertTrue("about 500 ms after the first frame: $early", early in 440L..512L)

        // Once the intro has settled the clock moves at most 30 times a second, at any frame rate.
        rule.mainClock.advanceTimeBy(1_500)
        val readings = mutableSetOf<Long>()
        repeat(60) {
            rule.mainClock.advanceTimeByFrame()
            readings += clock!!()
        }
        assertTrue("${readings.size} readings in 60 frames", readings.size in 25..31)
        assertTrue(readings.all { it % SignInIntro.FRAME_MS == 0L })

        shown = false
        rule.mainClock.advanceTimeByFrame()
        val last = clock!!()
        rule.mainClock.advanceTimeBy(5_000)
        assertEquals("nothing runs once the screen has left", last, clock!!())
    }

    @Test
    fun withAnimationsOffThereIsNoClock() {
        ShellXSnapshots.withoutAnimations {
            var clock: (() -> Long)? = { 0L }
            rule.setContent { clock = rememberSignInIntroClock() }
            rule.waitForIdle()
            assertNull(clock)
        }
    }

    @Test
    fun aRotationCarriesTheIntroOnInsteadOfPlayingItAgain() {
        rule.mainClock.autoAdvance = false
        val screen: @Composable () -> Unit = {
            ShellXTheme { SignInView(expired = false, signIn = {}, startDemo = {}) }
        }
        rule.setContent(screen)
        val first = context.getString(R.string.signin_tagline_1)
        rule.mainClock.advanceTimeBy(TypedTagline.START_MS + first.length * TypedTagline.TYPE_MS + 500)
        assertEquals(first, typed())

        rule.activityRule.scenario.recreate()
        rule.activityRule.scenario.onActivity { it.setContent(content = screen) }
        rule.mainClock.advanceTimeByFrame()

        assertEquals("the tagline is still typed: the intro did not start over", first, typed())
    }

    @Test
    fun animationsTurnedOffWhileTheAppWasAwayStopTheIntroOnReturn() {
        rule.mainClock.autoAdvance = false
        show(signIn = {})
        val first = context.getString(R.string.signin_tagline_1)
        rule.mainClock.advanceTimeBy(TypedTagline.START_MS + 5 * TypedTagline.TYPE_MS)
        assertTrue("typing: \"${typed()}\"", typed().length < first.length)

        rule.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
        ShellXSnapshots.withoutAnimations {
            rule.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
            rule.mainClock.advanceTimeByFrame()
            assertEquals("the first tagline, whole", first, typed())
            rule.mainClock.advanceTimeBy(10_000)
            assertEquals("and still", first, typed())
        }
    }

    @Test
    fun theLogoIsAnImageNamedShellXLogo() {
        show(signIn = {})

        rule.onNodeWithTag("signin.logo")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("ShellX logo")))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Image))
        rule.onNodeWithTag("signin.title")
            .assertTextEquals(context.getString(R.string.signin_title))
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
    }

    @Test
    @Config(qualifiers = WITH_THE_STEPS)
    fun theThreeStepsAreNumberedAndReadAsOneEach() {
        show(signIn = {})

        val steps = listOf(R.string.signin_guide_1, R.string.signin_guide_2, R.string.signin_guide_3)
        for ((index, words) in steps.withIndex()) {
            rule.onNodeWithTag("signin.guide.${index + 1}").assertTextEquals("${index + 1}", context.getString(words))
        }
    }

    // The email step is the first screen.

    @Test
    @Config(qualifiers = WITH_THE_STEPS)
    fun theFirstScreenIsTheEmailStepWithGoogleBelow() {
        show()
        rule.waitForIdle()
        val order = listOf("signin.email.field", "signin.email.send", "signin.or", "signin.google", "signin.demo")
        for ((above, below) in order.zipWithNext()) {
            val a = rule.onNodeWithTag(above).assertIsDisplayed().getUnclippedBoundsInRoot()
            val b = rule.onNodeWithTag(below).assertIsDisplayed().getUnclippedBoundsInRoot()
            assertTrue("$above ($a) stands above $below ($b)", a.bottom <= b.top)
        }
        rule.onNodeWithTag("signin.email.send").assertTextEquals(string(R.string.signin_email_send)).assertIsNotEnabled()
        rule.onNode(hasText(string(R.string.signin_email_continue))).assertDoesNotExist()
        rule.onNodeWithTag("signin.email").assertDoesNotExist()

        // No keyboard on arrival: nothing has the focus, and the whole intro shows.
        rule.onNodeWithTag("signin.email.field").assertIsNotFocused()
        rule.onNodeWithTag("signin.tagline").assertIsDisplayed()
        assertFalse("Back is the system's on the first screen", rule.activity.onBackPressedDispatcher.hasEnabledCallbacks())
        assertEquals(emptyList<Pair<String, String>>(), requests)
    }

    @Test
    fun sendCodeIsOnOnceTheFieldHoldsAnAddress() {
        show()
        rule.onNodeWithTag("signin.email.field").performClick()
        rule.onNodeWithTag("signin.email.field").performTextInput("phu@")
        rule.onNodeWithTag("signin.email.send").assertIsNotEnabled()
        rule.onNodeWithTag("signin.email.field").performTextInput("example.com")
        rule.onNodeWithTag("signin.email.send").assertIsEnabled()
    }

    /**
     * A keyboard's Tab goes top to bottom: the field, Send code, Google, the demo link (TalkBack reads in the same order:
     * [theFirstScreenIsTheEmailStepWithGoogleBelow]). Tab leaves touch mode, as on a phone with a keyboard.
     */
    @OptIn(ExperimentalComposeUiApi::class)
    @Test
    @Config(qualifiers = WITH_THE_STEPS)
    fun theFocusGoesFromTheFieldToSendThenGoogleThenTheDemo() {
        var focusManager: FocusManager? = null
        var inputMode: InputModeManager? = null
        rule.setContent {
            ShellXTheme {
                focusManager = LocalFocusManager.current
                inputMode = LocalInputModeManager.current
                Screen(emailRestore = mutableStateOf(null))
            }
        }
        rule.onNodeWithTag("signin.email.field").performClick()
        rule.onNodeWithTag("signin.email.field").performTextInput("phu@example.com")
        rule.onNodeWithTag("signin.email.field").assertIsFocused()
        rule.runOnIdle { inputMode!!.requestInputMode(InputMode.Keyboard) }
        for (tag in listOf("signin.email.send", "signin.google", "signin.demo")) {
            rule.runOnIdle { focusManager!!.moveFocus(FocusDirection.Next) }
            rule.onNodeWithTag(tag).assertIsFocused()
        }
    }

    @Test
    fun whileGoogleRunsTheEmailStepIsOff() {
        val answer = CompletableDeferred<Unit>()
        show(signIn = { answer.await() })
        rule.onNodeWithTag("signin.email.field").performClick()
        rule.onNodeWithTag("signin.email.field").performTextInput("phu@example.com")
        rule.onNodeWithTag("signin.email.send").assertIsEnabled()

        rule.onNodeWithTag("signin.google").performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("signin.email.field").assertIsNotEnabled()
        rule.onNodeWithTag("signin.email.send").assertIsNotEnabled()
        rule.onNodeWithTag("signin.demo").assertIsNotEnabled()

        answer.complete(Unit)
        rule.waitForIdle()
        rule.onNodeWithTag("signin.email.field").assertIsEnabled()
        rule.onNodeWithTag("signin.email.send").assertIsEnabled()
        assertEquals(emptyList<Pair<String, String>>(), requests)
    }

    @Test
    fun whileACodeIsAskedForGoogleIsOff() {
        heldRequest = CompletableDeferred()
        show()
        rule.onNodeWithTag("signin.email.field").performClick()
        rule.onNodeWithTag("signin.email.field").performTextInput("phu@example.com")
        rule.onNodeWithTag("signin.email.send").performClick()
        rule.waitForIdle()

        rule.onNodeWithTag("signin.email.field").assertIsNotEnabled()
        rule.onNodeWithTag("signin.email.send").assertIsNotEnabled()
        rule.onNodeWithTag("signin.google").assertIsNotEnabled()
        rule.onNodeWithTag("signin.demo").assertIsNotEnabled()
        assertTrue("Back waits for the relay", rule.activity.onBackPressedDispatcher.hasEnabledCallbacks())

        heldRequest?.complete(Unit)
        rule.waitForIdle()
        rule.onNodeWithTag("signin.email.code").assertIsFocused()
        rule.onNodeWithTag("signin.google").assertDoesNotExist()
    }

    /** Review Focus 1 and 3: a pasted "123 456" signs in by itself, once. */
    @Test
    fun aCodeSignsInOnceAndAutoSubmits() {
        heldVerify = CompletableDeferred()
        show()
        rule.onNodeWithTag("signin.email.field").performClick()
        rule.onNodeWithTag("signin.email.field").performTextInput("Phu@Example.com")
        rule.onNodeWithTag("signin.email.send").performClick()
        rule.waitForIdle()
        assertEquals(listOf("Phu@Example.com" to "en"), requests)
        rule.onNodeWithTag("signin.email.sentTo").assertTextEquals(context.getString(R.string.signin_email_sent_to, "phu@example.com"))
        rule.onNodeWithTag("signin.email.code").assertIsFocused()
        rule.onNodeWithTag("signin.demo").assertDoesNotExist()
        rule.onNodeWithTag("signin.google").assertDoesNotExist()

        rule.onNodeWithTag("signin.email.code").performTextInput("123 456")
        rule.waitForIdle()
        assertEquals("the sixth digit verifies, with no tap", listOf("c1" to "123456"), verifies)
        rule.onNodeWithTag("signin.email.verify").assertIsNotEnabled()
        rule.onNodeWithTag("signin.email.code").assertIsNotEnabled()

        heldVerify?.complete(Unit)
        rule.waitForIdle()
        assertEquals(1, verifies.size)
        rule.onNodeWithTag("signin.email.verify").assertIsNotEnabled()
    }

    @Test
    fun aWrongCodeShowsItsWordsAndTakesANewOne() {
        verifyFailures += SignInException.InvalidCode()
        show()
        reachTheCodeStep()
        rule.onNodeWithTag("signin.email.code").performTextInput("123456")
        rule.waitForIdle()

        rule.onNodeWithTag("signin.email.error").assertTextEquals(string(R.string.signin_error_invalid_code))
        rule.onNodeWithTag("signin.email.code").assertIsEnabled()
        assertEquals("", fieldText("signin.email.code"))

        rule.onNodeWithTag("signin.email.code").performTextInput("654321")
        rule.waitForIdle()
        assertEquals(listOf("c1" to "123456", "c1" to "654321"), verifies)
    }

    /** Review Focus 2: the relay's 410 turns the field off and opens Resend at once, in the middle of the countdown. */
    @Test
    fun anExpiredCodeOffersResendAtOnce() {
        verifyFailures += SignInException.CodeExpired()
        show()
        reachTheCodeStep()
        rule.onNodeWithTag("signin.email.resend").assertTextEquals("Resend code in 60 s").assertIsNotEnabled()
        rule.onNodeWithTag("signin.email.code").performTextInput("123456")
        rule.waitForIdle()

        rule.onNodeWithTag("signin.email.error").assertTextEquals(string(R.string.signin_error_code_expired))
        rule.onNodeWithTag("signin.email.code").assertIsNotEnabled()
        rule.onNodeWithTag("signin.email.resend").assertTextEquals("Resend code").assertIsEnabled().performClick()
        rule.waitForIdle()

        assertEquals(listOf("phu@example.com" to "en", "phu@example.com" to "en"), requests)
        rule.onNodeWithTag("signin.email.code").assertIsEnabled()
        rule.onNodeWithTag("signin.email.resend").assertTextEquals("Resend code in 60 s").assertIsNotEnabled()
        rule.onNodeWithTag("signin.email.error").assertDoesNotExist()
    }

    @Test
    fun anOldRelaySaysNotAvailableInThisBuild() {
        requestFailures += SignInException.ProviderUnavailable()
        show()
        rule.onNodeWithTag("signin.email.field").performClick()
        rule.onNodeWithTag("signin.email.field").performTextInput("phu@example.com")
        rule.onNodeWithTag("signin.email.send").performClick()
        rule.waitForIdle()

        rule.onNodeWithTag("signin.email.error").assertTextEquals(string(R.string.signin_error_provider_unavailable))
        assertEquals("phu@example.com", fieldText("signin.email.field"))
        rule.onNodeWithTag("signin.email.code").assertDoesNotExist()
    }

    /** Review Focus 7: nothing typed is lost, and nothing retries by itself. */
    @Test
    fun offlineKeepsWhatWasTyped() {
        requestFailures += SignInException.Network()
        show()
        rule.onNodeWithTag("signin.email.field").performClick()
        rule.onNodeWithTag("signin.email.field").performTextInput("phu@example.com")
        rule.onNodeWithTag("signin.email.send").performClick()
        rule.waitForIdle()

        rule.onNodeWithTag("signin.email.error").assertTextEquals(string(R.string.signin_error_network))
        assertEquals("phu@example.com", fieldText("signin.email.field"))
        rule.onNodeWithTag("signin.email.send").assertIsEnabled()
        assertEquals(1, requests.size)

        // The same in the code step: the digits stay, and Verify works on a second tap.
        rule.onNodeWithTag("signin.email.send").performClick()
        rule.waitForIdle()
        verifyFailures += SignInException.Network()
        rule.onNodeWithTag("signin.email.code").performTextInput("123456")
        rule.waitForIdle()
        rule.onNodeWithTag("signin.email.error").assertTextEquals(string(R.string.signin_error_network))
        assertEquals("123456", fieldText("signin.email.code"))
        assertEquals(1, verifies.size)
        rule.onNodeWithTag("signin.email.verify").assertIsEnabled().performClick()
        rule.waitForIdle()
        assertEquals(listOf("c1" to "123456", "c1" to "123456"), verifies)
    }

    @Test
    fun useADifferentEmailGoesBackToTheFirstScreenWithTheAddress() {
        show()
        reachTheCodeStep("Phu@Example.com")
        assertTrue("Back goes a step back from the code step", rule.activity.onBackPressedDispatcher.hasEnabledCallbacks())
        rule.onNodeWithTag("signin.email.change").performClick()
        rule.waitForIdle()

        assertEquals("phu@example.com", fieldText("signin.email.field"))
        // On the way back the field takes the focus: a different address is what comes next.
        rule.onNodeWithTag("signin.email.field").assertIsFocused()
        rule.onNodeWithTag("signin.email.code").assertDoesNotExist()
        rule.onNodeWithTag("signin.email.send").assertIsEnabled()
        rule.onNodeWithTag("signin.google").assertIsDisplayed()
        rule.onNodeWithTag("signin.demo").assertIsDisplayed()
        assertFalse(rule.activity.onBackPressedDispatcher.hasEnabledCallbacks())

        // Back from the code step is the same step back.
        rule.onNodeWithTag("signin.email.send").performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("signin.email.code").assertExists()
        rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        rule.waitForIdle()
        assertEquals("phu@example.com", fieldText("signin.email.field"))
        rule.onNodeWithTag("signin.google").assertIsDisplayed()
        assertFalse("then Back is the system's again", rule.activity.onBackPressedDispatcher.hasEnabledCallbacks())
        assertEquals(2, requests.size)
    }

    /** Review Focus 5: nothing is asked or sent again. */
    @Test
    fun theCodeStepSurvivesARotation() {
        val restore = mutableStateOf<EmailSignInModel.Saved?>(null)
        val screen: @Composable () -> Unit = { ShellXTheme { Screen(emailRestore = restore) } }
        rule.setContent(screen)
        reachTheCodeStep()
        rule.onNodeWithTag("signin.email.code").performTextInput("123")
        rule.waitForIdle()

        rule.activityRule.scenario.recreate()
        rule.activityRule.scenario.onActivity { it.setContent(content = screen) }
        rule.waitForIdle()

        rule.onNodeWithTag("signin.email.sentTo").assertExists()
        assertEquals("123", fieldText("signin.email.code"))
        assertEquals(1, requests.size)

        // A verify on the relay goes on across a rotation, and is not sent a second time.
        heldVerify = CompletableDeferred()
        rule.onNodeWithTag("signin.email.code").performTextInput("456")
        rule.waitForIdle()
        assertEquals(listOf("c1" to "123456"), verifies)
        rule.activityRule.scenario.recreate()
        rule.activityRule.scenario.onActivity { it.setContent(content = screen) }
        rule.waitForIdle()
        rule.onNodeWithTag("signin.email.verify").assertIsNotEnabled()
        heldVerify?.complete(Unit)
        rule.waitForIdle()
        assertEquals(1, verifies.size)
        assertEquals(1, requests.size)
    }

    /** Review Focus 4: Android killed the app while the mail was read. */
    @Test
    fun aSavedCodeStepIsShownAtOnce() {
        val saved = EmailSignInModel.Saved("phu@example.com", "c1", clock.nowMs() + 600_000, clock.nowMs() + 40_000)
        show(emailRestore = mutableStateOf(saved))
        rule.waitForIdle()

        rule.onNodeWithTag("signin.email.code").assertIsDisplayed().assertIsEnabled()
        rule.onNodeWithTag("signin.email.sentTo").assertTextEquals(context.getString(R.string.signin_email_sent_to, "phu@example.com"))
        rule.onNodeWithTag("signin.email.resend").assertTextEquals("Resend code in 40 s")
        rule.onNodeWithTag("signin.google").assertDoesNotExist()
        assertEquals(emptyList<Pair<String, String>>(), requests)

        // Its code goes to the challenge that was saved.
        rule.onNodeWithTag("signin.email.code").performTextInput("123456")
        rule.waitForIdle()
        assertEquals(listOf("c1" to "123456"), verifies)
    }

    @Test
    fun theScreenWritesWhatAKilledAppNeeds() {
        val restore = mutableStateOf<EmailSignInModel.Saved?>(null)
        show(emailRestore = restore)
        rule.waitForIdle()
        assertNull("nothing while the field is empty", restore.value)

        rule.onNodeWithTag("signin.email.field").performClick()
        rule.onNodeWithTag("signin.email.field").performTextInput("phu@example.com")
        rule.waitForIdle()
        assertEquals(EmailSignInModel.Saved("phu@example.com", null, 0, 0), restore.value)

        rule.onNodeWithTag("signin.email.send").performClick()
        rule.waitForIdle()
        assertEquals(
            EmailSignInModel.Saved("phu@example.com", "c1", clock.nowMs() + 600_000, clock.nowMs() + 60_000),
            restore.value,
        )

        rule.onNodeWithTag("signin.email.code").performTextInput("123456")
        rule.waitForIdle()
        assertEquals(1, verifies.size)
        assertNull("signed in: nothing to come back to", restore.value)
    }

    @Test
    fun aTapOutsideTheFieldPutsTheKeyboardDownAndKeepsTheStep() {
        var hides = 0
        val keyboard = object : SoftwareKeyboardController {
            override fun show() = Unit

            override fun hide() {
                hides++
            }
        }
        val restore = mutableStateOf<EmailSignInModel.Saved?>(null)
        rule.setContent {
            ShellXTheme {
                CompositionLocalProvider(LocalSoftwareKeyboardController provides keyboard) {
                    TapOutsideHidesKeyboard { Screen(emailRestore = restore) }
                }
            }
        }
        rule.onNodeWithTag("signin.email.field").performClick()
        rule.onNodeWithTag("signin.email.field").performTextInput("phu@example.com")
        rule.onNodeWithTag("signin.email.field").assertIsFocused()

        assertTrue("the window is in touch mode, as on a phone", rule.activity.window.decorView.isInTouchMode)
        rule.onNodeWithTag("signin.logo").performClick()
        rule.waitUntil(5_000) { hides == 1 }
        rule.onNodeWithTag("signin.email.field").assertIsNotFocused()
        assertEquals("phu@example.com", fieldText("signin.email.field"))

        rule.onNodeWithTag("signin.email.field").performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("signin.email.field").assertIsFocused()

        rule.onNodeWithTag("signin.email.send").performClick()
        rule.waitForIdle()
        assertEquals("a tap on a button hides nothing", 1, hides)
        assertEquals(1, requests.size)
    }

    @Test
    fun aShortWindowLeavesTheStepsOut() {
        // Robolectric's own window is 320 × 470 dp: under 705 dp of height the field and the buttons need the steps' room.
        show()
        rule.onNodeWithTag("signin.guide.1").assertDoesNotExist()
        for (tag in listOf("signin.email.field", "signin.email.send", "signin.or", "signin.google", "signin.demo")) {
            rule.onNodeWithTag(tag).assertExists()
        }
    }

    @Test
    @Config(qualifiers = WITH_THE_STEPS)
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

    private companion object {
        /** The Pixel 3's window between its bars: tall enough (705 dp) for the three steps above the field. */
        const val WITH_THE_STEPS = "w393dp-h713dp"
    }
}
