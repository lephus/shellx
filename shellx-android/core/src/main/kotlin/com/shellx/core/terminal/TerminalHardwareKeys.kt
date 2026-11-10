package com.shellx.core.terminal

import com.shellx.link.core.TerminalKey
import com.shellx.link.core.TerminalModifier

/** android.view.KeyEvent's values; app-test pins each one against KeyEvent. */
object TerminalKeyCodes {
    /** KEYCODE_A … KEYCODE_Z are A … Z, in the alphabet's order. */
    const val A = 29
    const val Z = 54
    const val DPAD_UP = 19
    const val DPAD_DOWN = 20
    const val DPAD_LEFT = 21
    const val DPAD_RIGHT = 22
    const val TAB = 61
    const val SPACE = 62
    const val ENTER = 66
    const val DEL = 67
    const val PAGE_UP = 92
    const val PAGE_DOWN = 93
    const val ESCAPE = 111
    const val FORWARD_DEL = 112
    const val MOVE_HOME = 122
    const val MOVE_END = 123
    const val NUMPAD_ENTER = 160
}

/** The modifiers held for a hardware key (KeyEvent's meta state). */
data class TerminalHardwareModifiers(
    val shift: Boolean = false,
    val ctrl: Boolean = false,
    val alt: Boolean = false,
    val meta: Boolean = false,
)

/** What a hardware key does in the terminal. */
sealed interface TerminalHardwareAction {
    /** A named key or a ctrl chord, sent as a `key` unit. */
    data class Send(val key: TerminalKey, val mods: List<TerminalModifier>) : TerminalHardwareAction

    /**
     * Text a key types, through `TerminalTextInput.typeKey`: the word being composed is committed first (A-g3), a
     * latched ctrl applies, `"\n"` becomes `enter`.
     */
    data class Type(val text: String) : TerminalHardwareAction {
        override fun toString(): String = "Type(<${text.length} chars>)"
    }

    /** Backspace through the model's typing: it edits the word being composed, or sends one backspace. */
    data object DeleteBackward : TerminalHardwareAction

    /** Ctrl+Shift+V: paste the clipboard. */
    data object Paste : TerminalHardwareAction

    /** Not the terminal's: Back, volume, Meta shortcuts, function keys. */
    data object System : TerminalHardwareAction
}

/** Android hardware keys in the terminal (plan 3G Task 7; the iPhone's `TerminalHardwareKeys` maps UIKeys). */
object TerminalHardwareKeys {
    private val NAMED: Map<Int, TerminalKey> = mapOf(
        TerminalKeyCodes.ESCAPE to TerminalKey.ESCAPE,
        TerminalKeyCodes.TAB to TerminalKey.TAB,
        TerminalKeyCodes.DPAD_UP to TerminalKey.UP,
        TerminalKeyCodes.DPAD_DOWN to TerminalKey.DOWN,
        TerminalKeyCodes.DPAD_LEFT to TerminalKey.LEFT,
        TerminalKeyCodes.DPAD_RIGHT to TerminalKey.RIGHT,
        TerminalKeyCodes.MOVE_HOME to TerminalKey.HOME,
        TerminalKeyCodes.MOVE_END to TerminalKey.END,
        TerminalKeyCodes.PAGE_UP to TerminalKey.PAGE_UP,
        TerminalKeyCodes.PAGE_DOWN to TerminalKey.PAGE_DOWN,
        TerminalKeyCodes.FORWARD_DEL to TerminalKey.DELETE,
    )

    /**
     * plainChar: the layout's character without ctrl, alt and meta (0 when none); altChar: with alt (0 when none).
     *
     * `mods` holds CTRL, ALT, SHIFT in that order, each when pressed. The first rule that matches wins:
     * 1. meta → System.
     * 2. ESCAPE, TAB, the four DPAD arrows, MOVE_HOME, MOVE_END, PAGE_UP, PAGE_DOWN, FORWARD_DEL → Send(named key, mods).
     * 3. ENTER, NUMPAD_ENTER → with ctrl or alt, Send(ENTER, mods); else Type("\n").
     * 4. DEL → with ctrl or alt, Send(BACKSPACE, mods); else DeleteBackward.
     * 5. SPACE with ctrl → Send(SPACE, mods).
     * 6. ctrl, and plainChar an ASCII letter → Paste when shift is held and the letter is v; else Send(the lowercase
     *    letter, mods). When plainChar is a letter of another script (a Russian or Greek layout) and keyCode is one of
     *    KEYCODE_A … KEYCODE_Z, the physical key's Latin letter instead, as the iPhone maps ctrl by the key (review B2
     *    I-1; AZERTY keeps its layout letter, from the first case). Ctrl with any other character → System.
     * 7. alt without ctrl → altChar ≠ 0: Type(altChar); else System.
     * 8. plainChar ≠ 0 → Type(plainChar).
     * 9. Otherwise → System.
     */
    fun action(keyCode: Int, plainChar: Int, altChar: Int, modifiers: TerminalHardwareModifiers): TerminalHardwareAction {
        val mods = buildList {
            if (modifiers.ctrl) add(TerminalModifier.CTRL)
            if (modifiers.alt) add(TerminalModifier.ALT)
            if (modifiers.shift) add(TerminalModifier.SHIFT)
        }
        if (modifiers.meta) return TerminalHardwareAction.System
        NAMED[keyCode]?.let { return TerminalHardwareAction.Send(it, mods) }
        val chorded = modifiers.ctrl || modifiers.alt
        when (keyCode) {
            TerminalKeyCodes.ENTER, TerminalKeyCodes.NUMPAD_ENTER ->
                return if (chorded) TerminalHardwareAction.Send(TerminalKey.ENTER, mods) else TerminalHardwareAction.Type("\n")
            TerminalKeyCodes.DEL ->
                return if (chorded) TerminalHardwareAction.Send(TerminalKey.BACKSPACE, mods) else TerminalHardwareAction.DeleteBackward
            TerminalKeyCodes.SPACE -> if (modifiers.ctrl) return TerminalHardwareAction.Send(TerminalKey.SPACE, mods)
        }
        if (modifiers.ctrl) {
            val letter = ctrlLetter(keyCode, plainChar) ?: return TerminalHardwareAction.System
            return if (modifiers.shift && letter == 'v') {
                TerminalHardwareAction.Paste
            } else {
                TerminalHardwareAction.Send(TerminalKey.letter(letter), mods)
            }
        }
        if (modifiers.alt) return typed(altChar) ?: TerminalHardwareAction.System
        return typed(plainChar) ?: TerminalHardwareAction.System
    }

    /** Rule 6's letter: the layout's ASCII letter, else a key A … Z of a layout whose letters are of another script. */
    private fun ctrlLetter(keyCode: Int, plainChar: Int): Char? {
        if (plainChar in 'a'.code..'z'.code || plainChar in 'A'.code..'Z'.code) return plainChar.toChar().lowercaseChar()
        if (keyCode !in TerminalKeyCodes.A..TerminalKeyCodes.Z) return null
        if (!Character.isValidCodePoint(plainChar) || !Character.isLetter(plainChar)) return null
        return 'a' + (keyCode - TerminalKeyCodes.A)
    }

    /** Type(the character of [codePoint]), or null for 0 or a value that is no character. */
    private fun typed(codePoint: Int): TerminalHardwareAction? {
        if (codePoint == 0 || !Character.isValidCodePoint(codePoint)) return null
        return TerminalHardwareAction.Type(String(Character.toChars(codePoint)))
    }
}

/** The key bar's keys in its order; `key` null for CTRL, which latches for the next key. */
enum class TerminalBarKey(val key: TerminalKey?) {
    ESCAPE(TerminalKey.ESCAPE),
    TAB(TerminalKey.TAB),
    CTRL(null),
    LEFT(TerminalKey.LEFT),
    UP(TerminalKey.UP),
    DOWN(TerminalKey.DOWN),
    RIGHT(TerminalKey.RIGHT),
}
