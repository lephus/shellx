package com.shellx.core.terminal

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TerminalViewportTest {
    private fun v(cols: Int, rows: Int, w: Float = 200f, h: Float = 100f) =
        TerminalViewport(10f, 20f, 4f).resized(w, h).contentChanged(cols, rows, 0, toBottom = true)

    @Test fun aNewSnapshotOrTypingShowsTheBottom() {
        val p = v(10, 50).scrolledBy(0f, -300f).contentChanged(10, 50, 0, toBottom = true)
        assertEquals(908f, p.maxScrollY); assertEquals(908f, p.scrollY); assertTrue(p.followsBottom)  // 8 + 50 × 20 − 100
    }
    @Test fun scrolledUpTheViewKeepsItsRowsWhenHistoryGrowsAbove() {
        val p = v(10, 50).scrolledBy(0f, -300f); assertFalse(p.followsBottom)
        assertEquals(668f, p.contentChanged(10, 53, topShiftDelta = 3, toBottom = false).scrollY)          // 608 + 3 × 20
    }
    @Test fun scrolledUpTheViewKeepsItsRowsWhenRowsDropFromTheTop() {
        assertEquals(568f, v(10, 50).scrolledBy(0f, -300f).contentChanged(10, 50, topShiftDelta = -2, toBottom = false).scrollY)
    }
    @Test fun followingTheBottomStaysThereAsRowsArrive() {
        val p = v(10, 50).contentChanged(10, 51, 0, toBottom = false)
        assertEquals(p.maxScrollY, p.scrollY); assertEquals(928f, p.scrollY)
    }
    @Test fun aWiderGridFitsTheWidthAndANewWidthGoesBackToFit() {
        val wide = v(320, 30); assertEquals(192f / 3200f, wide.scale, 0.0001f)
        val zoomed = wide.pinched(10f, 0f, 0f); assertEquals(0.6f, zoomed.scale, 0.0001f)
        assertEquals(0.6f, zoomed.contentChanged(320, 30, 0, toBottom = false).scale, 0.0001f)
        assertEquals(192f / 1000f, zoomed.contentChanged(100, 30, 0, toBottom = false).scale, 0.0001f)
    }
    @Test fun aPinchKeepsThePointUnderTheFingers() {
        val p = v(40, 400, h = 300f).scrolledBy(0f, -1000f)
        val before = (p.scrollY + 150f - 4f) / p.scale
        val q = p.pinched(1.5f, 100f, 150f)
        assertEquals(before, (q.scrollY + 150f - 4f) / q.scale, 0.01f)
    }
    @Test fun aPinchStaysBetweenFitAndTwo() {
        val p = v(40, 30); assertEquals(p.fit, p.pinched(0.1f, 0f, 0f).scale); assertEquals(2f, p.pinched(100f, 0f, 0f).scale)
    }
    @Test fun visibleRowsCoverTheViewport() {
        val p = v(10, 100); val q = p.scrolledBy(0f, 504f - p.scrollY)
        assertEquals(504f, q.scrollY); assertEquals(25..29, q.visibleRows)
    }
    /** Review B2 m1 (iPhone parity): a scroll that ends within half a row of the bottom follows it. */
    @Test fun aScrollThatEndsWithinHalfARowOfTheBottomFollows() {
        val near = v(10, 50).scrolledBy(0f, -9f)
        assertEquals(899f, near.scrollY); assertTrue(near.followsBottom)
        assertEquals(928f, near.contentChanged(10, 51, 0, toBottom = false).scrollY)
        assertFalse(v(10, 50).scrolledBy(0f, -11f).followsBottom)
    }
    @Test fun aKeyboardThatShrinksThePaneKeepsTheBottom() {
        val p = v(10, 100, h = 300f).resized(200f, 150f)
        assertEquals(p.maxScrollY, p.scrollY); assertTrue(p.followsBottom)
    }
}
