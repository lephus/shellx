package com.shellx.core.terminal

import com.shellx.core.text.graphemes
import com.shellx.core.text.utf8Size
import com.shellx.link.core.ShellXLink
import com.shellx.link.core.TerminalInputUnit
import kotlin.math.abs

/** Turns input units into `terminal.view.input` messages within plan 2A's limits (PROTOCOL.md 11.2; TerminalInputBatcher.swift). */
object TerminalInputBatcher {
    /**
     * The largest paste the phone sends: 16 messages of 16 384 bytes. The host keeps at most 64 queued input messages
     * (plan 2A), so a longer paste could silently lose its tail; R12 refuses it instead and the pane shows
     * `terminal_paste_too_large`.
     */
    const val MAX_PASTE_BYTES = 262_144

    /**
     * [units] as `terminal.view.input` messages, in order. Every message passes `TerminalInputCheck.check`: 1 to 64
     * units, typed text at most 4 096 UTF-8 bytes in all, pasted text at most 16 384; a longer `text` or `paste` unit is
     * cut into pieces at grapheme boundaries (a grapheme longer than the limit at code point boundaries).
     */
    fun messages(units: List<TerminalInputUnit>): List<List<TerminalInputUnit>> {
        val messages = ArrayList<List<TerminalInputUnit>>()
        var current = ArrayList<TerminalInputUnit>()
        var typedBytes = 0
        var pastedBytes = 0

        fun add(unit: TerminalInputUnit, typed: Int, pasted: Int) {
            if (current.size == ShellXLink.TERMINAL_MAX_INPUT_UNITS ||
                typedBytes + typed > ShellXLink.TERMINAL_MAX_TEXT_BYTES ||
                pastedBytes + pasted > ShellXLink.TERMINAL_MAX_PASTE_BYTES
            ) {
                messages += current
                current = ArrayList()
                typedBytes = 0
                pastedBytes = 0
            }
            current += unit
            typedBytes += typed
            pastedBytes += pasted
        }

        for (unit in units) {
            when (unit) {
                is TerminalInputUnit.Text -> for (piece in pieces(unit.text, ShellXLink.TERMINAL_MAX_TEXT_BYTES)) {
                    add(TerminalInputUnit.Text(piece), typed = piece.utf8Size, pasted = 0)
                }
                is TerminalInputUnit.Paste -> for (piece in pieces(unit.text, ShellXLink.TERMINAL_MAX_PASTE_BYTES)) {
                    add(TerminalInputUnit.Paste(piece), typed = 0, pasted = piece.utf8Size)
                }
                else -> add(unit, typed = 0, pasted = 0)
            }
        }
        if (current.isNotEmpty()) messages += current
        return messages
    }

    /** Pasted text as one `paste` unit, every control character but tab, line feed and carriage return dropped; none when nothing is left. */
    fun pasteUnits(text: String): List<TerminalInputUnit> {
        val cleaned = cleanPaste(text)
        return if (cleaned.isEmpty()) emptyList() else listOf(TerminalInputUnit.Paste(cleaned))
    }

    /** True when the cleaned paste (as pasteUnits would send it) is at most MAX_PASTE_BYTES UTF-8 bytes. */
    fun pasteFits(text: String): Boolean = cleanPaste(text).utf8Size <= MAX_PASTE_BYTES

    /** A scroll of [lines] (either sign) as units of at most 100 lines each, in the same direction; none for 0. */
    fun scrollUnits(lines: Int): List<TerminalInputUnit> {
        val step = ShellXLink.TERMINAL_MAX_SCROLL_LINES.toLong()
        val sign = if (lines < 0) -1 else 1
        var left = abs(lines.toLong())
        val units = ArrayList<TerminalInputUnit>()
        while (left > 0) {
            val part = minOf(left, step)
            units += TerminalInputUnit.Scroll(sign * part.toInt())
            left -= part
        }
        return units
    }

    private fun cleanPaste(text: String): String {
        val out = StringBuilder(text.length)
        var i = 0
        while (i < text.length) {
            val v = text.codePointAt(i)
            i += Character.charCount(v)
            val control = v <= 0x1F || v == 0x7F || v in 0x80..0x9F
            if (!control || v == 0x09 || v == 0x0A || v == 0x0D) out.appendCodePoint(v)
        }
        return out.toString()
    }

    /**
     * [text] cut into non-empty pieces of at most [maxBytes] UTF-8 bytes at grapheme boundaries; a grapheme longer than
     * [maxBytes] is cut at code point boundaries.
     */
    private fun pieces(text: String, maxBytes: Int): List<String> {
        if (text.isEmpty()) return emptyList()
        if (text.utf8Size <= maxBytes) return listOf(text)
        val result = ArrayList<String>()
        val piece = StringBuilder()
        var pieceBytes = 0
        fun flush() {
            if (piece.isNotEmpty()) {
                result += piece.toString()
                piece.setLength(0)
                pieceBytes = 0
            }
        }
        for (character in text.graphemes()) {
            val bytes = character.utf8Size
            if (bytes > maxBytes) {
                flush()
                val scalars = StringBuilder()
                var scalarBytes = 0
                var i = 0
                while (i < character.length) {
                    val codePoint = character.codePointAt(i)
                    i += Character.charCount(codePoint)
                    val size = String(Character.toChars(codePoint)).utf8Size
                    if (scalarBytes + size > maxBytes && scalars.isNotEmpty()) {
                        result += scalars.toString()
                        scalars.setLength(0)
                        scalarBytes = 0
                    }
                    scalars.appendCodePoint(codePoint)
                    scalarBytes += size
                }
                if (scalars.isNotEmpty()) result += scalars.toString()
                continue
            }
            if (pieceBytes + bytes > maxBytes) flush()
            piece.append(character)
            pieceBytes += bytes
        }
        flush()
        return result
    }
}
