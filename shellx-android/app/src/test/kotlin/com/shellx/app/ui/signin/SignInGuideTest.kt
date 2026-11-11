package com.shellx.app.ui.signin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The three steps come in after the logo settles: 80 ms apart, 250 ms each, rising 8 dp. */
class SignInGuideTest {
    private val start = SignInGuide.START_MS

    @Test
    fun theTimingIsTheSpecifiedOne() {
        assertEquals("after the logo's chevrons are in place", SignInLogo.SLIDE_MS, start)
        assertEquals(80L, SignInGuide.STEP_MS)
        assertEquals(250L, SignInGuide.ROW_MS)
        assertEquals(8, SignInGuide.RISE_DP)
        assertEquals(3, SignInGuide.ROWS)
        assertEquals(start + 2 * 80 + 250, SignInGuide.END_MS)
    }

    @Test
    fun theRowsAreUnseenUntilTheirTurn() {
        for (row in 0 until SignInGuide.ROWS) {
            assertEquals("row $row at first", 0f, SignInGuide.reveal(row, 0), 0f)
            assertEquals("row $row as its turn starts", 0f, SignInGuide.reveal(row, start + row * 80), 0f)
        }
    }

    @Test
    fun eachRowComesIn80MsAfterTheOneBefore() {
        for (row in 0 until SignInGuide.ROWS) {
            val from = start + row * 80
            assertEquals("row $row is in after 250 ms", 1f, SignInGuide.reveal(row, from + 250), 1e-6f)
            assertEquals("and stays", 1f, SignInGuide.reveal(row, from + 60_000), 0f)
            val steps = (from..from + 250 step 5).map { SignInGuide.reveal(row, it) }
            assertTrue("row $row only ever comes in", steps.zipWithNext().all { (a, b) -> b >= a })
            assertTrue("between unseen and in place", steps.all { it in 0f..1f })
            val middle = SignInGuide.reveal(row, from + 125)
            assertTrue("half way in time, part way in ($middle)", middle > 0.2f && middle < 1f)
        }
        val at = start + 120
        assertTrue(
            "the first is ahead of the second, the second of the third",
            SignInGuide.reveal(0, at) > SignInGuide.reveal(1, at) && SignInGuide.reveal(1, at) > SignInGuide.reveal(2, at),
        )
        assertEquals(1f, SignInGuide.reveal(2, SignInGuide.END_MS), 1e-6f)
    }

    @Test
    fun withoutMotionEveryRowIsThereAtOnce() {
        for (row in 0 until SignInGuide.ROWS) assertEquals(1f, SignInGuide.reveal(row, null), 0f)
    }
}
