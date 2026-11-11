package com.shellx.app.ui.signin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** What the sign-in screen shows for a window's size, and its intro's clock. */
class SignInLayoutTest {
    @Test
    fun aPhoneInPortraitHasTheBigLogoTheSubtitleAndTheSteps() {
        // The Pixel 3 is 393 × 785 dp; about 713 dp are left between its status and navigation bars.
        for (height in listOf(713f, 737f, 785f, 852f)) {
            assertEquals(
                "393 × $height",
                SignInLayout(logoDp = 96, subtitle = true, guide = true, sideBySide = false),
                SignInLayout.of(393f, height),
            )
        }
    }

    @Test
    fun aShorterPhoneLeavesTheSubtitleToTheTaglines() {
        assertEquals(SignInLayout(logoDp = 96, subtitle = false, guide = true, sideBySide = false), SignInLayout.of(360f, 640f))
        assertTrue(SignInLayout.of(393f, 700f).subtitle)
        assertFalse(SignInLayout.of(393f, 699.5f).subtitle)
    }

    @Test
    fun aWindowUnder600DpTallHasTheSmallLogo() {
        assertEquals(SignInLayout(logoDp = 72, subtitle = false, guide = true, sideBySide = false), SignInLayout.of(360f, 592f))
        assertEquals(96, SignInLayout.of(360f, 600f).logoDp)
        assertEquals(72, SignInLayout.of(360f, 599.5f).logoDp)
    }

    @Test
    fun aPhoneInLandscapeHasTheSmallLogoBesideTheButtonsAndNoSteps() {
        // The Pixel 3 turned: 785 × 393 dp, less its bars.
        for ((width, height) in listOf(737f to 369f, 785f to 393f, 851f to 393f)) {
            assertEquals(
                "$width × $height",
                SignInLayout(logoDp = 72, subtitle = false, guide = false, sideBySide = true),
                SignInLayout.of(width, height),
            )
        }
        assertTrue(SignInLayout.of(900f, 400f).guide)
        assertFalse(SignInLayout.of(900f, 399.5f).guide)
    }

    @Test
    fun aTabletInLandscapeKeepsTheStepsBesideTheLogo() {
        assertEquals(SignInLayout(logoDp = 72, subtitle = true, guide = true, sideBySide = true), SignInLayout.of(1280f, 752f))
        assertEquals(SignInLayout(logoDp = 72, subtitle = false, guide = true, sideBySide = true), SignInLayout.of(960f, 540f))
    }

    @Test
    fun aTabletInPortraitIsAPhoneWithMoreRoom() {
        assertEquals(SignInLayout(logoDp = 96, subtitle = true, guide = true, sideBySide = false), SignInLayout.of(800f, 1232f))
        assertEquals("a square window is not landscape", 96, SignInLayout.of(700f, 700f).logoDp)
        assertFalse(SignInLayout.of(700f, 700f).sideBySide)
    }

    @Test
    fun aNarrowLandscapeWindowKeepsOneColumn() {
        // A phone's split screen: wider than tall, with no room for two columns.
        assertEquals(SignInLayout(logoDp = 72, subtitle = false, guide = false, sideBySide = false), SignInLayout.of(393f, 350f))
        assertTrue(SignInLayout.of(600f, 380f).sideBySide)
        assertFalse(SignInLayout.of(599.5f, 380f).sideBySide)
    }

    @Test
    fun theIntroMovesOnlyWhileTheSystemsAnimationsAreOn() {
        assertTrue(SignInIntro.animates(animatorsEnabled = true))
        assertFalse("Remove animations, a render, a UI test", SignInIntro.animates(animatorsEnabled = false))
    }

    @Test
    fun theIntroHasSettledOnceTheLogoAndTheStepsAreIn() {
        assertEquals(maxOf(SignInLogo.INTRO_MS, SignInGuide.END_MS), SignInIntro.SETTLED_MS)
        assertTrue(SignInIntro.SETTLED_MS >= 900L)
    }

    @Test
    fun afterTheIntroTheClockMovesAtMost30TimesASecond() {
        assertEquals(33L, SignInIntro.FRAME_MS)
        assertEquals(1_056L, SignInIntro.tick(1_056))
        assertEquals(1_056L, SignInIntro.tick(1_060))
        assertEquals(1_056L, SignInIntro.tick(1_088))
        assertEquals(1_089L, SignInIntro.tick(1_089))
        val readingsInASecond = (0L until 1_000L).map { SignInIntro.tick(60_000 + it) }.distinct().size
        assertTrue("$readingsInASecond readings in a second", readingsInASecond in 30..31)
    }
}
