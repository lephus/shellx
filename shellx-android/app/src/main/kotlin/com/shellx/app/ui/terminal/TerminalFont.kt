package com.shellx.app.ui.terminal

import android.content.Context
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import kotlin.math.ceil
import kotlin.math.max

/** The cell and the glyph widths a layout places text by, in px. Tests give their own. */
interface TerminalGlyphMetrics {
    val cellWidth: Float
    val cellHeight: Float

    /** From a cell's top to its baseline. */
    val baseline: Float

    /** Below the baseline, positive downward. */
    val underlineOffset: Float
    val lineThickness: Float

    /** The drawn width of [text] in that face, px. */
    fun advance(text: String, bold: Boolean, italic: Boolean): Float
}

/**
 * The system monospace at [SIZE_DP] (`TerminalFont.swift`, SF Mono at 12 pt): regular, bold, italic and bold italic.
 * In dp, not sp: the grid never follows the system font size, a pinch zooms the drawing instead (`TerminalZoom`).
 *
 * [cellWidth] is the regular face's advance of "0"; [cellHeight] is `ceil(descent − ascent + leading)`; [baseline] is
 * `−ascent + leading / 2`. The underline's position and thickness come from Paint on API 29 and later, else
 * 0.1 × textSize and max(1 px, textSize / 14). Ligatures and contextual alternates are off (a terminal places every
 * character in its own cell). Advances are kept per face, at most [ADVANCES_KEPT] each. Main thread only.
 */
class TerminalFont(context: Context) : TerminalGlyphMetrics {
    companion object {
        const val SIZE_DP = 12f

        /** Advances kept per face before the face's cache starts again. */
        const val ADVANCES_KEPT = 4_096

        private const val FEATURES = "'liga' 0, 'clig' 0, 'calt' 0"
    }

    private val textSize = SIZE_DP * context.resources.displayMetrics.density

    /** regular, bold, italic, bold italic. */
    private val faces: Array<Paint> = arrayOf(Typeface.NORMAL, Typeface.BOLD, Typeface.ITALIC, Typeface.BOLD_ITALIC).map { style ->
        Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            typeface = Typeface.create(Typeface.MONOSPACE, style)
            textSize = this@TerminalFont.textSize
            fontFeatureSettings = FEATURES
        }
    }.toTypedArray()

    private val advances: Array<HashMap<String, Float>> = Array(4) { HashMap() }

    override val cellWidth: Float
    override val cellHeight: Float
    override val baseline: Float
    override val underlineOffset: Float
    override val lineThickness: Float

    init {
        val regular = faces[0]
        val metrics = regular.fontMetrics
        val zero = regular.measureText("0")
        cellWidth = if (zero > 0f) zero else textSize * 0.6f
        // A face that reports no metrics still gets a usable cell.
        val height = ceil(metrics.descent - metrics.ascent + metrics.leading)
        cellHeight = if (height > 0f) height else ceil(textSize * 1.2f)
        baseline = if (height > 0f) -metrics.ascent + metrics.leading / 2 else textSize
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            underlineOffset = regular.underlinePosition
            lineThickness = max(1f, regular.underlineThickness)
        } else {
            underlineOffset = 0.1f * textSize
            lineThickness = max(1f, textSize / 14f)
        }
    }

    /** The face's paint; a caller that changes its colour or scale sets them before each use. */
    fun paint(bold: Boolean, italic: Boolean): Paint = faces[face(bold, italic)]

    override fun advance(text: String, bold: Boolean, italic: Boolean): Float {
        val index = face(bold, italic)
        val kept = advances[index]
        kept[text]?.let { return it }
        if (kept.size >= ADVANCES_KEPT) kept.clear()
        val paint = faces[index]
        val scale = paint.textScaleX
        paint.textScaleX = 1f
        val width = paint.measureText(text)
        paint.textScaleX = scale
        kept[text] = width
        return width
    }

    private fun face(bold: Boolean, italic: Boolean): Int = (if (bold) 1 else 0) + (if (italic) 2 else 0)
}
