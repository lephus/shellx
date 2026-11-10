package com.shellx.app.ui.terminal

import com.shellx.link.core.TerminalPalette
import com.shellx.link.core.TerminalRow
import java.util.Collections
import java.util.IdentityHashMap

/**
 * Row layouts by row object: a `TerminalRow` keeps its object while it moves from the screen into history, so an echo
 * lays out one row again and a scroll none. Keyed by identity, never by equality: a row is a data class, and comparing
 * it would walk its runs for every row of every frame (review A m10). Everything is dropped when the columns or the
 * palette change. Main thread only.
 */
class TerminalRowCache(private val metrics: TerminalGlyphMetrics) {
    private val layouts = IdentityHashMap<TerminalRow, TerminalRowLayout>()
    private var cols = -1
    private var palette: TerminalPalette? = null

    /** Layouts built so far (tests). */
    var builds: Int = 0
        private set

    fun layout(row: TerminalRow, cols: Int, palette: TerminalPalette): TerminalRowLayout {
        // A snapshot brings the same palette as a new object: equal is the same palette.
        if (cols != this.cols || (palette !== this.palette && palette != this.palette)) {
            layouts.clear()
            this.cols = cols
        }
        this.palette = palette
        return layouts.getOrPut(row) {
            builds += 1
            TerminalRowLayout(row, cols, palette, metrics)
        }
    }

    /** Drops every layout but those of [rows]. */
    fun retain(rows: Collection<TerminalRow>) {
        val kept = Collections.newSetFromMap(IdentityHashMap<TerminalRow, Boolean>(rows.size * 2))
        kept.addAll(rows)
        layouts.keys.retainAll(kept)
    }
}
