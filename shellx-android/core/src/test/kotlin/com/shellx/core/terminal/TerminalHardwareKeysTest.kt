package com.shellx.core.terminal

import com.shellx.link.core.TerminalKey
import com.shellx.link.core.TerminalModifier
import kotlin.test.Test
import kotlin.test.assertEquals

class TerminalHardwareKeysTest {
    private val K = TerminalKeyCodes
    private val ctrl = TerminalHardwareModifiers(ctrl = true); private val alt = TerminalHardwareModifiers(alt = true)
    private val shift = TerminalHardwareModifiers(shift = true); private val meta = TerminalHardwareModifiers(meta = true)
    private fun a(keyCode: Int, plain: Char? = null, altChar: Char? = plain, mods: TerminalHardwareModifiers = TerminalHardwareModifiers()) =
        TerminalHardwareKeys.action(keyCode, plain?.code ?: 0, altChar?.code ?: 0, mods)
    // Kotlin allows no value class as a vararg type (TerminalModifier is one): one overload per count.
    private fun send(key: TerminalKey) = TerminalHardwareAction.Send(key, emptyList())
    private fun send(key: TerminalKey, mod: TerminalModifier) = TerminalHardwareAction.Send(key, listOf(mod))
    private fun send(key: TerminalKey, first: TerminalModifier, second: TerminalModifier) =
        TerminalHardwareAction.Send(key, listOf(first, second))
    private val System = TerminalHardwareAction.System

    @Test fun namedKeysAreSentWithTheirModifiers() {
        assertEquals(send(TerminalKey.ESCAPE), a(K.ESCAPE)); assertEquals(send(TerminalKey.TAB), a(K.TAB, '\t'))
        assertEquals(send(TerminalKey.TAB, TerminalModifier.SHIFT), a(K.TAB, '\t', mods = shift))
        assertEquals(listOf(send(TerminalKey.LEFT), send(TerminalKey.RIGHT), send(TerminalKey.UP), send(TerminalKey.DOWN)),
            listOf(K.DPAD_LEFT, K.DPAD_RIGHT, K.DPAD_UP, K.DPAD_DOWN).map { a(it) })
        assertEquals(send(TerminalKey.LEFT, TerminalModifier.ALT), a(K.DPAD_LEFT, mods = alt))
        assertEquals(send(TerminalKey.UP, TerminalModifier.CTRL, TerminalModifier.SHIFT),
            a(K.DPAD_UP, mods = TerminalHardwareModifiers(ctrl = true, shift = true)))
        assertEquals(listOf(send(TerminalKey.HOME), send(TerminalKey.END), send(TerminalKey.PAGE_UP), send(TerminalKey.PAGE_DOWN),
            send(TerminalKey.DELETE)), listOf(K.MOVE_HOME, K.MOVE_END, K.PAGE_UP, K.PAGE_DOWN, K.FORWARD_DEL).map { a(it) })
    }
    @Test fun ctrlLettersAreKeysByTheLayoutsLetter() {
        assertEquals(send(TerminalKey.letter('c'), TerminalModifier.CTRL), a(31, 'c', mods = ctrl))           // KEYCODE_C
        assertEquals(send(TerminalKey.letter('a'), TerminalModifier.CTRL, TerminalModifier.SHIFT),
            a(29, 'A', mods = TerminalHardwareModifiers(ctrl = true, shift = true)))                               // KEYCODE_A
        assertEquals(send(TerminalKey.letter('a'), TerminalModifier.CTRL), a(45, 'a', mods = ctrl))           // KEYCODE_Q on AZERTY
        assertEquals(System, a(8, '1', mods = ctrl))                                                           // KEYCODE_1
    }
    /** Review B2 I-1 (iPhone parity): on a Russian layout Ctrl+С is ctrl-c, as the iPhone maps the physical key. */
    @Test fun ctrlOnANonLatinLayoutUsesTheKeysLatinLetter() {
        val ctrlShift = TerminalHardwareModifiers(ctrl = true, shift = true)
        assertEquals(send(TerminalKey.letter('c'), TerminalModifier.CTRL), a(31, 'с', mods = ctrl))          // KEYCODE_C
        assertEquals(send(TerminalKey.letter('a'), TerminalModifier.CTRL, TerminalModifier.SHIFT), a(29, 'Ф', mods = ctrlShift))
        assertEquals(TerminalHardwareAction.Paste, a(50, 'М', mods = ctrlShift))                               // KEYCODE_V
        assertEquals(System, a(41, ',', mods = ctrl))                                                          // AZERTY's KEYCODE_M
        assertEquals(System, a(8, '1', mods = ctrl))
    }
    /**
     * Re-review B N-2: a letter key whose layout types a combining mark (Hindi InScript's D is the virama, Thai
     * Kedmanee's U a vowel sign) still chords by the physical key; punctuation on such a key stays System (ruled).
     */
    @Test fun ctrlOnAKeyThatTypesAMarkUsesTheKeysLatinLetter() {
        assertEquals(send(TerminalKey.letter('d'), TerminalModifier.CTRL), a(32, '्', mods = ctrl))     // KEYCODE_D
        assertEquals(send(TerminalKey.letter('u'), TerminalModifier.CTRL), a(49, 'ี', mods = ctrl))     // KEYCODE_U
        assertEquals(send(TerminalKey.letter('x'), TerminalModifier.CTRL), a(52, 'ं', mods = ctrl))     // KEYCODE_X
        assertEquals(System, a(41, ',', mods = ctrl))                                                          // AZERTY's KEYCODE_M
        assertEquals(System, a(45, '/', mods = ctrl))                                                          // Hebrew Q
    }
    @Test fun ctrlVIsTheKeyAndCtrlShiftVPastes() {
        assertEquals(send(TerminalKey.letter('v'), TerminalModifier.CTRL), a(50, 'v', mods = ctrl))           // KEYCODE_V
        assertEquals(TerminalHardwareAction.Paste, a(50, 'V', mods = TerminalHardwareModifiers(ctrl = true, shift = true)))
    }
    @Test fun lettersReturnBackspaceAndSpaceGoThroughTyping() {
        assertEquals(TerminalHardwareAction.Type("c"), a(31, 'c')); assertEquals(TerminalHardwareAction.Type("C"), a(31, 'C', mods = shift))
        assertEquals(TerminalHardwareAction.Type("1"), a(8, '1'))
        assertEquals(TerminalHardwareAction.Type("\n"), a(K.ENTER)); assertEquals(TerminalHardwareAction.Type("\n"), a(K.NUMPAD_ENTER))
        assertEquals(TerminalHardwareAction.DeleteBackward, a(K.DEL)); assertEquals(TerminalHardwareAction.Type(" "), a(K.SPACE, ' '))
    }
    @Test fun returnBackspaceAndSpaceWithModifiersAreKeys() {
        assertEquals(send(TerminalKey.ENTER, TerminalModifier.CTRL), a(K.ENTER, mods = ctrl))
        assertEquals(send(TerminalKey.BACKSPACE, TerminalModifier.ALT), a(K.DEL, mods = alt))
        assertEquals(send(TerminalKey.SPACE, TerminalModifier.CTRL), a(K.SPACE, ' ', mods = ctrl))
    }
    @Test fun altTypesWhatTheLayoutGivesElseNothing() {
        assertEquals(TerminalHardwareAction.Type("å"), a(29, 'a', altChar = 'å', mods = alt))
        assertEquals(System, a(29, 'a', altChar = null, mods = alt))
    }
    @Test fun metaShortcutsFunctionKeysAndBackGoToTheSystem() {
        assertEquals(System, a(31, 'c', mods = meta)); assertEquals(System, a(K.ESCAPE, mods = meta))
        assertEquals(System, a(131)); assertEquals(System, a(4)); assertEquals(System, a(24))                // F1, BACK, VOLUME_UP
    }
    /** Review B2 m6: a dead key the surface did not handle (getUnicodeChar's COMBINING_ACCENT bit) never types. */
    @Test fun anUnhandledDeadKeyNeverTypes() {
        val deadAcute = 0x80000301.toInt()
        assertEquals(System, TerminalHardwareKeys.action(29, deadAcute, 0, TerminalHardwareModifiers()))
        assertEquals(System, TerminalHardwareKeys.action(29, deadAcute, deadAcute, alt))
        assertEquals(System, TerminalHardwareKeys.action(29, deadAcute, 0, ctrl))
    }
    /** Review B2 m7: typed text prints as its UTF-8 size only (the plan's privacy rule, as TerminalInputUnit.Text). */
    @Test fun typedTextPrintsItsSizeOnly() {
        assertEquals("Type(<5 bytes>)", TerminalHardwareAction.Type("été").toString())
    }
    @Test fun keyBarOrderAndKeys() {
        assertEquals(listOf("ESCAPE", "TAB", "CTRL", "LEFT", "UP", "DOWN", "RIGHT"), TerminalBarKey.entries.map { it.name })
        assertEquals(listOf(TerminalKey.ESCAPE, TerminalKey.TAB, null, TerminalKey.LEFT, TerminalKey.UP, TerminalKey.DOWN,
            TerminalKey.RIGHT), TerminalBarKey.entries.map { it.key })
    }
}
