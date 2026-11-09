package com.shellx.link.core

// The grid of a `terminal.view.frame` (PROTOCOL.md 11.4 and 11.5; `Terminal/TerminalGrid.swift`).

/** What a `terminal.view.frame` holds (PROTOCOL.md 11.4). */
@JvmInline
value class TerminalFrameKind(val wire: String) {
    companion object {
        val SNAPSHOT = TerminalFrameKind("snapshot")
        val DELTA = TerminalFrameKind("delta")
        val HISTORY = TerminalFrameKind("history")
    }
}

@JvmInline
value class TerminalCursorShape(val wire: String) {
    companion object {
        val BLOCK = TerminalCursorShape("block")
        val BAR = TerminalCursorShape("bar")
        val UNDERLINE = TerminalCursorShape("underline")
        val BLOCK_HOLLOW = TerminalCursorShape("block_hollow")
    }
}

@JvmInline
value class TerminalAttribute(val wire: String) {
    companion object {
        val BOLD = TerminalAttribute("bold")
        val FAINT = TerminalAttribute("faint")
        val ITALIC = TerminalAttribute("italic")
        val UNDERLINE = TerminalAttribute("underline")
        val BLINK = TerminalAttribute("blink")
        val INVERSE = TerminalAttribute("inverse")
        val INVISIBLE = TerminalAttribute("invisible")
        val STRIKE = TerminalAttribute("strike")
        val OVERLINE = TerminalAttribute("overline")
    }
}

/** [x] is the column (0 at the left), [y] the screen row (0 at the top). */
data class TerminalCursor(
    val x: Int,
    val y: Int,
    val shape: TerminalCursorShape = TerminalCursorShape.BLOCK,
    val visible: Boolean = true,
    val blink: Boolean = false,
)

/**
 * The terminal's colours (PROTOCOL.md 11.5). A colour is `#rrggbb`. A null [cursor] means the cursor takes the
 * foreground colour; [colors] is the indexed palette, exactly 256 colours.
 */
data class TerminalPalette(val fg: String, val bg: String, val cursor: String? = null, val colors: List<String>)

/** A resolved style: what a cell is drawn with. The default style has default colours and no attribute. */
data class TerminalCellStyle(
    val fg: Int? = null,
    val fgRgb: String? = null,
    val bg: Int? = null,
    val bgRgb: String? = null,
    val attrs: List<TerminalAttribute> = emptyList(),
) {
    companion object {
        val DEFAULT = TerminalCellStyle()
    }
}

/** An entry of a frame's style table (PROTOCOL.md 11.5). Its [id] means something only in its frame. */
data class TerminalStyle(
    val id: Int,
    val fg: Int? = null,
    val fgRgb: String? = null,
    val bg: Int? = null,
    val bgRgb: String? = null,
    val attrs: List<TerminalAttribute> = emptyList(),
) {
    val cellStyle: TerminalCellStyle get() = TerminalCellStyle(fg, fgRgb, bg, bgRgb, attrs)
}

/**
 * A stretch of cells of one style (PROTOCOL.md 11.5). Wire keys `x`, `t`, `s`, `w`. A null [x] means right after the
 * previous run of the line (0 for the first); a null or 0 [style] is the default style; with a [width] the run is
 * exactly one cell of that many columns (1 or 2). It prints the size of its text, never the text.
 */
data class TerminalRun(val x: Int? = null, val text: String, val style: Int? = null, val width: Int? = null) {
    override fun toString(): String = "TerminalRun(x=$x, text=<${text.utf8Size} bytes>, style=$style, width=$width)"
}

/** [y] is 0 to rows - 1 for the screen, -1 to -history for history rows (-1 the newest). */
data class TerminalLine(val y: Int, val runs: List<TerminalRun> = emptyList())

/**
 * The head of a frame, carried by its part 0 (PROTOCOL.md 11.5). [history] is the history rows the frame carries,
 * [scroll] the rows that left the top of the screen since the frame before (deltas); both are left out when 0.
 */
data class TerminalFrameHead(
    val kind: TerminalFrameKind,
    val cols: Int,
    val rows: Int,
    val alt: Boolean = false,
    val cursor: TerminalCursor? = null,
    val palette: TerminalPalette? = null,
    val history: Int = 0,
    val scroll: Int = 0,
)

/** One message of a frame: `terminal.view.frame` without its `terminal_id` (PROTOCOL.md 11.4). [head] is part 0's. */
data class TerminalFramePart(
    val revision: Long,
    val part: Int = 0,
    val parts: Int = 1,
    val head: TerminalFrameHead? = null,
    val styles: List<TerminalStyle> = emptyList(),
    val lines: List<TerminalLine> = emptyList(),
) {
    companion object {
        /**
         * Stands where this phone dropped frames before they reached the assembler ([TerminalPushQueue] was full; plan
         * 3G Task 4b). A later part of no frame being assembled, so [TerminalFrameAssembler] takes it as a gap and asks
         * for one resync. Its revision 0 is one the codec refuses both ways, so no frame from the wire equals it. Never
         * sent, and never applied.
         */
        val LOST = TerminalFramePart(revision = 0, part = 1, parts = 2)
    }
}

/** One whole frame, all parts merged: what the assembler hands out and the screen applies. */
data class TerminalGridFrame(
    val head: TerminalFrameHead,
    val styles: List<TerminalStyle> = emptyList(),
    val lines: List<TerminalLine> = emptyList(),
)

/** Far above any grid, low enough that column arithmetic cannot overflow (2A's `maxColumn`). */
private const val MAX_RUN_COLUMN = 1_000_000

private const val MAX_STYLE_ID = 65_535

/**
 * The structural rules of PROTOCOL.md 11.4 and 11.5 that the codec enforces on encode and decode. Size limits of a
 * grid (beyond 1 000) are not checked here: a receiver treats them as a gap (11.7).
 */
internal fun TerminalFramePart.isValid(): Boolean {
    if (revision < 1 || parts !in 1..ShellXLink.TERMINAL_MAX_FRAME_PARTS || part !in 0 until parts) return false
    head?.let { h ->
        if (h.cols < 1 || h.rows < 1 || h.history < 0 || h.scroll < 0) return false
        h.cursor?.let { if (it.x < 0 || it.y < 0) return false }
        h.palette?.let { p ->
            if (!isTerminalColor(p.fg) || !isTerminalColor(p.bg) || !(p.cursor?.let(::isTerminalColor) ?: true)) return false
            if (p.colors.size != 256 || !p.colors.all(::isTerminalColor)) return false
        }
    }
    for (s in styles) {
        if (s.id !in 1..MAX_STYLE_ID) return false
        if (s.fg != null && s.fg !in 0..255) return false
        if (s.bg != null && s.bg !in 0..255) return false
        if (s.fgRgb != null && !isTerminalColor(s.fgRgb)) return false
        if (s.bgRgb != null && !isTerminalColor(s.bgRgb)) return false
        if (s.fg != null && s.fgRgb != null) return false
        if (s.bg != null && s.bgRgb != null) return false
    }
    for (line in lines) {
        for (run in line.runs) {
            if (run.text.isEmpty()) return false
            if (run.width != null && run.width !in 1..2) return false
            if (run.x != null && run.x !in 0..MAX_RUN_COLUMN) return false
            if (run.style != null && run.style !in 0..MAX_STYLE_ID) return false
        }
    }
    return true
}

/** `#` followed by 6 hexadecimal digits, either case. */
internal fun isTerminalColor(text: String): Boolean =
    text.length == 7 && text[0] == '#' && (1 until 7).all { text[it] in '0'..'9' || text[it] in 'a'..'f' || text[it] in 'A'..'F' }
