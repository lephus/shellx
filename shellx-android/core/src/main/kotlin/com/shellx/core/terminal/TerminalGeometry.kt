package com.shellx.core.terminal

import kotlin.math.floor
import kotlin.math.truncate

/** The grid the phone asks for. */
data class TerminalGridSize(val cols: Int, val rows: Int)

/** Whole lines of a pan, and what is left of it for the next one. */
data class TerminalScrollStep(val lines: Int, val carry: Float)

/**
 * Sizes of the terminal pane (TerminalGeometry.swift): the grid the phone asks for, the scale that fits a wider grid,
 * and alternate-screen scroll lines. Every length is in the caller's unit (px in the app), [PADDING_DP] included once
 * the caller converts it.
 */
object TerminalGeometry {
    const val PADDING_DP = 4f
    const val MAX_ZOOM = 2f

    /** The grid the phone asks for: what fits the viewport at the default font, whose cell is given; at least 1 × 1. */
    fun phoneGrid(viewportWidth: Float, viewportHeight: Float, cellWidth: Float, cellHeight: Float, padding: Float): TerminalGridSize {
        if (cellWidth <= 0f || cellHeight <= 0f) return TerminalGridSize(1, 1)
        val cols = floor((viewportWidth - 2 * padding) / cellWidth).toInt()
        val rows = floor((viewportHeight - 2 * padding) / cellHeight).toInt()
        return TerminalGridSize(maxOf(1, cols), maxOf(1, rows))
    }

    /** The scale that fits [cols] columns into [viewportWidth]; 1 when they fit already (never larger than 1). */
    fun fitScale(cols: Int, cellWidth: Float, viewportWidth: Float, padding: Float): Float {
        val content = maxOf(cols, 1) * cellWidth
        if (content <= 0f) return 1f
        return minOf(1f, maxOf(viewportWidth - 2 * padding, 1f) / content)
    }

    /**
     * Whole lines of a vertical pan on the alternate screen: `carry + translation` over `lineHeight × scale`, truncated
     * toward zero (positive for a finger moving down, toward older content); the rest carries over.
     */
    fun scrollLines(translation: Float, carry: Float, lineHeight: Float, scale: Float): TerminalScrollStep {
        val total = carry + translation
        val line = lineHeight * scale
        if (line <= 0f || !total.isFinite()) return TerminalScrollStep(0, 0f)
        val lines = truncate(total / line)
        return TerminalScrollStep(lines.toInt(), total - lines * line)
    }
}

/** The user's pinch over a grid (TerminalZoom.swift): null follows the fit scale; a grid with other columns goes back to it. Immutable: each change returns the changed copy. */
data class TerminalZoom(val zoom: Float? = null, val cols: Int? = null) {
    /** Remembers [cols]; a different value than the last sets the zoom back to null (fit). */
    fun gridChanged(cols: Int): TerminalZoom = if (cols != this.cols) TerminalZoom(null, cols) else this

    /** Stores the pinch, kept between [fit] and [TerminalGeometry.MAX_ZOOM]. */
    fun pinch(to: Float, fit: Float): TerminalZoom = copy(zoom = minOf(maxOf(to, fit), TerminalGeometry.MAX_ZOOM))

    /** The scale to draw at: the pinch (or fit), never below [fit] nor above [TerminalGeometry.MAX_ZOOM]. */
    fun scale(fit: Float): Float = minOf(maxOf(zoom ?: fit, fit), TerminalGeometry.MAX_ZOOM)
}
