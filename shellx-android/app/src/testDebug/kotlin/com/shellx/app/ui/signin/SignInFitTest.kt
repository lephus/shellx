package com.shellx.app.ui.signin

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpRect
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.account.SignInException
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
 * The sign-in screen holds in every window it must: the Pixel 3 (393 × 785 dp, about 713 dp between its bars), turned
 * (737 × 369 dp), a short phone, a tablet, each with large text too (font scale 1.3). Robolectric draws no system
 * bars, so a window here is the room between them.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE) // Real text metrics, so the lines are as long and as tall as on a phone.
class SignInFitTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()

    private fun show(expired: Boolean = false, error: SignInException? = null) {
        rule.setContent {
            ShellXTheme { SignInView(expired = expired, signIn = {}, startDemo = {}, initialError = error) }
        }
    }

    private fun bounds(tag: String): DpRect = rule.onNodeWithTag(tag).getUnclippedBoundsInRoot()

    private fun exists(tag: String): Boolean = rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()

    private fun assertDp(what: String, expected: Dp, actual: Dp) =
        assertTrue("$what is $actual, expected $expected", abs((expected - actual).value) < 0.5f)

    /** Each of [tags] is whole inside the window as it stands: nothing is clipped and nothing needs a scroll. */
    private fun assertWholeOnScreen(vararg tags: String) {
        val window = rule.onRoot().getUnclippedBoundsInRoot()
        for (tag in tags) {
            val box = bounds(tag)
            assertTrue("$tag has a size ($box)", box.width > 0.dp && box.height > 0.dp)
            assertTrue(
                "$tag $box is whole inside the window $window",
                box.left >= window.left && box.top >= window.top && box.right <= window.right && box.bottom <= window.bottom,
            )
        }
    }

    /** [tags] stand one under another in this order, none over the next. */
    private fun assertStacked(vararg tags: String) {
        for ((above, below) in tags.toList().zipWithNext()) {
            assertTrue(
                "$above ends at ${bounds(above).bottom}, before $below starts at ${bounds(below).top}",
                bounds(above).bottom <= bounds(below).top,
            )
        }
    }

    private fun assertThePortraitScreenFits() {
        assertWholeOnScreen(*PORTRAIT)
        assertStacked(*PORTRAIT)
        assertDp("the logo", 96.dp, bounds("signin.logo").width)
        assertDp("the logo", 96.dp, bounds("signin.logo").height)
    }

    private fun assertTheLandscapeScreenFits() {
        assertWholeOnScreen("signin.logo", "signin.title", "signin.tagline", "signin.google", "signin.demo")
        assertStacked("signin.logo", "signin.title", "signin.tagline")
        assertStacked("signin.google", "signin.demo")
        assertDp("the logo", 72.dp, bounds("signin.logo").width)
        assertFalse("no steps under 400 dp of height", exists("signin.guide.1"))
        assertFalse(exists("signin.subtitle"))
        for (left in listOf("signin.logo", "signin.title", "signin.tagline")) {
            assertTrue("$left is beside the buttons", bounds(left).right <= bounds("signin.google").left)
        }
    }

    @Test
    @Config(qualifiers = PIXEL_3)
    fun thePixel3ShowsTheWholeScreenWithoutAScroll() {
        show()
        assertThePortraitScreenFits()
        val window = rule.onRoot().getUnclippedBoundsInRoot()
        assertDp("the room under the buttons, which stand at the bottom,", 24.dp, window.bottom - bounds("signin.demo").bottom)
    }

    @Test
    @Config(qualifiers = "vi-$PIXEL_3")
    fun thePixel3ShowsTheWholeScreenInVietnamese() {
        show()
        assertThePortraitScreenFits()
    }

    @Test
    @Config(qualifiers = PIXEL_3, fontScale = 1.3f)
    fun largeTextOnThePixel3ClipsNothing() {
        show()
        assertThePortraitScreenFits()
    }

    @Test
    @Config(qualifiers = "vi-$PIXEL_3", fontScale = 1.3f)
    fun largeVietnameseTextOnThePixel3ClipsNothing() {
        show()
        assertThePortraitScreenFits()
    }

    @Test
    @Config(qualifiers = PIXEL_3)
    fun theTaglineKeepsRoomForTwoLines() {
        show()
        // bodyMedium's line is 20 sp tall.
        assertTrue("the tagline is ${bounds("signin.tagline").height} tall", bounds("signin.tagline").height >= 39.dp)
    }

    @Test
    @Config(qualifiers = PIXEL_3, fontScale = 1.3f)
    fun nothingMovesWhileTheIntroPlaysAndTheTaglinesChange() {
        rule.mainClock.autoAdvance = false
        show()
        val still = PORTRAIT.filterNot { it.startsWith("signin.guide.") }
        val steps = PORTRAIT.filter { it.startsWith("signin.guide.") }
        val first = still.associateWith { bounds(it) }
        for (step in steps) {
            assertTrue("$step is there from the first frame", exists(step))
        }

        rule.mainClock.advanceTimeBy(SignInIntro.SETTLED_MS + 100)
        val settled = steps.associateWith { bounds(it) }
        assertStacked(*PORTRAIT)

        // Through the first tagline's hold, its erasing, the second one (which wraps here) and into the third.
        var passed = 0L
        while (passed < 12_000) {
            rule.mainClock.advanceTimeBy(700)
            passed += 700
            assertEquals("after $passed ms", first, still.associateWith { bounds(it) })
            assertEquals("after $passed ms", settled, steps.associateWith { bounds(it) })
        }
    }

    @Test
    @Config(qualifiers = PIXEL_3)
    fun aFailureStandsBetweenTheStepsAndTheButtons() {
        show(expired = true, error = SignInException.SwitchFromSignedInDevice())
        assertStacked("signin.guide.3", "signin.expired", "signin.error", "signin.google", "signin.demo")
        rule.onNodeWithTag("signin.demo").performScrollTo().assertIsDisplayed()
        rule.onNodeWithTag("signin.logo").performScrollTo().assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = PIXEL_3_TURNED)
    fun inLandscapeTheLogoAndTheWordsStandBesideTheButtons() {
        show()
        assertTheLandscapeScreenFits()
    }

    @Test
    @Config(qualifiers = "vi-$PIXEL_3_TURNED", fontScale = 1.3f)
    fun largeVietnameseTextInLandscapeClipsNothing() {
        show()
        assertTheLandscapeScreenFits()
    }

    @Test
    @Config(qualifiers = PIXEL_3_TURNED, fontScale = 1.3f)
    fun aFailureInLandscapeWithLargeTextIsReachedByAScroll() {
        show(error = SignInException.SwitchFromSignedInDevice())
        assertStacked("signin.error", "signin.google", "signin.demo")
        for (tag in listOf("signin.error", "signin.demo", "signin.logo")) {
            rule.onNodeWithTag(tag).performScrollTo().assertIsDisplayed()
        }
    }

    @Test
    @Config(qualifiers = "w360dp-h592dp-xhdpi")
    fun aShortPhoneHasTheSmallLogoAndNoSubtitle() {
        show()
        val shown = PORTRAIT.filterNot { it == "signin.subtitle" }.toTypedArray()
        assertWholeOnScreen(*shown)
        assertStacked(*shown)
        assertDp("the logo", 72.dp, bounds("signin.logo").width)
        assertFalse("the taglines stand in for the subtitle", exists("signin.subtitle"))
    }

    @Test
    @Config(qualifiers = "w1280dp-h752dp-land-mdpi")
    fun aTabletInLandscapeKeepsTheStepsBesideTheLogo() {
        show()
        assertWholeOnScreen(*PORTRAIT)
        assertStacked("signin.logo", "signin.title", "signin.tagline", "signin.subtitle")
        assertStacked("signin.guide.1", "signin.guide.2", "signin.guide.3", "signin.google", "signin.demo")
        assertDp("the logo", 72.dp, bounds("signin.logo").width)
        assertTrue(bounds("signin.title").right <= bounds("signin.guide.1").left)
    }

    private companion object {
        /** The Pixel 3's window between its status bar (24 dp) and its three-button bar (48 dp). */
        const val PIXEL_3 = "w393dp-h713dp-440dpi"

        /** The same phone turned: the three-button bar is at the side. */
        const val PIXEL_3_TURNED = "w737dp-h369dp-land-440dpi"

        /** Everything a tall portrait window shows, from the top. */
        val PORTRAIT = arrayOf(
            "signin.logo", "signin.title", "signin.tagline", "signin.subtitle",
            "signin.guide.1", "signin.guide.2", "signin.guide.3", "signin.google", "signin.demo",
        )
    }
}
