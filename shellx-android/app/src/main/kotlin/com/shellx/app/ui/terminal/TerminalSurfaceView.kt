package com.shellx.app.ui.terminal

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.MotionEvent
import android.view.View
import com.shellx.core.terminal.TerminalColors
import com.shellx.core.terminal.TerminalGeometry
import com.shellx.core.terminal.TerminalViewModel
import com.shellx.core.terminal.TerminalViewPhase
import com.shellx.core.terminal.TerminalViewState
import com.shellx.core.terminal.TerminalViewport
import com.shellx.link.core.TerminalCursorShape
import com.shellx.link.core.TerminalPalette
import com.shellx.link.core.TerminalRow
import com.shellx.link.core.TerminalScreen

/**
 * Draws `model.screen` (it keeps no copy of it) through [viewport]: history rows and screen rows on the main screen,
 * screen rows on the alternate one, at `TerminalViewport.scale` (fit to the width unless pinched), following the bottom
 * unless scrolled up (then held in place by `topShift`). The iPhone's `TerminalSurfaceView` and `TerminalCanvasView` in
 * one View; the gestures are `TerminalPane`'s, so [onTouchEvent] returns false.
 *
 * A frame draws only the visible rows, from layouts kept by row object ([TerminalRowCache]): every row's backgrounds,
 * then every row's text and lines, then the cursor, then the text being composed, so a diacritic that rises into the
 * row above is never painted over. Main thread only.
 */
@SuppressLint("ViewConstructor") // Made in code by TerminalPane only.
class TerminalSurfaceView(
    context: Context,
    val model: TerminalViewModel,
    /** The terminal of the page this surface belongs to: the model is every page's, and shows one terminal at a time. */
    val terminalId: String,
    val font: TerminalFont,
) : View(context) {
    private val density = context.resources.displayMetrics.density
    private val padding = TerminalGeometry.PADDING_DP * density
    private val cache = TerminalRowCache(font)
    private val fill = Paint()
    private val stroke = Paint().apply { style = Paint.Style.STROKE }

    /** Called with every new [viewport]. */
    var onViewportChange: (TerminalViewport) -> Unit = {}

    /** What the screen is drawn with before a palette came (the card's colour). */
    var emptyColor: Int = 0

    var viewport: TerminalViewport = TerminalViewport(font.cellWidth, font.cellHeight, padding)
        private set

    private var state = TerminalViewState()
    private var lastSnapshots: Int? = null
    private var lastTopShift = 0
    private var lastSentInputs = 0

    /** What is left of a vertical drag on the alternate screen below one line (TerminalGeometry.scrollLines). */
    private var scrollCarry = 0f

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    // Updates

    /**
     * The model changed: a new snapshot or typing goes back to the bottom, rows added above a scrolled-up view keep it
     * in place, and a grid of other columns goes back to fit.
     */
    fun render(state: TerminalViewState) {
        this.state = state
        val screen = model.screen
        val newSnapshot = state.snapshots != lastSnapshots
        val typed = state.sentInputs != lastSentInputs
        val shift = state.topShift - lastTopShift
        lastSnapshots = state.snapshots
        lastSentInputs = state.sentInputs
        lastTopShift = state.topShift
        setViewport(viewport.contentChanged(screen.cols, shownRows(screen), if (newSnapshot) 0 else shift, toBottom = newSnapshot || typed))
        invalidate()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        setViewport(viewport.resized(w.toFloat(), h.toFloat()))
    }

    private fun setViewport(next: TerminalViewport) {
        if (next == viewport) return
        viewport = next
        onViewportChange(next)
        invalidate()
    }

    private fun shownRows(screen: TerminalScreen): Int = (if (screen.alt) 0 else screen.historyRows.size) + screen.rows

    // Gestures (TerminalPane's)

    @SuppressLint("ClickableViewAccessibility") // The pane's gestures stand for it.
    override fun onTouchEvent(event: MotionEvent): Boolean = false

    /** The alternate screen while its grid fits the height: a vertical drag sends scroll lines to the Mac. */
    private val scrollsTheMac: Boolean
        get() = model.screen.alt && viewport.contentHeight <= viewport.height + 0.5f

    /**
     * A vertical drag of [delta] px (a finger moving down is positive): on the main screen it shows older rows and
     * returns the px used; on the alternate screen, while the grid fits the height, it becomes `model.scroll(lines)`
     * and uses all of [delta].
     */
    fun dragVertically(delta: Float): Float {
        if (scrollsTheMac) {
            val step = TerminalGeometry.scrollLines(delta, scrollCarry, font.cellHeight, viewport.scale)
            scrollCarry = step.carry
            if (step.lines != 0 && accepts()) model.scroll(step.lines)
            return delta
        }
        val before = viewport.scrollY
        setViewport(viewport.scrolledBy(0f, -delta))
        return before - viewport.scrollY
    }

    /** The drag ended: the scroll-line carry starts again at 0. */
    fun endVerticalDrag() {
        scrollCarry = 0f
    }

    /** A sideways drag pans while the grid is wider than the pane; returns the px used. */
    fun dragHorizontally(delta: Float): Float {
        val before = viewport.scrollX
        setViewport(viewport.scrolledBy(-delta, 0f))
        return before - viewport.scrollX
    }

    /** Zooms by [factor] around the point ([focusX], [focusY]) of the view, between fit and TerminalGeometry.MAX_ZOOM. */
    fun pinch(factor: Float, focusX: Float, focusY: Float) {
        setViewport(viewport.pinched(factor, focusX, focusY))
    }

    /** Input from this surface may reach the model: its page is the terminal shown, and it takes input. */
    internal fun accepts(): Boolean = model.terminalId == terminalId && model.acceptsInput

    // Drawing

    override fun onDraw(canvas: Canvas) {
        val screen = model.screen
        val palette = screen.palette
        if (palette == null || screen.cols <= 0) {
            canvas.drawColor(emptyColor)
            return
        }
        canvas.drawColor(TerminalRowLayout.argb(TerminalColors.background(palette)))
        val history = if (screen.alt) 0 else screen.historyRows.size
        val visible = viewport.visibleRows
        canvas.save()
        canvas.translate(padding - viewport.scrollX, padding - viewport.scrollY)
        val scale = viewport.scale
        canvas.scale(scale, scale)
        val drawn = ArrayList<Pair<Int, TerminalRowLayout>>(if (visible.isEmpty()) 0 else visible.last - visible.first + 1)
        for (index in visible) {
            val row = row(screen, index, history) ?: continue
            drawn += index to cache.layout(row, screen.cols, palette)
        }
        for ((index, layout) in drawn) layout.drawBackground(canvas, index * font.cellHeight)
        for ((index, layout) in drawn) layout.drawText(canvas, index * font.cellHeight, font)
        drawCursor(canvas, screen, palette, history)
        drawMarkedText(canvas, screen, palette, history)
        canvas.restore()
        if (!visible.isEmpty()) cache.retain(rowsAround(screen, visible, history))
    }

    /** The shown row [index]: history rows first on the main screen, then the screen's. */
    private fun row(screen: TerminalScreen, index: Int, history: Int): TerminalRow? {
        if (index < history) return screen.historyRows.getOrNull(index)
        val y = index - history
        if (y >= screen.rows) return null
        return screen.screenRows.getOrNull(y) ?: BLANK
    }

    /** The rows within [CACHE_MARGIN] of the visible ones, whose layouts stay. */
    private fun rowsAround(screen: TerminalScreen, visible: IntRange, history: Int): List<TerminalRow> {
        val first = maxOf(0, visible.first - CACHE_MARGIN)
        val last = minOf(history + screen.rows - 1, visible.last + CACHE_MARGIN)
        return (first..last).mapNotNull { row(screen, it, history) }
    }

    /** The cursor's box in grid px (two columns over a wide cell), its column, and the layout of its row. */
    private fun cursorBox(screen: TerminalScreen, palette: TerminalPalette, history: Int): Triple<FloatArray, Int, TerminalRowLayout>? {
        val cursor = screen.cursor ?: return null
        if (cursor.y !in 0 until screen.rows || cursor.x !in 0 until screen.cols) return null
        val index = history + cursor.y
        val layout = cache.layout(row(screen, index, history) ?: BLANK, screen.cols, palette)
        val found = layout.cell(cursor.x)?.first
        val column = found?.column ?: cursor.x
        val width = found?.width ?: 1
        val left = column * font.cellWidth
        val top = index * font.cellHeight
        return Triple(floatArrayOf(left, top, left + width * font.cellWidth, top + font.cellHeight), column, layout)
    }

    /** Only while Live, the cursor visible and nothing composed; it never blinks. */
    private fun drawCursor(canvas: Canvas, screen: TerminalScreen, palette: TerminalPalette, history: Int) {
        val cursor = screen.cursor ?: return
        if (state.phase != TerminalViewPhase.Live || !cursor.visible || state.markedText.isNotEmpty()) return
        val (box, column, layout) = cursorBox(screen, palette, history) ?: return
        val color = TerminalRowLayout.argb(TerminalColors.cursor(palette))
        val (left, top, right, bottom) = box
        fill.color = color
        when (cursor.shape) {
            TerminalCursorShape.BAR -> canvas.drawRect(left, top, left + 2 * density, bottom, fill)
            TerminalCursorShape.UNDERLINE -> canvas.drawRect(left, bottom - 2 * density, right, bottom, fill)
            TerminalCursorShape.BLOCK_HOLLOW -> {
                stroke.color = color
                stroke.strokeWidth = density
                val inset = density / 2
                canvas.drawRect(left + inset, top + inset, right - inset, bottom - inset, stroke)
            }
            else -> {
                canvas.drawRect(left, top, right, bottom, fill)
                layout.drawCellText(canvas, top, column, TerminalRowLayout.argb(TerminalColors.background(palette)), font)
            }
        }
    }

    /** The text the keyboard is composing, at the cursor's cell: palette foreground on palette background, underlined. */
    private fun drawMarkedText(canvas: Canvas, screen: TerminalScreen, palette: TerminalPalette, history: Int) {
        val marked = state.markedText
        if (marked.isEmpty()) return
        val (box, _, _) = cursorBox(screen, palette, history) ?: return
        val left = box[0]
        val top = box[1]
        val width = maxOf(font.advance(marked, bold = false, italic = false), font.cellWidth)
        fill.color = TerminalRowLayout.argb(TerminalColors.background(palette))
        canvas.drawRect(left, top, left + width, top + font.cellHeight, fill)
        val foreground = TerminalRowLayout.argb(TerminalColors.foreground(palette))
        val paint = font.paint(bold = false, italic = false)
        paint.color = foreground
        canvas.drawText(marked, left, top + font.baseline, paint)
        // At the cell's bottom, below the font's underline position, so the dots under Vietnamese vowels (ạ, ệ) stay clear.
        fill.color = foreground
        canvas.drawRect(left, top + font.cellHeight - density, left + width, top + font.cellHeight, fill)
    }

    private companion object {
        /** Rows kept laid out beyond the visible ones, above and below. */
        const val CACHE_MARGIN = 40

        val BLANK = TerminalRow()
    }
}
