package com.shellx.app.ui.terminal

import android.view.KeyEvent
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.terminal.TerminalKeyCodes
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/** `:core` cannot see android.view.KeyEvent: its copies of the key codes are pinned here. */
@RunWith(AndroidJUnit4::class)
class TerminalKeyCodesTest {
    @Test
    fun eachKeyCodeIsAndroids() {
        assertEquals(KeyEvent.KEYCODE_A, TerminalKeyCodes.A)
        assertEquals(KeyEvent.KEYCODE_Z, TerminalKeyCodes.Z)
        assertEquals(KeyEvent.KEYCODE_DPAD_UP, TerminalKeyCodes.DPAD_UP)
        assertEquals(KeyEvent.KEYCODE_DPAD_DOWN, TerminalKeyCodes.DPAD_DOWN)
        assertEquals(KeyEvent.KEYCODE_DPAD_LEFT, TerminalKeyCodes.DPAD_LEFT)
        assertEquals(KeyEvent.KEYCODE_DPAD_RIGHT, TerminalKeyCodes.DPAD_RIGHT)
        assertEquals(KeyEvent.KEYCODE_TAB, TerminalKeyCodes.TAB)
        assertEquals(KeyEvent.KEYCODE_SPACE, TerminalKeyCodes.SPACE)
        assertEquals(KeyEvent.KEYCODE_ENTER, TerminalKeyCodes.ENTER)
        assertEquals(KeyEvent.KEYCODE_DEL, TerminalKeyCodes.DEL)
        assertEquals(KeyEvent.KEYCODE_PAGE_UP, TerminalKeyCodes.PAGE_UP)
        assertEquals(KeyEvent.KEYCODE_PAGE_DOWN, TerminalKeyCodes.PAGE_DOWN)
        assertEquals(KeyEvent.KEYCODE_ESCAPE, TerminalKeyCodes.ESCAPE)
        assertEquals(KeyEvent.KEYCODE_FORWARD_DEL, TerminalKeyCodes.FORWARD_DEL)
        assertEquals(KeyEvent.KEYCODE_MOVE_HOME, TerminalKeyCodes.MOVE_HOME)
        assertEquals(KeyEvent.KEYCODE_MOVE_END, TerminalKeyCodes.MOVE_END)
        assertEquals(KeyEvent.KEYCODE_NUMPAD_ENTER, TerminalKeyCodes.NUMPAD_ENTER)
    }
}
