package com.shellx.core.terminal

import kotlin.math.ceil
import kotlin.math.floor

/**
 * Android only (the iPhone's UIScrollView keeps this): where the pane looks into the drawn grid. Immutable: each change
 * returns the changed copy. Every length is in the caller's unit (px in the app). The drawn grid is [cols] ×
 * [shownRows] cells of [cellWidth] × [cellHeight] at [scale], inside [padding] on each side.
 *
 * Rules (plan 3G Task 8):
 * - Every result has [scrollX] in `0..maxScrollX` and [scrollY] in `0..maxScrollY`.
 * - [resized] keeps the scroll, and a viewport that follows the bottom stays at [maxScrollY].
 * - [contentChanged] first applies `zoom.gridChanged(cols)`. With `toBottom` or [followsBottom] the result is at
 *   [maxScrollY] with [followsBottom] true. Otherwise [scrollY] moves by `topShiftDelta × cellHeight × scale`.
 * - [scrolledBy] adds `dx` and `dy`, then sets [followsBottom] to `scrollY >= maxScrollY - 0.5`.
 * - [pinched]: with `s0` the scale before and `s1` the scale of `zoom.pinch(s0 × factor, fit)`, the content point under
 *   the focus stays: `scrollX' = (scrollX + focusX − padding) × s1 / s0 + padding − focusX`, the same for y; then
 *   clamped, and [followsBottom] as in [scrolledBy].
 */
data class TerminalViewport(
    val cellWidth: Float,
    val cellHeight: Float,
    val padding: Float,
    val width: Float = 0f,
    val height: Float = 0f,
    val cols: Int = 0,
    /** History rows (main screen) plus screen rows. */
    val shownRows: Int = 0,
    val zoom: TerminalZoom = TerminalZoom(),
    /** The content point at the viewport's top left. */
    val scrollX: Float = 0f,
    val scrollY: Float = 0f,
    val followsBottom: Boolean = true,
) {
    val fit: Float get() = TerminalGeometry.fitScale(cols, cellWidth, width, padding)
    val scale: Float get() = zoom.scale(fit)
    val contentWidth: Float get() = 2 * padding + cols * cellWidth * scale
    val contentHeight: Float get() = 2 * padding + shownRows * cellHeight * scale
    val maxScrollX: Float get() = maxOf(0f, contentWidth - width)
    val maxScrollY: Float get() = maxOf(0f, contentHeight - height)

    /** The shown rows the viewport touches (0 = the oldest history row on the main screen); IntRange.EMPTY when none. */
    val visibleRows: IntRange
        get() {
            val rowHeight = cellHeight * scale
            if (shownRows <= 0 || rowHeight <= 0f) return IntRange.EMPTY
            val first = floor((scrollY - padding) / rowHeight).toInt().coerceIn(0, shownRows - 1)
            val last = (ceil((scrollY + height - padding) / rowHeight).toInt() - 1).coerceIn(0, shownRows - 1)
            return if (first > last) IntRange.EMPTY else first..last
        }

    fun resized(width: Float, height: Float): TerminalViewport {
        val sized = copy(width = width, height = height)
        return if (followsBottom) sized.atBottom() else sized.clamped()
    }

    /** The model changed: topShiftDelta rows were added above (negative: dropped from the top); toBottom: a new snapshot or typing. */
    fun contentChanged(cols: Int, shownRows: Int, topShiftDelta: Int, toBottom: Boolean): TerminalViewport {
        val changed = copy(cols = cols, shownRows = shownRows, zoom = zoom.gridChanged(cols))
        if (toBottom || followsBottom) return changed.atBottom()
        return changed.copy(scrollY = scrollY + topShiftDelta * changed.cellHeight * changed.scale).clamped()
    }

    fun scrolledBy(dx: Float, dy: Float): TerminalViewport =
        copy(scrollX = scrollX + dx, scrollY = scrollY + dy).clamped().following()

    fun pinched(factor: Float, focusX: Float, focusY: Float): TerminalViewport {
        val s0 = scale
        val pinched = copy(zoom = zoom.pinch(s0 * factor, fit))
        val s1 = pinched.scale
        if (s0 <= 0f) return pinched.clamped().following()
        return pinched.copy(
            scrollX = (scrollX + focusX - padding) * s1 / s0 + padding - focusX,
            scrollY = (scrollY + focusY - padding) * s1 / s0 + padding - focusY,
        ).clamped().following()
    }

    private fun clamped(): TerminalViewport =
        copy(scrollX = scrollX.coerceIn(0f, maxScrollX), scrollY = scrollY.coerceIn(0f, maxScrollY))

    private fun atBottom(): TerminalViewport =
        copy(scrollX = scrollX.coerceIn(0f, maxScrollX), scrollY = maxScrollY, followsBottom = true)

    private fun following(): TerminalViewport = copy(followsBottom = scrollY >= maxScrollY - 0.5f)
}
