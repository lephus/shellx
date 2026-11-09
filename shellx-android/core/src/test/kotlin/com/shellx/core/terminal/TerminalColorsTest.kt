package com.shellx.core.terminal

import com.shellx.link.core.TerminalAttribute
import com.shellx.link.core.TerminalCellStyle
import com.shellx.link.core.TerminalPalette
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TerminalColorsTest {
    /** fg #d0d0d0, bg #101010, colors[i] = grey i, colors[2] = "#00ff00". */
    private val palette = TerminalPalette(
        "#d0d0d0", "#101010",
        colors = (0 until 256).map { if (it == 2) "#00ff00" else "#%02x%02x%02x".format(it, it, it) },
    )

    @Test fun defaultStyleUsesThePalette() {
        val style = TerminalColors.resolve(TerminalCellStyle.DEFAULT, palette)
        assertEquals(TerminalRgb(0xd0, 0xd0, 0xd0), style.foreground); assertNull(style.background)
        assertTrue(style.drawsText); assertFalse(style.bold)
    }

    @Test fun indexedAndRgbColours() {
        val style = TerminalColors.resolve(TerminalCellStyle(fg = 2, bgRgb = "#336699"), palette)
        assertEquals(TerminalRgb(0, 255, 0), style.foreground)
        assertEquals(TerminalRgb(0x33, 0x66, 0x99), style.background)
    }

    @Test fun inverseSwapsEvenTheDefaults() {
        val style = TerminalColors.resolve(TerminalCellStyle(attrs = listOf(TerminalAttribute.INVERSE)), palette)
        assertEquals(TerminalRgb(0x10, 0x10, 0x10), style.foreground)
        assertEquals(TerminalRgb(0xd0, 0xd0, 0xd0), style.background)
    }

    @Test fun faintBlendsHalfwayToTheBackground() {
        val style = TerminalColors.resolve(
            TerminalCellStyle(fgRgb = "#ffffff", bgRgb = "#000000", attrs = listOf(TerminalAttribute.FAINT)), palette,
        )
        assertEquals(TerminalRgb(128, 128, 128), style.foreground)
    }

    @Test fun invisibleBoldItalicUnderlineStrikeOverline() {
        val attrs = listOf(
            TerminalAttribute.INVISIBLE, TerminalAttribute.BOLD, TerminalAttribute.ITALIC, TerminalAttribute.UNDERLINE,
            TerminalAttribute.STRIKE, TerminalAttribute.OVERLINE, TerminalAttribute.BLINK,
        )
        val style = TerminalColors.resolve(TerminalCellStyle(attrs = attrs), palette)
        assertFalse(style.drawsText)
        assertTrue(style.bold && style.italic && style.underline && style.strike && style.overline)
    }

    @Test fun badColoursFallBack() {
        assertNull(TerminalColors.rgb("#12345")); assertEquals(TerminalRgb(0xab, 0xcd, 0xef), TerminalColors.rgb("#AbCdEf"))
        val broken = TerminalPalette("red", "#101010", colors = palette.colors)
        assertEquals(TerminalRgb(255, 255, 255), TerminalColors.foreground(broken))
        assertEquals(TerminalColors.foreground(palette), TerminalColors.cursor(palette))
    }
}
