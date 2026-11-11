package com.shellx.app.ui.signin

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The animated logo's geometry and timeline: the launcher's mark, a 900 ms intro, a blinking underscore, a glow. */
class SignInLogoTest {
    private val slide = SignInLogo.SLIDE_MS
    private val intro = SignInLogo.INTRO_MS

    @Test
    fun theMarkIsTheLaunchersOne() {
        // res/drawable/shellx_logo.xml and ic_launcher_foreground.xml (design/shellx-logo.svg).
        assertEquals(512f, SignInLogo.VIEWPORT)
        assertEquals(114f, SignInLogo.CORNER)
        assertEquals(listOf(0xFF1C1438, 0xFF0B0716), SignInLogo.SQUARE)
        assertEquals(listOf(Offset(128f, 122f), Offset(222f, 234f), Offset(128f, 346f)), SignInLogo.PROMPT)
        assertEquals(listOf(0xFF7DF7BE, 0xFF2FD98A), SignInLogo.MINT)
        assertEquals(listOf(Offset(384f, 122f), Offset(290f, 234f), Offset(384f, 346f)), SignInLogo.PHONE)
        assertEquals(listOf(0xFFFFFFFF, 0xFFCFC8EE), SignInLogo.LILAC)
        assertEquals(54f, SignInLogo.STROKE)
        assertEquals(Rect(300f, 398f, 384f, 424f), SignInLogo.UNDERSCORE)
        assertEquals(8f, SignInLogo.UNDERSCORE_CORNER)
    }

    @Test
    fun theLogoIs96DpAnd72WhereTheWindowIsShort() {
        assertEquals(96, SignInLogo.SIZE_DP)
        assertEquals(72, SignInLogo.COMPACT_SIZE_DP)
    }

    @Test
    fun theIntroTakesAbout900Ms() {
        assertEquals(900L, intro)
        assertTrue("the chevrons settle before the underscore comes", slide in 500L until intro)
    }

    @Test
    fun theChevronsStartOutsideTheSquare() {
        val half = SignInLogo.STROKE / 2
        val promptRight = SignInLogo.PROMPT.maxOf { it.x } + half
        val phoneLeft = SignInLogo.PHONE.minOf { it.x } - half
        assertTrue("the prompt starts left of the square", promptRight - SignInLogo.TRAVEL <= 0f)
        assertTrue("the phone's chevron starts right of it", phoneLeft + SignInLogo.TRAVEL >= SignInLogo.VIEWPORT)
        assertEquals(0f, SignInLogo.slide(0), 0f)
    }

    @Test
    fun theChevronsSlideInAndStay() {
        assertEquals(1f, SignInLogo.slide(slide), 1e-6f)
        assertEquals(1f, SignInLogo.slide(intro), 0f)
        assertEquals(1f, SignInLogo.slide(3_600_000), 0f)
        assertEquals("before the screen's first frame", 0f, SignInLogo.slide(-5), 0f)
        assertTrue("most of the way in a third of the time", SignInLogo.slide(slide / 3) > 0.8f)
    }

    @Test
    fun theSettleEasesOutAndOvershootsByAtMostFourPercent() {
        assertEquals(0f, SignInLogo.settle(0f), 1e-6f)
        assertEquals(1f, SignInLogo.settle(1f), 1e-6f)
        val steps = (0..1000).map { SignInLogo.settle(it / 1000f) }
        val peak = steps.max()
        assertTrue("a slight overshoot ($peak)", peak > 1.005f)
        assertTrue("at most 4 % ($peak)", peak <= 1f + SignInLogo.MAX_OVERSHOOT)
        assertEquals(0.04f, SignInLogo.MAX_OVERSHOOT)
        assertTrue("never behind the start", steps.min() >= 0f)
        val top = steps.indexOf(peak)
        assertTrue("rises to the peak", (1..top).all { steps[it] >= steps[it - 1] })
        assertTrue("then settles back", (top + 1..1000).all { steps[it] <= steps[it - 1] })
        assertTrue("ease-out: faster at the start than at the end", steps[100] - steps[0] > steps[1000] - steps[900])
    }

    @Test
    fun theChevronsNeverTouchAtTheOvershoot() {
        val half = SignInLogo.STROKE / 2
        val gapAtRest = (SignInLogo.PHONE.minOf { it.x } - half) - (SignInLogo.PROMPT.maxOf { it.x } + half)
        val peak = (0..1000).maxOf { SignInLogo.settle(it / 1000f) }
        assertTrue("the tips keep apart", gapAtRest - 2 * (peak - 1f) * SignInLogo.TRAVEL > 0f)
    }

    @Test
    fun theUnderscoreComesAfterTheChevronsThenBlinksLikeACursor() {
        assertEquals(0f, SignInLogo.underscore(0), 0f)
        assertEquals(0f, SignInLogo.underscore(slide), 0f)
        val half = SignInLogo.underscore((slide + intro) / 2)
        assertTrue("fading in ($half)", half > 0.3f && half < 0.7f)
        assertEquals(530L, SignInLogo.BLINK_ON_MS)
        assertEquals(530L, SignInLogo.BLINK_OFF_MS)
        assertEquals("lit", 1f, SignInLogo.underscore(intro), 0f)
        assertEquals(1f, SignInLogo.underscore(intro + 529), 0f)
        assertEquals("dark", 0f, SignInLogo.underscore(intro + 530), 0f)
        assertEquals(0f, SignInLogo.underscore(intro + 1059), 0f)
        assertEquals("lit again", 1f, SignInLogo.underscore(intro + 1060), 0f)
        assertEquals("forever", 0f, SignInLogo.underscore(intro + 1060 * 3_000 + 600), 0f)
    }

    @Test
    fun aCursorInStepWithTheUnderscoreIsLitUntilTheIntroEnds() {
        assertTrue(SignInLogo.cursorOn(0))
        assertTrue(SignInLogo.cursorOn(intro - 1))
        assertTrue(SignInLogo.cursorOn(intro + 529))
        assertFalse(SignInLogo.cursorOn(intro + 530))
        assertTrue(SignInLogo.cursorOn(intro + 1060))
    }

    @Test
    fun theGlowBreathesBetween25And45PercentEveryFourSecondsAfterTheIntro() {
        assertEquals(0.25f, SignInLogo.GLOW_MIN)
        assertEquals(0.45f, SignInLogo.GLOW_MAX)
        assertEquals(4_000L, SignInLogo.GLOW_PERIOD_MS)
        assertEquals("none during the intro", 0f, SignInLogo.glow(0), 0f)
        assertEquals(0f, SignInLogo.glow(slide), 0f)
        assertEquals("it comes up from nothing", 0f, SignInLogo.glow(intro), 1e-6f)
        val rising = SignInLogo.glow(intro + SignInLogo.GLOW_FADE_IN_MS / 2)
        assertTrue("coming up ($rising)", rising > 0.05f && rising < 0.25f)
        assertEquals("brightest half way", 0.45f, SignInLogo.glow(intro + 2_000), 1e-4f)
        assertEquals("back at the lowest", 0.25f, SignInLogo.glow(intro + 4_000), 1e-4f)
        assertEquals(0.45f, SignInLogo.glow(intro + 6_000), 1e-4f)
        assertEquals(0.25f, SignInLogo.glow(intro + 8_000), 1e-4f)
        val from = intro + SignInLogo.GLOW_FADE_IN_MS
        for (ms in from..from + 12_000 step 37) {
            val glow = SignInLogo.glow(ms)
            assertTrue("$glow at $ms", glow >= 0.25f - 1e-4f && glow <= 0.45f + 1e-4f)
            assertEquals("the same one loop later", glow, SignInLogo.glow(ms + 4_000), 1e-4f)
        }
        val steps = (intro..intro + 2_000 step 20).map { SignInLogo.glow(it) }
        assertTrue("no jump on the way up", steps.zipWithNext().all { (a, b) -> b >= a && b - a < 0.02f })
    }

    @Test
    fun aPoseIsTheThreeAtOneMoment() {
        assertEquals(SignInLogo.Pose(slide = 0f, underscore = 0f, glow = 0f), SignInLogo.pose(0))
        for (ms in listOf(100L, slide, intro, intro + 700, intro + 2_000, 60_000L)) {
            val expected = SignInLogo.Pose(SignInLogo.slide(ms), SignInLogo.underscore(ms), SignInLogo.glow(ms))
            assertEquals("at $ms", expected, SignInLogo.pose(ms))
        }
    }

    @Test
    fun withoutMotionTheLogoRestsAsTheLauncherShowsIt() {
        assertEquals(SignInLogo.Pose(slide = 1f, underscore = 1f, glow = 0f), SignInLogo.REST)
    }
}
