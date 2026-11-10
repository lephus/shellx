package com.shellx.app.ui.terminal

import android.graphics.Canvas
import android.graphics.Paint
import com.shellx.core.terminal.TerminalColors
import com.shellx.core.terminal.TerminalResolvedStyle
import com.shellx.core.terminal.TerminalRgb
import com.shellx.link.core.TerminalCell
import com.shellx.link.core.TerminalCellStyle
import com.shellx.link.core.TerminalPalette
import com.shellx.link.core.TerminalRow
import kotlin.math.abs

/**
 * One row, laid out once from its cells and drawn from that until the row changes (`TerminalRowLayout.swift`).
 *
 * Every cell is placed by its column, never by the font's advance, so a glyph the monospace face lacks (a fallback
 * font's CJK, emoji or Vietnamese letter of another width) cannot push the cells after it sideways (Review Focus 5).
 * Narrow cells whose advance is the cell's width are drawn as one run; any other glyph is drawn alone, centred in its
 * cells when narrower, squeezed into them when wider. Lengths are grid px (the font's px at scale 1). Main thread only.
 */
class TerminalRowLayout(row: TerminalRow, cols: Int, palette: TerminalPalette, private val metrics: TerminalGlyphMetrics) {
    data class Cell(val column: Int, val width: Int, val text: String)

    /** Consecutive cells of one resolved style (a blank counts as a space in the default style). */
    data class Segment(
        val columns: IntRange,
        val style: TerminalResolvedStyle,
        /** Cells of width 1 and one code point, each at its column. */
        val narrow: List<Cell>,
        /** Cells of width 2, or of more than one code point: each drawn alone, centred in its columns. */
        val clusters: List<Cell>,
    )

    /** One drawText: [text] with its left at [x] (grid px), squeezed horizontally by [scaleX] (1 = as is). */
    data class TextOp(val text: String, val x: Float, val scaleX: Float, val color: Int, val bold: Boolean, val italic: Boolean)

    val segments: List<Segment> = segments(row.cells(cols), palette)
    val ops: List<TextOp> = buildOps()

    /** The glyph cell covering [column] (the second column of a wide cell gives the wide cell) and its style; null for a blank. */
    fun cell(column: Int): Pair<Cell, TerminalResolvedStyle>? {
        val segment = segments.firstOrNull { column in it.columns } ?: return null
        val covers = { cell: Cell -> cell.column <= column && column < cell.column + cell.width }
        val found = segment.narrow.firstOrNull(covers) ?: segment.clusters.firstOrNull(covers) ?: return null
        if (found.text == " ") return null
        return found to segment.style
    }

    /** Fills the columns of each segment that has a background, with the row's top at [top]. */
    fun drawBackground(canvas: Canvas, top: Float) {
        for (segment in segments) {
            val background = segment.style.background ?: continue
            fill.color = argb(background)
            canvas.drawRect(left(segment), top, right(segment), top + metrics.cellHeight, fill)
        }
    }

    /** Draws the text, then each segment's underline, strike and overline, with the row's top at [top]. */
    fun drawText(canvas: Canvas, top: Float, font: TerminalFont) {
        val baseline = top + metrics.baseline
        for (op in ops) drawOp(canvas, op.text, op.x, op.scaleX, op.color, op.bold, op.italic, baseline, font)
        val thickness = metrics.lineThickness
        for (segment in segments) {
            val style = segment.style
            if (!style.drawsText || !(style.underline || style.strike || style.overline)) continue
            fill.color = argb(style.foreground)
            val left = left(segment)
            val right = right(segment)
            if (style.underline) {
                val y = baseline + metrics.underlineOffset
                canvas.drawRect(left, y, right, y + thickness, fill)
            }
            if (style.strike) {
                val y = baseline - 0.3f * metrics.cellHeight
                canvas.drawRect(left, y, right, y + thickness, fill)
            }
            if (style.overline) canvas.drawRect(left, top, right, top + thickness, fill)
        }
    }

    /** Draws the text of the cell at [column] alone in [color] (the text under a block cursor), as [ops] places it. */
    fun drawCellText(canvas: Canvas, top: Float, column: Int, color: Int, font: TerminalFont) {
        val (cell, style) = cell(column) ?: return
        if (!style.drawsText) return
        val (x, scaleX) = place(cell, metrics.advance(cell.text, style.bold, style.italic))
        drawOp(canvas, cell.text, x, scaleX, color, style.bold, style.italic, top + metrics.baseline, font)
    }

    private fun drawOp(
        canvas: Canvas, text: String, x: Float, scaleX: Float, color: Int, bold: Boolean, italic: Boolean,
        baseline: Float, font: TerminalFont,
    ) {
        val paint = font.paint(bold, italic)
        paint.color = color
        paint.textScaleX = scaleX
        canvas.drawText(text, x, baseline, paint)
        paint.textScaleX = 1f
    }

    private fun left(segment: Segment): Float = segment.columns.first * metrics.cellWidth

    private fun right(segment: Segment): Float = (segment.columns.last + 1) * metrics.cellWidth

    /** A lone glyph's left and squeeze: centred in its cells when narrower, at their left and squeezed when wider. */
    private fun place(cell: Cell, advance: Float): Pair<Float, Float> {
        val box = cell.width * metrics.cellWidth
        val left = cell.column * metrics.cellWidth
        return if (advance > box && advance > 0f) left to box / advance else left + (box - advance) / 2 to 1f
    }

    private fun buildOps(): List<TextOp> {
        val ops = ArrayList<TextOp>()
        for (segment in segments) {
            val style = segment.style
            if (!style.drawsText) continue
            val color = argb(style.foreground)
            fun op(text: String, x: Float, scaleX: Float) {
                ops += TextOp(text, x, scaleX, color, style.bold, style.italic)
            }
            // Narrow cells of the cell's width join one run (spaces inside it included, at its ends left out); every
            // other cell is drawn on its own. Cells come in column order: narrow and clusters are merged by column.
            val run = StringBuilder()
            var runX = 0f
            var trailingSpaces = 0
            fun flush() {
                if (run.isNotEmpty()) op(run.substring(0, run.length - trailingSpaces), runX, 1f)
                run.setLength(0)
                trailingSpaces = 0
            }
            val cells = (segment.narrow.map { it to true } + segment.clusters.map { it to false }).sortedBy { it.first.column }
            for ((cell, narrow) in cells) {
                val advance = metrics.advance(cell.text, style.bold, style.italic)
                if (narrow && abs(advance - metrics.cellWidth) <= 0.5f) {
                    if (cell.text == " ") {
                        if (run.isNotEmpty()) {
                            run.append(' ')
                            trailingSpaces += 1
                        }
                    } else {
                        if (run.isEmpty()) runX = cell.column * metrics.cellWidth
                        run.append(cell.text)
                        trailingSpaces = 0
                    }
                    continue
                }
                flush()
                if (cell.text == " ") continue
                val (x, scaleX) = place(cell, advance)
                op(cell.text, x, scaleX)
            }
            flush()
        }
        return ops
    }

    companion object {
        private val fill = Paint()

        /** Colours as ARGB: `0xFF shl 24 or (r shl 16) or (g shl 8) or b`. */
        fun argb(rgb: TerminalRgb): Int = (0xFF shl 24) or (rgb.red shl 16) or (rgb.green shl 8) or rgb.blue

        /** A segment while its cells are gathered. */
        private class Building(val first: Int, var end: Int, val style: TerminalResolvedStyle) {
            val narrow = ArrayList<Cell>()
            val clusters = ArrayList<Cell>()

            fun build() = Segment(first..end, style, narrow, clusters)
        }

        fun segments(cells: List<TerminalCell>, palette: TerminalPalette): List<Segment> {
            val segments = ArrayList<Building>()
            var lastStyle: TerminalCellStyle? = null
            var lastResolved: TerminalResolvedStyle? = null
            fun resolved(style: TerminalCellStyle): TerminalResolvedStyle {
                val known = lastResolved
                if (known != null && lastStyle == style) return known
                return TerminalColors.resolve(style, palette).also {
                    lastStyle = style
                    lastResolved = it
                }
            }
            cells.forEachIndexed { column, cell ->
                val item: Cell
                val style: TerminalResolvedStyle
                val narrow: Boolean
                when (cell) {
                    TerminalCell.Continuation -> return@forEachIndexed
                    TerminalCell.Blank -> {
                        item = Cell(column, 1, " ")
                        style = resolved(TerminalCellStyle.DEFAULT)
                        narrow = true
                    }
                    is TerminalCell.Glyph -> {
                        item = Cell(column, maxOf(cell.width, 1), cell.text)
                        style = resolved(cell.style)
                        narrow = cell.width == 1 && cell.text.codePointCount(0, cell.text.length) == 1
                    }
                }
                val end = column + item.width - 1
                val last = segments.lastOrNull()?.takeIf { it.style == style && it.end + 1 == column }
                    ?: Building(column, end, style).also { segments += it }
                last.end = end
                if (narrow) last.narrow += item else last.clusters += item
            }
            return segments.map { it.build() }
        }
    }
}
