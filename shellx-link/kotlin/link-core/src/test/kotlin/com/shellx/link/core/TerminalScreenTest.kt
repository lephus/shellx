package com.shellx.link.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

/** The ports of 2A's `TerminalScreenTests`, then two Kotlin tests. */
class TerminalScreenTest {
    private val palette = TerminalPalette("#d0d0d0", "#101010", colors = (0 until 256).map { "#%02x%02x%02x".format(it, it, it) })

    /** As 2A's `snapshotFrame`: cursor (0, 0), [history] at y -history.size … -1. */
    private fun snapshot(cols: Int, rows: Int, text: List<String>, history: List<String> = emptyList()): TerminalGridFrame {
        val lines = history.mapIndexedNotNull { i, row -> row.takeIf { it.isNotEmpty() }?.let { TerminalLine(i - history.size, listOf(TerminalRun(text = it))) } } +
            text.mapIndexedNotNull { i, row -> row.takeIf { it.isNotEmpty() }?.let { TerminalLine(i, listOf(TerminalRun(text = it))) } }
        val head = TerminalFrameHead(
            TerminalFrameKind.SNAPSHOT, cols, rows, cursor = TerminalCursor(0, 0), palette = palette, history = history.size,
        )
        return TerminalGridFrame(head, lines = lines)
    }

    /** As 2A's `deltaFrame` without history rows: replaces the rows of [replacing]. */
    private fun delta(cols: Int, rows: Int, replacing: Map<Int, String>, scroll: Int = 0): TerminalGridFrame {
        val lines = replacing.keys.sorted().map { y ->
            val row = replacing.getValue(y)
            TerminalLine(y, if (row.isEmpty()) emptyList() else listOf(TerminalRun(text = row)))
        }
        val head = TerminalFrameHead(TerminalFrameKind.DELTA, cols, rows, cursor = TerminalCursor(0, 0), scroll = scroll)
        return TerminalGridFrame(head, lines = lines)
    }

    @Test
    fun rowTextSkipsTheSecondColumnOfAWideCell() {
        val row = TerminalRow(listOf(TerminalStyledRun(0, "a"), TerminalStyledRun(1, "中", width = 2)))
        assertEquals("a中", row.text(5))
        val d = TerminalCellStyle.DEFAULT
        assertEquals(
            listOf(TerminalCell.Glyph("a", 1, d), TerminalCell.Glyph("中", 2, d), TerminalCell.Continuation, TerminalCell.Blank, TerminalCell.Blank),
            row.cells(5),
        )
    }

    @Test
    fun laterRunOverwritesCellByCell() {
        assertEquals("aZc", TerminalRow(listOf(TerminalStyledRun(0, "abc"), TerminalStyledRun(1, "Z"))).text(3))
    }

    @Test
    fun screenStartsEmpty() {
        val s = TerminalScreen()
        assertEquals(0, s.cols)
        assertNull(s.cursor)
        assertEquals(emptyList(), s.screenText())
        assertEquals(emptyList(), s.historyText())
    }

    @Test
    fun overwritingHalfAWideCellLeavesNoHalfGlyph() {
        val row = TerminalRow(listOf(TerminalStyledRun(0, "中", width = 2), TerminalStyledRun(1, "x")))
        assertEquals(listOf(TerminalCell.Blank, TerminalCell.Glyph("x", 1, TerminalCellStyle.DEFAULT), TerminalCell.Blank), row.cells(3))
    }

    @Test
    fun historyKeepsAtMostMaxRowsDroppingTheOldest() {
        val s = TerminalScreen(maxHistoryRows = 3)
        s.apply(snapshot(10, 1, listOf("x"), history = listOf("h1", "h2", "h3", "h4", "h5")))
        assertEquals(listOf("h3", "h4", "h5"), s.historyText())
    }

    @Test
    fun aRowThatScrollsIntoHistoryIsTheSameObject() {
        val s = TerminalScreen()
        s.apply(snapshot(10, 2, listOf("a", "b")))
        val top = s.screenRows[0]
        val bottom = s.screenRows[1]
        s.apply(delta(10, 2, replacing = mapOf(1 to "c"), scroll = 1))
        assertSame(top, s.historyRows.last())
        assertSame(bottom, s.screenRows[0])
    }

    /**
     * Android only (final review m6): history is capped by its estimated size too, so output with a colour per character
     * cannot fill a budget phone's heap within the 10 000 rows. The oldest rows go first; the row cap still holds.
     */
    @Test
    fun historyIsCappedBySizeToo() {
        val screen = TerminalScreen(maxHistoryRows = 10_000, maxHistoryBytes = 200_000)
        screen.apply(snapshot(100, 2, listOf("", "")))
        val rainbow = (0 until 100).map { TerminalRun(x = it, text = "a") }
        repeat(1_000) {
            val head = TerminalFrameHead(TerminalFrameKind.DELTA, 100, 2, cursor = TerminalCursor(0, 0), scroll = 1)
            screen.apply(TerminalGridFrame(head, lines = listOf(TerminalLine(1, rainbow))))
        }
        assertTrue(screen.historyBytes <= 200_000, "${screen.historyBytes}")
        assertTrue(screen.historyRows.size in 10 until 999, "${screen.historyRows.size}")
        assertEquals("a".repeat(100), screen.historyText().last())
        assertEquals(TerminalScreen.DEFAULT_MAX_HISTORY_BYTES, TerminalScreen().maxHistoryBytes)
        val rowsCapped = TerminalScreen(maxHistoryRows = 5)
        rowsCapped.apply(snapshot(10, 2, listOf("", "")))
        repeat(20) { rowsCapped.apply(delta(10, 2, mapOf(1 to "r$it"), scroll = 1)) }
        assertEquals(5, rowsCapped.historyRows.size)
    }
}

