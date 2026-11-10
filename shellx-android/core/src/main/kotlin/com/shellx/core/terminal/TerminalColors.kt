package com.shellx.core.terminal

import com.shellx.link.core.TerminalAttribute
import com.shellx.link.core.TerminalCellStyle
import com.shellx.link.core.TerminalPalette
import kotlin.math.roundToInt

/** A colour, each channel 0 to 255. */
data class TerminalRgb(val red: Int, val green: Int, val blue: Int)

/** What a cell is drawn with, once its style is resolved against the palette. */
data class TerminalResolvedStyle(
    val foreground: TerminalRgb,
    /** Null: the default background, which the canvas has painted already. */
    val background: TerminalRgb?,
    val bold: Boolean,
    val italic: Boolean,
    val underline: Boolean,
    val strike: Boolean,
    val overline: Boolean,
    /** False for `invisible`: only the background is drawn. */
    val drawsText: Boolean,
)

/** Styles and the palette of a frame (PROTOCOL.md 11.5) → colours (TerminalColors.swift). */
object TerminalColors {
    private val WHITE = TerminalRgb(255, 255, 255)
    private val BLACK = TerminalRgb(0, 0, 0)

    /** "#rrggbb" in either case; null otherwise. */
    fun rgb(hex: String): TerminalRgb? {
        if (hex.length != 7 || hex[0] != '#') return null
        val channels = IntArray(3)
        for (index in 0 until 3) {
            val high = nibble(hex[1 + 2 * index]) ?: return null
            val low = nibble(hex[2 + 2 * index]) ?: return null
            channels[index] = high shl 4 or low
        }
        return TerminalRgb(channels[0], channels[1], channels[2])
    }

    /** The palette's foreground, else #ffffff. */
    fun foreground(palette: TerminalPalette): TerminalRgb = rgb(palette.fg) ?: WHITE

    /** The palette's background, else #000000. */
    fun background(palette: TerminalPalette): TerminalRgb = rgb(palette.bg) ?: BLACK

    /** The palette's cursor, else the foreground. */
    fun cursor(palette: TerminalPalette): TerminalRgb = palette.cursor?.let(::rgb) ?: foreground(palette)

    /** Inverse swaps with the defaults, faint goes halfway to the background, invisible draws no text. */
    fun resolve(style: TerminalCellStyle, palette: TerminalPalette): TerminalResolvedStyle {
        var foreground = style.fgRgb?.let(::rgb) ?: indexed(style.fg, palette) ?: foreground(palette)
        var background = style.bgRgb?.let(::rgb) ?: indexed(style.bg, palette)
        val attrs = style.attrs
        if (TerminalAttribute.INVERSE in attrs) {
            val swapped = background ?: background(palette)
            background = foreground
            foreground = swapped
        }
        if (TerminalAttribute.FAINT in attrs) foreground = mix(foreground, background ?: background(palette))
        return TerminalResolvedStyle(
            foreground = foreground,
            background = background,
            bold = TerminalAttribute.BOLD in attrs,
            italic = TerminalAttribute.ITALIC in attrs,
            underline = TerminalAttribute.UNDERLINE in attrs,
            strike = TerminalAttribute.STRIKE in attrs,
            overline = TerminalAttribute.OVERLINE in attrs,
            drawsText = TerminalAttribute.INVISIBLE !in attrs,
        )
    }

    private fun indexed(index: Int?, palette: TerminalPalette): TerminalRgb? {
        if (index == null || index !in 0..255 || index !in palette.colors.indices) return null
        return rgb(palette.colors[index])
    }

    /** Each channel halfway between [a] and [b], rounded. */
    private fun mix(a: TerminalRgb, b: TerminalRgb): TerminalRgb {
        fun half(x: Int, y: Int) = ((x + y) / 2.0).roundToInt()
        return TerminalRgb(half(a.red, b.red), half(a.green, b.green), half(a.blue, b.blue))
    }

    private fun nibble(c: Char): Int? = when (c) {
        in '0'..'9' -> c - '0'
        in 'a'..'f' -> c - 'a' + 10
        in 'A'..'F' -> c - 'A' + 10
        else -> null
    }
}
