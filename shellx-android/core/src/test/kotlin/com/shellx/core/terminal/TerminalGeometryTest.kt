package com.shellx.core.terminal

import kotlin.test.Test
import kotlin.test.assertEquals

class TerminalGeometryTest {
    @Test fun phoneGridFitsTheViewport() {
        assertEquals(TerminalGridSize(50, 42), TerminalGeometry.phoneGrid(375f, 646f, 7.2f, 15f, 4f))
        assertEquals(TerminalGridSize(1, 1), TerminalGeometry.phoneGrid(0f, 0f, 7.2f, 15f, 4f))
    }

    @Test fun fitScaleShrinksAWiderGridAndNeverEnlarges() {
        assertEquals(367f / 864f, TerminalGeometry.fitScale(120, 7.2f, 375f, 4f), 0.0001f)
        assertEquals(1f, TerminalGeometry.fitScale(40, 7.2f, 375f, 4f))
        // A Mac-sized grid beyond the phone's 300-column limit (contracts §17).
        assertEquals(367f / 2304f, TerminalGeometry.fitScale(320, 7.2f, 375f, 4f), 0.0001f)
    }

    @Test fun scrollLinesKeepTheRest() {
        val first = TerminalGeometry.scrollLines(47f, 0f, 15f, 1f)
        assertEquals(3, first.lines); assertEquals(2f, first.carry, 0.001f)
        val up = TerminalGeometry.scrollLines(-20f, first.carry, 15f, 1f)
        assertEquals(-1, up.lines); assertEquals(-3f, up.carry, 0.001f)
        assertEquals(4, TerminalGeometry.scrollLines(30f, 0f, 15f, 0.5f).lines)
    }
}
