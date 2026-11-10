package com.shellx.link.core

// The names of a terminal view (PROTOCOL.md section 11; `Messages/TerminalView.swift`). The open enums keep a wire
// value this version does not know as it is, as those of OpenEnums.kt do.

/** How the host answered `terminal.view.open` (PROTOCOL.md 11.1). */
@JvmInline
value class TerminalViewOpenOutcome(val wire: String) {
    companion object {
        val OK = TerminalViewOpenOutcome("ok")
        val NOT_FOUND = TerminalViewOpenOutcome("not_found")
        val REFUSED = TerminalViewOpenOutcome("refused")
        val BUSY = TerminalViewOpenOutcome("busy")
        val FAILED = TerminalViewOpenOutcome("failed")
    }
}

/** Why a `terminal.view.ended` was sent (PROTOCOL.md 11.1). */
@JvmInline
value class TerminalViewEndReason(val wire: String) {
    companion object {
        val GONE = TerminalViewEndReason("gone")
        val REFUSED = TerminalViewEndReason("refused")
        val FAILED = TerminalViewEndReason("failed")
        val NOT_OPEN = TerminalViewEndReason("not_open")
    }
}

/** A modifier of a `key` unit. There is no `cmd`, `super` or `meta`. */
@JvmInline
value class TerminalModifier(val wire: String) {
    companion object {
        val CTRL = TerminalModifier("ctrl")
        val ALT = TerminalModifier("alt")
        val SHIFT = TerminalModifier("shift")
    }
}

/** A key a phone can press in a terminal view (PROTOCOL.md 11.2). */
@JvmInline
value class TerminalKey(val wire: String) {
    /** 'a'..'z' when the wire is one lowercase ASCII letter, else null. */
    val letter: Char?
        get() = wire.singleOrNull()?.takeIf { it in 'a'..'z' }

    /** One of [ALL_KNOWN]. */
    val isKnown: Boolean
        get() = letter != null || wire in NAMED_WIRES

    companion object {
        val ENTER = TerminalKey("enter")
        val TAB = TerminalKey("tab")
        val BACKSPACE = TerminalKey("backspace")
        val ESCAPE = TerminalKey("escape")
        val DELETE = TerminalKey("delete")
        val SPACE = TerminalKey("space")
        val UP = TerminalKey("up")
        val DOWN = TerminalKey("down")
        val LEFT = TerminalKey("left")
        val RIGHT = TerminalKey("right")
        val HOME = TerminalKey("home")
        val END = TerminalKey("end")
        val PAGE_UP = TerminalKey("page_up")
        val PAGE_DOWN = TerminalKey("page_down")

        private val NAMED: List<TerminalKey> =
            listOf(ENTER, TAB, BACKSPACE, ESCAPE, DELETE, SPACE, UP, DOWN, LEFT, RIGHT, HOME, END, PAGE_UP, PAGE_DOWN)
        private val NAMED_WIRES: Set<String> = NAMED.mapTo(HashSet()) { it.wire }

        /** The key of letter [c]. Throws [IllegalArgumentException] unless [c] is in 'a'..'z'. */
        fun letter(c: Char): TerminalKey {
            require(c in 'a'..'z') { "a letter key is one of a to z" }
            return TerminalKey(c.toString())
        }

        /** The 40 names of PROTOCOL.md 11.2 in its order: the 14 named keys, then a … z. */
        val ALL_KNOWN: List<TerminalKey> = NAMED + ('a'..'z').map(::letter)
    }
}

/**
 * One unit of a `terminal.view.input` (PROTOCOL.md 11.2). Its `k` is an open enum: an unknown one decodes to [Other]
 * and its other fields are dropped. Typed and pasted text prints as its size (Global Constraint "Privacy").
 */
sealed interface TerminalInputUnit {
    /** `{"k":"text","text":…}`: committed typing. A line break is never typed: it is `Key(ENTER)`. */
    data class Text(val text: String) : TerminalInputUnit {
        override fun toString(): String = "Text(<${text.utf8Size} bytes>)"
    }

    /** `{"k":"key","key":…,"mods":[…]}`; `mods` is left out when empty. */
    data class Key(val key: TerminalKey, val mods: List<TerminalModifier> = emptyList()) : TerminalInputUnit

    /** `{"k":"paste","text":…}`: may hold tabs and line breaks. */
    data class Paste(val text: String) : TerminalInputUnit {
        override fun toString(): String = "Paste(<${text.utf8Size} bytes>)"
    }

    /** `{"k":"scroll","lines":…}`: positive scrolls toward older output. */
    data class Scroll(val lines: Int) : TerminalInputUnit

    /** A unit of a later version: its other fields are dropped; it encodes as `{"k":kind}`. */
    data class Other(val kind: String) : TerminalInputUnit
}
