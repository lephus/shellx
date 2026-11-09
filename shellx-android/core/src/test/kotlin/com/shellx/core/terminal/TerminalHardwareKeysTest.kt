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
    private fun send(key: TerminalKey, vararg mods: TerminalModifier) = TerminalHardwareAction.Send(key, mods.toList())
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
    @Test fun keyBarOrderAndKeys() {
        assertEquals(listOf("ESCAPE", "TAB", "CTRL", "LEFT", "UP", "DOWN", "RIGHT"), TerminalBarKey.entries.map { it.name })
        assertEquals(listOf(TerminalKey.ESCAPE, TerminalKey.TAB, null, TerminalKey.LEFT, TerminalKey.UP, TerminalKey.DOWN,
            TerminalKey.RIGHT), TerminalBarKey.entries.map { it.key })
    }
}
