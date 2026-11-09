package com.shellx.core.terminal

import com.shellx.core.text.dropLastGrapheme
import com.shellx.core.text.graphemes
import com.shellx.link.core.TerminalInputUnit
import com.shellx.link.core.TerminalKey
import com.shellx.link.core.TerminalModifier

/**
 * What the keyboard composes and what it sends (S2 §3.6; plan 2C's TerminalTyping, TerminalTyping.swift). Marked text
 * (an input method's word in progress, Telex or VNI) stays on the phone; only committed text goes out. Ctrl, tapped on
 * the key bar, applies to the next key or letter. Mutable, one owner (the model, on the main thread).
 */
class TerminalTyping(markedText: String = "", ctrlLatched: Boolean = false) {
    var markedText: String = markedText
        private set
    var ctrlLatched: Boolean = ctrlLatched
        private set

    fun toggleCtrl() {
        ctrlLatched = !ctrlLatched
    }

    /** Committed text (`commitText`). Committing the input method's word is never a ctrl chord. */
    fun insert(text: String): List<TerminalInputUnit> {
        // The input method's word becomes this text.
        val committing = markedText.isNotEmpty()
        markedText = ""
        val first = firstCharacter(text)
        if (committing || !ctrlLatched || first == null) return plain(text)
        ctrlLatched = false
        return merged(chord(first) + plain(text.substring(first.length)))
    }

    /** The word in progress (`setComposingText`). Ctrl takes the first letter of a new composition; the surface then resets the keyboard. */
    fun setMarked(text: String): List<TerminalInputUnit> {
        val first = firstCharacter(text)
        if (markedText.isEmpty() && ctrlLatched && first != null) {
            ctrlLatched = false
            return chord(first)
        }
        markedText = text
        return emptyList()
    }

    /** What was composed is committed (`finishComposingText`); committing never takes the ctrl latch. */
    fun unmark(): List<TerminalInputUnit> {
        val units = plain(markedText)
        markedText = ""
        return units
    }

    /** Edits the marked text and, only when there is none, sends backspace. */
    fun deleteBackward(): List<TerminalInputUnit> {
        if (markedText.isNotEmpty()) {
            markedText = markedText.dropLastGrapheme()
            return emptyList()
        }
        return key(TerminalKey.BACKSPACE)
    }

    /** A key bar or hardware key. The word in progress goes first; a latched ctrl joins the key's modifiers. */
    fun key(key: TerminalKey, mods: List<TerminalModifier> = emptyList()): List<TerminalInputUnit> {
        val units = unmark().toMutableList()
        var keyMods = mods
        if (ctrlLatched) {
            ctrlLatched = false
            if (TerminalModifier.CTRL !in keyMods) keyMods = listOf(TerminalModifier.CTRL) + keyMods
        }
        units += TerminalInputUnit.Key(key, keyMods)
        return units
    }

    internal companion object {
        private const val CR = 0x0D
        private const val LF = 0x0A
        private const val TAB = 0x09

        private fun isControl(codePoint: Int): Boolean = codePoint <= 0x1F || codePoint == 0x7F || codePoint in 0x80..0x9F

        /**
         * Swift's `text.first`: a control character (CR LF together) is a character of its own, anything else is the
         * first grapheme. Null for "".
         */
        fun firstCharacter(text: String): String? {
            if (text.isEmpty()) return null
            if (text.startsWith("\r\n")) return "\r\n"
            val codePoint = text.codePointAt(0)
            if (isControl(codePoint)) return String(Character.toChars(codePoint))
            return text.graphemes().first()
        }

        /**
         * Line breaks (`\n`, `\r`, `\r\n`) become `enter`, tabs `tab`; other control characters are dropped; each stretch
         * between keys is one `text` unit.
         */
        fun plain(text: String): List<TerminalInputUnit> {
            val units = ArrayList<TerminalInputUnit>()
            val pending = StringBuilder()
            fun flush() {
                if (pending.isNotEmpty()) {
                    units += TerminalInputUnit.Text(pending.toString())
                    pending.setLength(0)
                }
            }
            var i = 0
            while (i < text.length) {
                val codePoint = text.codePointAt(i)
                i += Character.charCount(codePoint)
                when {
                    codePoint == CR || codePoint == LF -> {
                        if (codePoint == CR && i < text.length && text[i].code == LF) i += 1
                        flush()
                        units += TerminalInputUnit.Key(TerminalKey.ENTER)
                    }
                    codePoint == TAB -> {
                        flush()
                        units += TerminalInputUnit.Key(TerminalKey.TAB)
                    }
                    isControl(codePoint) -> Unit
                    else -> pending.appendCodePoint(codePoint)
                }
            }
            flush()
            return units
        }

        /** One character typed with ctrl: letters, space, a line break and tab become chords; anything else is typed plain. */
        fun chord(character: String): List<TerminalInputUnit> {
            val ctrl = listOf(TerminalModifier.CTRL)
            val single = character.singleOrNull()
            return when {
                single != null && (single in 'a'..'z' || single in 'A'..'Z') ->
                    listOf(TerminalInputUnit.Key(TerminalKey.letter(single.lowercaseChar()), ctrl))
                character == " " -> listOf(TerminalInputUnit.Key(TerminalKey.SPACE, ctrl))
                character == "\n" || character == "\r" || character == "\r\n" ->
                    listOf(TerminalInputUnit.Key(TerminalKey.ENTER, ctrl))
                character == "\t" -> listOf(TerminalInputUnit.Key(TerminalKey.TAB, ctrl))
                else -> plain(character)
            }
        }

        /** Adjacent `text` units joined, so a chord that fell back to plain text does not split a stretch. */
        private fun merged(units: List<TerminalInputUnit>): List<TerminalInputUnit> {
            val result = ArrayList<TerminalInputUnit>(units.size)
            for (unit in units) {
                val previous = result.lastOrNull()
                if (unit is TerminalInputUnit.Text && previous is TerminalInputUnit.Text) {
                    result[result.size - 1] = TerminalInputUnit.Text(previous.text + unit.text)
                } else {
                    result += unit
                }
            }
            return result
        }
    }
}
