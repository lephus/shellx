package com.shellx.app.ui.terminal

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.demo.DemoTerminalScreens
import com.shellx.link.core.TerminalCellStyle
import com.shellx.link.core.TerminalRow
import com.shellx.link.core.TerminalStyledRun
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

/** Cells of 10 × 20 px, baseline 15; a glyph is 10 px per code point unless [advances] says otherwise. */
internal class FakeMetrics(private val advances: Map<String, Float> = emptyMap()) : TerminalGlyphMetrics {
    override val cellWidth: Float = 10f
    override val cellHeight: Float = 20f
    override val baseline: Float = 15f
    override val underlineOffset: Float = 2f
    override val lineThickness: Float = 1f

    override fun advance(text: String, bold: Boolean, italic: Boolean): Float =
        advances[text] ?: (10f * text.codePointCount(0, text.length))
}

/**
 * A terminal row cut into segments of one style, each cell at its column, wide and combined cells drawn on their own
 * (`TerminalRowLayoutTests.swift`), and the draw calls a row makes (plan 3G Review Focus 5).
 */
@RunWith(AndroidJUnit4::class)
class TerminalRowLayoutTest {
    @Test
    fun cellsOfOneStyleFormOneSegment() {
        val cells = TerminalRow(
            listOf(TerminalStyledRun(0, "ab", style = TerminalCellStyle(fg = 1)), TerminalStyledRun(2, "c")),
        ).cells(5)
        val segments = TerminalRowLayout.segments(cells, DemoTerminalScreens.PALETTE)
        assertEquals(listOf(0..1, 2..4), segments.map { it.columns })
        assertEquals(listOf("a", "b"), segments[0].narrow.map { it.text })
    }

    @Test
    fun wideAndClusterCellsAreDrawnOnTheirOwn() {
        val cells = TerminalRow(
            listOf(TerminalStyledRun(0, "a"), TerminalStyledRun(1, "中", width = 2), TerminalStyledRun(3, "é", width = 1)),
        ).cells(5)
        val segments = TerminalRowLayout.segments(cells, DemoTerminalScreens.PALETTE)
        assertEquals(1, segments.size)
        assertEquals(
            listOf(TerminalRowLayout.Cell(1, 2, "中"), TerminalRowLayout.Cell(3, 1, "é")),
            segments[0].clusters,
        )
        assertEquals(listOf(0, 4), segments[0].narrow.map { it.column })
    }

    @Test
    fun theCellUnderTheCursorIsFound() {
        val row = TerminalRow(listOf(TerminalStyledRun(0, "a"), TerminalStyledRun(1, "中", width = 2)))
        val layout = TerminalRowLayout(row, 5, DemoTerminalScreens.PALETTE, FakeMetrics())
        assertEquals(TerminalRowLayout.Cell(1, 2, "中"), layout.cell(2)?.first)
        assertEquals("a", layout.cell(0)?.first?.text)
        assertNull(layout.cell(4))
    }

    @Test
    fun aRunOfUniformGlyphsIsOneDrawCall() {
        val layout = TerminalRowLayout(TerminalRow(listOf(TerminalStyledRun(0, "hello"))), 5, DemoTerminalScreens.PALETTE, FakeMetrics())
        assertEquals(listOf("hello"), layout.ops.map { it.text })
        assertEquals(0f, layout.ops[0].x)
    }

    @Test
    fun aGlyphThatIsNotOneCellWideStaysInItsCell() { // Review Focus 5
        val metrics = FakeMetrics(advances = mapOf("ắ" to 15f, "x" to 6f))
        val layout = TerminalRowLayout(TerminalRow(listOf(TerminalStyledRun(0, "aắbxc"))), 5, DemoTerminalScreens.PALETTE, metrics)
        assertEquals(listOf("a", "ắ", "b", "x", "c"), layout.ops.map { it.text })
        assertEquals(listOf(0f, 10f, 20f, 32f, 40f), layout.ops.map { it.x }) // x is centred: 30 + (10 − 6) / 2
        assertEquals(10f / 15f, layout.ops[1].scaleX, 0.0001f)
        assertEquals(1f, layout.ops[3].scaleX)
    }

    /** Where each glyph of [layout]'s ops starts, by its code point index along the row's text ops. */
    private fun glyphStarts(layout: TerminalRowLayout, metrics: TerminalGlyphMetrics): List<Pair<String, Float>> =
        layout.ops.flatMap { op ->
            var x = op.x
            op.text.map { char ->
                val start = char.toString() to x
                x += metrics.advance(char.toString(), op.bold, op.italic) * op.scaleX
                start
            }
        }

    /**
     * Glyphs a little off the cell's width (a fallback face, 0.4 px here) still join runs, but never far enough to leave
     * their columns: every glyph starts within 0.5 px of its column, the 80th of a row at 79 cells, and "x" after twenty
     * of them at 200 (reviews D1 M9, final m1; the iPhone moves every glyph to its column).
     */
    @Test
    fun aRunOfGlyphsSlightlyOffTheCellWidthStaysOnTheGrid() {
        val metrics = FakeMetrics(advances = mapOf("─" to 10.4f))
        val row = TerminalRowLayout(TerminalRow(listOf(TerminalStyledRun(0, "─".repeat(80)))), 80, DemoTerminalScreens.PALETTE, metrics)
        val starts = glyphStarts(row, metrics)
        assertEquals(80, starts.size)
        starts.forEachIndexed { column, (_, x) -> assertEquals("column $column", column * 10f, x, 0.5f) }
        val mixed = TerminalRowLayout(TerminalRow(listOf(TerminalStyledRun(0, "─".repeat(20) + "x"))), 21, DemoTerminalScreens.PALETTE, metrics)
        val placed = glyphStarts(mixed, metrics)
        placed.forEachIndexed { column, (_, x) -> assertEquals("column $column", column * 10f, x, 0.5f) }
        assertEquals("x", placed.last().first)
        assertEquals(200f, placed.last().second, 0.5f)
    }

    @Test
    fun aClusterWiderThanItsCellsIsSqueezedIntoThem() {
        val metrics = FakeMetrics(advances = mapOf("👨‍👩‍👧" to 30f, "中" to 18f))
        val row = TerminalRow(
            listOf(TerminalStyledRun(0, "👨‍👩‍👧", width = 2), TerminalStyledRun(2, "中", width = 2), TerminalStyledRun(4, "z")),
        )
        val layout = TerminalRowLayout(row, 5, DemoTerminalScreens.PALETTE, metrics)
        assertEquals(listOf(0f, 21f, 40f), layout.ops.map { it.x }) // 20 + (20 − 18) / 2
        assertEquals(20f / 30f, layout.ops[0].scaleX, 0.0001f)
        assertEquals("z", layout.ops[2].text)
    }
}
