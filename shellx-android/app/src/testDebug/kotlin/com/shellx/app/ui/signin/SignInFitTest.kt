package com.shellx.app.ui.signin

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsNotFocused
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
 * The sign-in screen's first screen (the email field with Send code, "or", Google, the demo link) holds in every window
 * it must: the Pixel 3 (393 × 785 dp, about 713 dp between its bars) whole without a scroll at font scale 1.0 in English
 * and Vietnamese, turned (737 × 369 dp), a taller phone, a short phone, a tablet, the windows at the layout's
 * thresholds; with large text (font scale 1.3) a portrait screen may scroll, and nothing overlaps or is cut. Robolectric
 * draws no system bars, so a window here is the room between them.
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

    /** Large text: [tags] stand one under another, none cut at the sides, each reached by a scroll. */
    private fun assertTheScreenScrollsToEach(vararg tags: String) {
        assertStacked(*tags)
        val window = rule.onRoot().getUnclippedBoundsInRoot()
        for (tag in tags) {
            assertTrue("$tag is inside the window's sides", bounds(tag).left >= window.left && bounds(tag).right <= window.right)
        }
        for (tag in tags.reversed() + tags) rule.onNodeWithTag(tag).performScrollTo().assertIsDisplayed()
    }

    private fun assertTheLandscapeScreenFits() {
        assertWholeOnScreen("signin.logo", "signin.title", "signin.tagline", *CONTROLS)
        assertStacked("signin.logo", "signin.title", "signin.tagline")
        assertStacked(*CONTROLS)
        assertDp("the logo", 72.dp, bounds("signin.logo").width)
        assertFalse("no steps under 400 dp of height", exists("signin.guide.1"))
        assertFalse(exists("signin.subtitle"))
        for (left in listOf("signin.logo", "signin.title", "signin.tagline")) {
            assertTrue("$left is beside the field and the buttons", bounds(left).right <= bounds("signin.email.field").left)
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
    fun largeTextOnThePixel3ScrollsAndCutsNothing() {
        show()
        assertTheScreenScrollsToEach(*PORTRAIT)
        assertDp("the logo", 96.dp, bounds("signin.logo").width)
    }

    @Test
    @Config(qualifiers = "vi-$PIXEL_3", fontScale = 1.3f)
    fun largeVietnameseTextOnThePixel3ScrollsAndCutsNothing() {
        show()
        assertTheScreenScrollsToEach(*PORTRAIT)
    }

    /** Arriving, nothing has the focus: the keyboard stays down and the whole intro shows. */
    @Test
    @Config(qualifiers = PIXEL_3)
    fun theFieldWaitsForATap() {
        show()
        rule.onNodeWithTag("signin.email.field").assertIsNotFocused()
        rule.onNodeWithTag("signin.email.send").assertIsNotEnabled()
        assertDp("the logo", 96.dp, bounds("signin.logo").width)
    }

    /** From 760 dp of height the subtitle has room again, under the taglines. */
    private val tall = PORTRAIT.flatMap { if (it == "signin.tagline") listOf(it, "signin.subtitle") else listOf(it) }.toTypedArray()

    private fun assertTheTallScreenFits() {
        assertWholeOnScreen(*tall)
        assertStacked(*tall)
        assertDp("the logo", 96.dp, bounds("signin.logo").width)
    }

    @Test
    @Config(qualifiers = TALL_PHONE)
    fun aTallPhoneKeepsTheSubtitle() {
        show()
        assertTheTallScreenFits()
    }

    @Test
    @Config(qualifiers = "vi-$TALL_PHONE")
    fun aTallPhoneKeepsTheSubtitleInVietnamese() {
        show()
        assertTheTallScreenFits()
    }

    @Test
    @Config(qualifiers = TALL_PHONE, fontScale = 1.3f)
    fun aTallPhoneWithLargeTextKeepsTheSubtitle() {
        show()
        assertTheScreenScrollsToEach(*tall)
    }

    /** The narrowest phone at the thresholds: its lines wrap the most, and it still needs no scroll. */
    @Test
    @Config(qualifiers = "w360dp-h760dp-xhdpi")
    fun aNarrowPhoneAtTheSubtitlesThresholdFits() {
        show()
        assertTheTallScreenFits()
    }

    @Test
    @Config(qualifiers = "vi-w360dp-h760dp-xhdpi")
    fun aNarrowPhoneAtTheSubtitlesThresholdFitsInVietnamese() {
        show()
        assertTheTallScreenFits()
    }

    @Test
    @Config(qualifiers = "w360dp-h705dp-xhdpi")
    fun aNarrowPhoneAtTheStepsThresholdFits() {
        show()
        assertThePortraitScreenFits()
    }

    @Test
    @Config(qualifiers = "vi-w360dp-h705dp-xhdpi")
    fun aNarrowPhoneAtTheStepsThresholdFitsInVietnamese() {
        show()
        assertThePortraitScreenFits()
    }

    @Test
    @Config(qualifiers = PIXEL_3)
    fun thePixel3LeavesTheSubtitleToTheTaglines() {
        show()
        assertFalse("under 760 dp the taglines stand in for the subtitle", exists("signin.subtitle"))
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
    fun aFailureStandsBetweenTheStepsAndTheField() {
        show(expired = true, error = SignInException.SwitchFromSignedInDevice())
        assertStacked("signin.guide.3", "signin.expired", "signin.error", *CONTROLS)
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
        assertStacked("signin.error", *CONTROLS)
        for (tag in listOf("signin.error", "signin.demo", "signin.logo")) {
            rule.onNodeWithTag(tag).performScrollTo().assertIsDisplayed()
        }
    }

    private fun assertTheShortScreenFits(logo: Dp) {
        val shown = PORTRAIT.filterNot { it.startsWith("signin.guide.") }.toTypedArray()
        assertWholeOnScreen(*shown)
        assertStacked(*shown)
        assertDp("the logo", logo, bounds("signin.logo").width)
        assertFalse("the taglines stand in for the subtitle", exists("signin.subtitle"))
        assertFalse("under 705 dp of height the steps leave their room to the field and the buttons", exists("signin.guide.1"))
    }

    @Test
    @Config(qualifiers = "w360dp-h592dp-xhdpi")
    fun aShortPhoneHasNeitherSubtitleNorSteps() {
        show()
        assertTheShortScreenFits(logo = 96.dp)
    }

    @Test
    @Config(qualifiers = "vi-w360dp-h560dp-xhdpi")
    fun aShortPhoneAtTheBigLogosThresholdFits() {
        show()
        assertTheShortScreenFits(logo = 96.dp)
    }

    @Test
    @Config(qualifiers = "w360dp-h540dp-xhdpi")
    fun aWindowUnder560DpHasTheSmallLogo() {
        show()
        assertTheShortScreenFits(logo = 72.dp)
    }

    @Test
    @Config(qualifiers = "w1280dp-h752dp-land-mdpi")
    fun aTabletInLandscapeKeepsTheStepsBesideTheLogo() {
        show()
        assertWholeOnScreen(*PORTRAIT, "signin.subtitle")
        assertStacked("signin.logo", "signin.title", "signin.tagline", "signin.subtitle")
        assertStacked("signin.guide.1", "signin.guide.2", "signin.guide.3", *CONTROLS)
        assertDp("the logo", 72.dp, bounds("signin.logo").width)
        assertTrue(bounds("signin.title").right <= bounds("signin.guide.1").left)
    }

    /** Two columns at the steps' threshold, on a narrow landscape window where the steps wrap the most. */
    @Test
    @Config(qualifiers = "w700dp-h470dp-land-mdpi")
    fun aLandscapeWindowAtTheStepsThresholdFits() {
        show()
        assertWholeOnScreen("signin.logo", "signin.title", "signin.tagline", "signin.guide.1", "signin.guide.3", *CONTROLS)
        assertStacked("signin.guide.1", "signin.guide.2", "signin.guide.3", *CONTROLS)
    }

    @Test
    @Config(qualifiers = "vi-w700dp-h470dp-land-mdpi")
    fun aLandscapeWindowAtTheStepsThresholdFitsInVietnamese() {
        show()
        assertWholeOnScreen("signin.logo", "signin.title", "signin.tagline", "signin.guide.1", "signin.guide.3", *CONTROLS)
        assertStacked("signin.guide.1", "signin.guide.2", "signin.guide.3", *CONTROLS)
    }

    private companion object {
        /** The Pixel 3's window between its status bar (24 dp) and its three-button bar (48 dp). */
        const val PIXEL_3 = "w393dp-h713dp-440dpi"

        /** The same phone turned: the three-button bar is at the side. */
        const val PIXEL_3_TURNED = "w737dp-h369dp-land-440dpi"

        /** A phone with 852 dp between its bars. */
        const val TALL_PHONE = "w393dp-h852dp-440dpi"

        /** The first screen's field and buttons, from the top. */
        val CONTROLS = arrayOf("signin.email.field", "signin.email.send", "signin.or", "signin.google", "signin.demo")

        /** Everything the Pixel 3's portrait window shows, from the top (the subtitle needs 760 dp of height). */
        val PORTRAIT = arrayOf(
            "signin.logo", "signin.title", "signin.tagline", "signin.guide.1", "signin.guide.2", "signin.guide.3", *CONTROLS,
        )
    }
}
