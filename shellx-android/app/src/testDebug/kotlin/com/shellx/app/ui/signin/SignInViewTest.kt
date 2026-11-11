package com.shellx.app.ui.signin

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasProgressBarRangeInfo
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.text.AnnotatedString
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.screenshots.ShellXSnapshots
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.account.SignInException
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Continue with Google: one sign-in at a time, the failures in words, and "Try without an account"; and the intro
 * around them (the logo, the typed taglines, the three steps), which never holds the buttons back.
 */
@RunWith(AndroidJUnit4::class)
class SignInViewTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()
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
    fun theThreeStepsAreNumberedAndReadAsOneEach() {
        show(signIn = {})

        val steps = listOf(R.string.signin_guide_1, R.string.signin_guide_2, R.string.signin_guide_3)
        for ((index, words) in steps.withIndex()) {
            rule.onNodeWithTag("signin.guide.${index + 1}").assertTextEquals("${index + 1}", context.getString(words))
        }
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
