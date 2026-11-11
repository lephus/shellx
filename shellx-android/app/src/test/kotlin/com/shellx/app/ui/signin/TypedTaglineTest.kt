package com.shellx.app.ui.signin

import androidx.compose.ui.graphics.Color
import com.shellx.app.ui.signin.TypedTagline.Frame
import com.shellx.app.ui.signin.TypedTagline.Phase
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The typed taglines' schedule: 28 ms a letter, held 2.4 s, erased at 12 ms a letter, 300 ms, the next one. */
class TypedTaglineTest {
    /** Three taglines of 3, 2 and 4 letters. */
    private val schedule = TypedTagline.Schedule(listOf(3, 2, 4))
    private val start = TypedTagline.START_MS

    @Test
    fun thePaceIsTheSpecifiedOne() {
        assertEquals(28L, TypedTagline.TYPE_MS)
        assertEquals(2_400L, TypedTagline.HOLD_MS)
        assertEquals(12L, TypedTagline.ERASE_MS)
        assertEquals(300L, TypedTagline.PAUSE_MS)
        assertEquals("typing starts when the logo's chevrons are in place", SignInLogo.SLIDE_MS, start)
    }

    @Test
    fun nothingIsTypedBeforeTheStart() {
        assertEquals(Frame(0, 0, Phase.PAUSING), schedule.at(0))
        assertEquals(Frame(0, 0, Phase.PAUSING), schedule.at(start - 1))
        assertEquals(Frame(0, 0, Phase.PAUSING), schedule.at(-40))
    }

    @Test
    fun aTaglineIsTypedALetterEvery28Ms() {
        assertEquals(Frame(0, 0, Phase.TYPING), schedule.at(start))
        assertEquals(Frame(0, 0, Phase.TYPING), schedule.at(start + 27))
        assertEquals(Frame(0, 1, Phase.TYPING), schedule.at(start + 28))
        assertEquals(Frame(0, 2, Phase.TYPING), schedule.at(start + 56))
        assertEquals(Frame(0, 2, Phase.TYPING), schedule.at(start + 83))
    }

    @Test
    fun aTypedTaglineIsHeldFor2400Ms() {
        val typed = start + 3 * 28
        assertEquals(Frame(0, 3, Phase.HOLDING), schedule.at(typed))
        assertEquals(Frame(0, 3, Phase.HOLDING), schedule.at(typed + 2_399))
    }

    @Test
    fun itIsErasedALetterEvery12MsAndTheNextFollowsAfter300Ms() {
        val erasing = start + 3 * 28 + 2_400
        assertEquals(Frame(0, 3, Phase.ERASING), schedule.at(erasing))
        assertEquals(Frame(0, 3, Phase.ERASING), schedule.at(erasing + 11))
        assertEquals(Frame(0, 2, Phase.ERASING), schedule.at(erasing + 12))
        assertEquals(Frame(0, 1, Phase.ERASING), schedule.at(erasing + 24))
        assertEquals(Frame(0, 1, Phase.ERASING), schedule.at(erasing + 35))
        val pause = erasing + 3 * 12
        assertEquals(Frame(0, 0, Phase.PAUSING), schedule.at(pause))
        assertEquals(Frame(0, 0, Phase.PAUSING), schedule.at(pause + 299))
        assertEquals(Frame(1, 0, Phase.TYPING), schedule.at(pause + 300))
        assertEquals(Frame(1, 1, Phase.TYPING), schedule.at(pause + 300 + 28))
    }

    @Test
    fun theTaglinesCycleForever() {
        fun round(letters: Int): Long = letters * 28L + 2_400 + letters * 12L + 300
        assertEquals(round(3) + round(2) + round(4), schedule.cycleMs)
        val third = start + round(3) + round(2)
        assertEquals(Frame(2, 0, Phase.TYPING), schedule.at(third))
        assertEquals(Frame(2, 4, Phase.HOLDING), schedule.at(third + 4 * 28))
        assertEquals("after the last, the first again", Frame(0, 0, Phase.TYPING), schedule.at(start + schedule.cycleMs))
        for (ms in start..start + schedule.cycleMs step 7) {
            assertEquals("at $ms, a thousand rounds later", schedule.at(ms), schedule.at(ms + 1_000 * schedule.cycleMs))
        }
    }

    @Test
    fun everyLetterOfEveryTaglineShowsInTurn() {
        val seen = (0..start + schedule.cycleMs).map { schedule.at(it) }.distinct()
        for ((line, letters) in listOf(3, 2, 4).withIndex()) {
            for (shown in 0..letters) {
                assertTrue("tagline $line with $shown letters", seen.any { it.line == line && it.shown == shown })
            }
        }
        assertTrue(seen.all { it.line in 0..2 && it.shown >= 0 })
    }

    @Test
    fun withoutMotionTheFirstTaglineIsThereAtOnce() {
        assertEquals(Frame(0, 3, Phase.HOLDING), schedule.still)
    }

    @Test
    fun oneTaglineAloneStillCycles() {
        val one = TypedTagline.Schedule(listOf(2))
        assertEquals(Frame(0, 2, Phase.HOLDING), one.at(start + 56))
        assertEquals(Frame(0, 0, Phase.TYPING), one.at(start + one.cycleMs))
    }

    @Test
    fun theCursorIsSteadyWhileLettersChangeAndBlinksWithTheLogosAtRest() {
        val lit = SignInLogo.INTRO_MS
        val dark = SignInLogo.INTRO_MS + SignInLogo.BLINK_ON_MS
        for (phase in listOf(Phase.TYPING, Phase.ERASING)) {
            assertTrue("$phase", TypedTagline.cursorOn(phase, lit))
            assertTrue("$phase", TypedTagline.cursorOn(phase, dark))
        }
        for (phase in listOf(Phase.HOLDING, Phase.PAUSING)) {
            assertTrue("$phase", TypedTagline.cursorOn(phase, lit))
            assertFalse("$phase", TypedTagline.cursorOn(phase, dark))
        }
    }

    @Test
    fun aLetterAndItsAccentsAreTypedAsOne() {
        assertArrayEquals(intArrayOf(1, 2, 3), TypedTagline.letters("abc"))
        assertArrayEquals("no letters", IntArray(0), TypedTagline.letters(""))
        // "ề" as e + circumflex + grave, then "u": two letters.
        assertArrayEquals(intArrayOf(3, 4), TypedTagline.letters("ều"))
        val tagline = "Điều khiển Mac từ túi của bạn."
        assertEquals("precomposed Vietnamese: a letter per character", tagline.length, TypedTagline.letters(tagline).size)
        assertEquals(tagline.length, TypedTagline.letters(tagline).last())
    }

    @Test
    fun theUntypedRestKeepsItsPlaceUnseen() {
        val half = TypedTagline.styled("Hello", shown = 2)
        assertEquals("the whole line is laid out, and read out", "Hello", half.text)
        assertEquals(1, half.spanStyles.size)
        assertEquals(2, half.spanStyles[0].start)
        assertEquals(5, half.spanStyles[0].end)
        assertEquals(Color.Transparent, half.spanStyles[0].item.color)

        assertEquals("nothing typed", 0, TypedTagline.styled("Hello", shown = 0).spanStyles.single().start)
        val whole = TypedTagline.styled("Hello", shown = 5)
        assertEquals("Hello", whole.text)
        assertTrue("all typed: nothing hidden", whole.spanStyles.isEmpty())
    }
}
