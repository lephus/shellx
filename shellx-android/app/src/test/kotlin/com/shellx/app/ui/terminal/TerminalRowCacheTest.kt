package com.shellx.app.ui.terminal

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.demo.DemoTerminalScreens
import com.shellx.link.core.TerminalCursor
import com.shellx.link.core.TerminalFrameHead
import com.shellx.link.core.TerminalFrameKind
import com.shellx.link.core.TerminalGridFrame
import com.shellx.link.core.TerminalLine
import com.shellx.link.core.TerminalPalette
import com.shellx.link.core.TerminalRun
import com.shellx.link.core.TerminalScreen
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/** Row layouts are kept by row object: an echo or a scroll lays out only the rows that changed (plan 3G, "Renderer"). */
@RunWith(AndroidJUnit4::class)
class TerminalRowCacheTest {
    /** A snapshot of 20 × 5 whose rows read r0 … r4. */
    private fun fiveRows() = TerminalGridFrame(
        TerminalFrameHead(TerminalFrameKind.SNAPSHOT, 20, 5, cursor = TerminalCursor(0, 0), palette = DemoTerminalScreens.PALETTE),
        lines = (0 until 5).map { TerminalLine(it, listOf(TerminalRun(text = "r$it"))) },
    )

    /** A delta of 20 × 5 with cursor (0, 0) and [line]. */
    private fun delta(line: TerminalLine, scroll: Int) = TerminalGridFrame(
        TerminalFrameHead(TerminalFrameKind.DELTA, 20, 5, cursor = TerminalCursor(0, 0), scroll = scroll),
        lines = listOf(line),
    )

    private fun TerminalScreen.layOut(cache: TerminalRowCache, palette: TerminalPalette = this.palette!!) =
        (historyRows + screenRows).forEach { cache.layout(it, cols, palette) }

    @Test
    fun aDeltaRebuildsOnlyTheRowsItReplaced() {
        val s = TerminalScreen().apply { apply(fiveRows()) }
        val cache = TerminalRowCache(FakeMetrics())
        s.layOut(cache)
        assertEquals(5, cache.builds)
        s.apply(delta(TerminalLine(2, listOf(TerminalRun(text = "ls"))), scroll = 0))
        s.layOut(cache)
        assertEquals(6, cache.builds)
    }

    @Test
    fun rowsThatScrollIntoHistoryKeepTheirLayout() {
        val s = TerminalScreen().apply { apply(fiveRows()) }
        val cache = TerminalRowCache(FakeMetrics())
        s.layOut(cache)
        s.apply(delta(TerminalLine(4, listOf(TerminalRun(text = "r5"))), scroll = 1))
        s.layOut(cache)
        assertEquals(listOf("r0"), s.historyText())
        assertEquals(6, cache.builds)
    }

    @Test
    fun aNewPaletteRebuildsEveryRow() {
        val s = TerminalScreen().apply { apply(fiveRows()) }
        val cache = TerminalRowCache(FakeMetrics())
        s.layOut(cache)
        s.layOut(cache, s.palette!!.copy(bg = "#000000"))
        assertEquals(10, cache.builds)
    }
}
