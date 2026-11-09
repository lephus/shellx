package com.shellx.link.core

/** One cell of a screen row. */
sealed interface TerminalCell {
    /** A space in the default style. */
    data object Blank : TerminalCell

    data class Glyph(val text: String, val width: Int, val style: TerminalCellStyle) : TerminalCell {
        override fun toString(): String = "Glyph(text=<${text.utf8Size} bytes>, width=$width, style=$style)"
    }

    /** The second column of a wide cell. */
    data object Continuation : TerminalCell
}

/**
 * A run with its column resolved and its style id replaced by the style (PROTOCOL.md 11.5). A null [width] means
 * narrow cells, one per Unicode scalar; 1 or 2 means one cell of that many columns holding all of [text].
 */
data class TerminalStyledRun(
    val x: Int,
    val text: String,
    val width: Int? = null,
    val style: TerminalCellStyle = TerminalCellStyle.DEFAULT,
) {
    override fun toString(): String = "TerminalStyledRun(x=$x, text=<${text.utf8Size} bytes>, width=$width, style=$style)"
}

/**
 * One row of the screen or the history: runs in order, later runs overwriting earlier ones. Immutable. A row keeps its
 * object while it moves from the screen into history, so a renderer can cache by object.
 */
data class TerminalRow(val runs: List<TerminalStyledRun> = emptyList()) {
    /**
     * Exactly [cols] cells. Cells at or past [cols] are dropped, with a wide cell that does not fit whole; a later run
     * overwrites an earlier one cell by cell (a wide cell half overwritten leaves a blank, not half a glyph).
     */
    fun cells(cols: Int): List<TerminalCell> {
        if (cols <= 0) return emptyList()
        val cells = Array<TerminalCell>(cols) { TerminalCell.Blank }
        fun put(index: Int, cell: TerminalCell) {
            when (val old = cells[index]) {
                TerminalCell.Continuation -> if (index > 0) cells[index - 1] = TerminalCell.Blank
                is TerminalCell.Glyph ->
                    if (old.width == 2 && index + 1 < cols && cells[index + 1] == TerminalCell.Continuation) {
                        cells[index + 1] = TerminalCell.Blank
                    }
                TerminalCell.Blank -> Unit
            }
            cells[index] = cell
        }
        for (run in runs) {
            if (run.x < 0) continue
            val width = run.width
            if (width != null) {
                if (run.x + width > cols) continue
                put(run.x, TerminalCell.Glyph(run.text, width, run.style))
                if (width == 2) put(run.x + 1, TerminalCell.Continuation)
            } else {
                var x = run.x
                var i = 0
                while (i < run.text.length && x < cols) {
                    val scalar = run.text.codePointAt(i)
                    val n = Character.charCount(scalar)
                    put(x, TerminalCell.Glyph(run.text.substring(i, i + n), 1, run.style))
                    x += 1
                    i += n
                }
            }
        }
        return cells.asList()
    }

    /**
     * The cells' text from left to right: a blank cell is a space, the second column of a wide cell is nothing, and
     * trailing spaces are removed (the row text rule of `spec/vectors/terminal.json`).
     */
    fun text(cols: Int): String {
        val out = StringBuilder()
        for (cell in cells(cols)) {
            when (cell) {
                TerminalCell.Blank -> out.append(' ')
                is TerminalCell.Glyph -> out.append(cell.text)
                TerminalCell.Continuation -> Unit
            }
        }
        return out.trimEnd(' ').toString()
    }

    override fun toString(): String = "TerminalRow(runs=${runs.size})"
}

/**
 * What the phone holds for one view: it applies the frames that [TerminalFrameAssembler] admits (PROTOCOL.md 11.6 and
 * the receiver rules of 11.5; `Terminal/TerminalScreen.swift`). Mutable: its owner applies frames and reads it on the
 * same thread. [screenRows] and [historyRows] are live views of what it holds.
 */
class TerminalScreen(maxHistoryRows: Int = DEFAULT_MAX_HISTORY_ROWS) {
    companion object {
        const val DEFAULT_MAX_HISTORY_ROWS = 10_000
    }

    val maxHistoryRows: Int = maxOf(0, maxHistoryRows)

    /** 0, 0 and false before the first snapshot. */
    var cols: Int = 0
        private set
    var rows: Int = 0
        private set
    var alt: Boolean = false
        private set

    /** Moved into the grid. */
    var cursor: TerminalCursor? = null
        private set
    var palette: TerminalPalette? = null
        private set

    private val screen = ArrayList<TerminalRow>()
    private val history = ArrayDeque<TerminalRow>()

    /** `rows` rows. */
    val screenRows: List<TerminalRow> get() = screen

    /** Oldest first, at most [maxHistoryRows]. */
    val historyRows: List<TerminalRow> get() = history

    /** False once any history row was dropped since the last snapshot: history frames could no longer join. */
    private var historyIntact = true

    fun apply(frame: TerminalGridFrame) {
        val head = frame.head
        if (head.cols < 1 || head.rows < 1) return
        when (head.kind) {
            TerminalFrameKind.SNAPSHOT -> {
                val byY = rowsByY(frame.lines, StyleTable(frame.styles))
                cols = head.cols
                rows = head.rows
                alt = head.alt
                palette = head.palette
                screen.clear()
                for (y in 0 until rows) screen += byY[y] ?: TerminalRow()
                history.clear()
                historyIntact = true
                if (!alt && head.history > 0) setHistory(historyRows(head.history, head.history, byY), replacing = true)
                setCursor(head.cursor)
            }
            TerminalFrameKind.DELTA -> {
                if (head.cols != cols || head.rows != rows || head.alt != alt) return
                val byY = rowsByY(frame.lines, StyleTable(frame.styles))
                if (!alt && head.scroll > 0) {
                    val k = minOf(head.scroll, rows)
                    // The row objects move; they are never copied.
                    val scrolled = ArrayList<TerminalRow>(screen.subList(0, k))
                    val carried = minOf(head.history, maxOf(0, head.scroll - rows))
                    if (carried > 0) scrolled += historyRows(head.history, carried, byY)
                    appendHistory(scrolled)
                    screen.subList(0, k).clear()
                    repeat(k) { screen += TerminalRow() }
                }
                for ((y, row) in byY) if (y in 0 until rows) screen[y] = row
                setCursor(head.cursor)
            }
            TerminalFrameKind.HISTORY -> {
                if (head.cols != cols || head.rows != rows || alt || head.alt || !historyIntact || head.history <= 0) return
                val byY = rowsByY(frame.lines, StyleTable(frame.styles))
                setHistory(historyRows(head.history, head.history, byY), replacing = false)
            }
            else -> return
        }
    }

    /** [y] >= 0 is a screen row; [y] < 0 is a history row counted from the newest (-1). */
    fun cell(x: Int, y: Int): TerminalCell {
        if (x < 0 || x >= cols) return TerminalCell.Blank
        val row = if (y >= 0) {
            screen.getOrNull(y)
        } else {
            history.getOrNull(history.size + y)
        } ?: return TerminalCell.Blank
        return row.cells(cols)[x]
    }

    fun screenText(): List<String> = screen.map { it.text(cols) }

    fun historyText(): List<String> = history.map { it.text(cols) }

    private fun setCursor(cursor: TerminalCursor?) {
        if (cursor == null) return
        this.cursor = cursor.copy(x = cursor.x.coerceIn(0, cols - 1), y = cursor.y.coerceIn(0, rows - 1))
    }

    /** Rows that scrolled off the top, at the newest end. */
    private fun appendHistory(newRows: List<TerminalRow>) {
        if (newRows.isEmpty()) return
        history.addAll(newRows)
        trimOldest()
    }

    /** [newRows] oldest first. Replacing: the snapshot's own history. Otherwise they go above the oldest row held. */
    private fun setHistory(newRows: List<TerminalRow>, replacing: Boolean) {
        if (replacing) history.clear()
        history.addAll(0, newRows)
        trimOldest()
    }

    private fun trimOldest() {
        val excess = history.size - maxHistoryRows
        if (excess > 0) {
            repeat(excess) { history.removeFirst() }
            historyIntact = false
        }
    }

    /**
     * The newest [take] of a frame's [count] history rows (oldest first), from the lines at y -count … -1; a row
     * without lines is blank.
     */
    private fun historyRows(count: Int, take: Int, byY: Map<Int, TerminalRow>): List<TerminalRow> =
        (count - take until count).map { byY[it - count] ?: TerminalRow() }

    private class StyleTable(list: List<TerminalStyle>) {
        private val styles = HashMap<Int, TerminalCellStyle>().apply { for (s in list) put(s.id, s.cellStyle) }

        fun resolve(id: Int?): TerminalCellStyle = if (id == null || id == 0) TerminalCellStyle.DEFAULT else styles[id] ?: TerminalCellStyle.DEFAULT
    }

    /** Lines with the same `y` make one row, in order; a run without `x` follows the previous run of its line. */
    private fun rowsByY(lines: List<TerminalLine>, table: StyleTable): Map<Int, TerminalRow> {
        val runsByY = LinkedHashMap<Int, MutableList<TerminalStyledRun>>()
        for (line in lines) {
            val runs = runsByY.getOrPut(line.y) { ArrayList() }
            var next = 0
            for (run in line.runs) {
                val x = run.x ?: next
                runs += TerminalStyledRun(x, run.text, run.width, table.resolve(run.style))
                next = x + (run.width ?: run.text.codePointCount(0, run.text.length))
            }
        }
        return runsByY.mapValues { TerminalRow(it.value) }
    }
}
