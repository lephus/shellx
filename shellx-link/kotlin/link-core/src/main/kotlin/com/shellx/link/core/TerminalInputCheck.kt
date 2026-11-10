package com.shellx.link.core

/**
 * A `terminal.view.input` that breaks a rule of PROTOCOL.md 11.2. [reason] is a fixed English phrase and never quotes
 * the units.
 */
data class TerminalInputException(val reason: String) : Exception(reason)

/** The input rules of PROTOCOL.md 11.2, shared by the client (before sending) and a host (before applying). */
object TerminalInputCheck {
    /**
     * Throws [TerminalInputException] when [units] break a rule, checked in 2A's order. Sizes count UTF-8 bytes, summed
     * over the message's units. [TerminalInputUnit.Other] units, unknown keys and unknown modifiers pass.
     */
    fun check(units: List<TerminalInputUnit>) {
        if (units.size !in 1..ShellXLink.TERMINAL_MAX_INPUT_UNITS) fail("an input message carries 1 to 64 units")
        var typedBytes = 0
        var pastedBytes = 0
        for (unit in units) {
            when (unit) {
                is TerminalInputUnit.Text -> {
                    if (unit.text.isEmpty()) fail("text is empty")
                    if (unit.text.hasScalar(::isControl)) fail("text holds a control character")
                    typedBytes += unit.text.utf8Size
                    if (typedBytes > ShellXLink.TERMINAL_MAX_TEXT_BYTES) fail("typed text is over 4096 bytes")
                }
                is TerminalInputUnit.Paste -> {
                    if (unit.text.isEmpty()) fail("pasted text is empty")
                    if (unit.text.hasScalar { isControl(it) && it !in PASTE_ALLOWED }) fail("pasted text holds a control character")
                    pastedBytes += unit.text.utf8Size
                    if (pastedBytes > ShellXLink.TERMINAL_MAX_PASTE_BYTES) fail("pasted text is over 16384 bytes")
                }
                // No abs(): abs(Int.MIN_VALUE) is negative.
                is TerminalInputUnit.Scroll -> if (unit.lines == 0 || unit.lines > ShellXLink.TERMINAL_MAX_SCROLL_LINES ||
                    unit.lines < -ShellXLink.TERMINAL_MAX_SCROLL_LINES
                ) {
                    fail("scroll lines must be 1 to 100 either way")
                }
                is TerminalInputUnit.Key -> {
                    val seen = HashSet<String>()
                    for (mod in unit.mods) if (!seen.add(mod.wire)) fail("a modifier is repeated")
                }
                is TerminalInputUnit.Other -> Unit
            }
        }
    }

    /** Tab, line feed and carriage return. */
    private val PASTE_ALLOWED = setOf(0x09, 0x0A, 0x0D)

    private fun fail(reason: String): Nothing = throw TerminalInputException(reason)

    /** C0, DEL and C1. */
    private fun isControl(scalar: Int): Boolean = scalar <= 0x1F || scalar == 0x7F || scalar in 0x80..0x9F

    /** Whether a Unicode scalar (code point) of this string matches [test]. */
    private inline fun String.hasScalar(test: (Int) -> Boolean): Boolean {
        var i = 0
        while (i < length) {
            val c = codePointAt(i)
            if (test(c)) return true
            i += Character.charCount(c)
        }
        return false
    }
}
