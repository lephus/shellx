package com.shellx.core.terminal

import com.shellx.link.core.TerminalInputUnit.Key
import com.shellx.link.core.TerminalInputUnit.Text
import com.shellx.link.core.TerminalKey
import com.shellx.link.core.TerminalModifier
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TerminalTypingTest {
    private val ctrl = listOf(TerminalModifier.CTRL)

    @Test fun committedTextIsSentAndMarkedTextIsNot() {
        val typing = TerminalTyping()
        assertEquals(emptyList(), typing.setMarked("v")); assertEquals(emptyList(), typing.setMarked("vi"))
        assertEquals(emptyList(), typing.setMarked("việ"))
        assertEquals("việ", typing.markedText)
        assertEquals(listOf(Text("việt")), typing.insert("việt"))
        assertEquals("", typing.markedText)
    }

    @Test fun unmarkCommitsWhatWasComposed() {
        val typing = TerminalTyping()
        typing.setMarked("Tiế")
        assertEquals(listOf(Text("Tiế")), typing.unmark()); assertEquals(emptyList(), typing.unmark())
    }

    @Test fun backspaceWhileComposingStaysOnThePhone() {
        val typing = TerminalTyping()
        typing.setMarked("việ")
        assertEquals(emptyList(), typing.deleteBackward()); assertEquals("vi", typing.markedText)
        typing.setMarked("")
        assertEquals(listOf(Key(TerminalKey.BACKSPACE)), typing.deleteBackward())
    }

    @Test fun lineBreaksAndTabsAreKeys() {
        val typing = TerminalTyping()
        assertEquals(listOf(Text("ls"), Key(TerminalKey.ENTER)), typing.insert("ls\n"))
        assertEquals(
            listOf(Text("a"), Key(TerminalKey.ENTER), Text("b"), Key(TerminalKey.TAB), Text("c")),
            typing.insert("a\r\nb\tc"),
        )
        assertEquals(listOf(Key(TerminalKey.ENTER)), typing.insert("\r"))
    }

    @Test fun otherControlCharactersAreDropped() {
        val typing = TerminalTyping()
        assertEquals(listOf(Text("a[31mb")), typing.insert("a\u001b[31mb\u007f\u0085"))
        assertEquals(emptyList(), typing.insert("\u001b"))
    }

    @Test fun ctrlLatchesForTheNextKeyOnly() {
        val typing = TerminalTyping()
        typing.toggleCtrl(); assertTrue(typing.ctrlLatched)
        assertEquals(listOf(Key(TerminalKey.letter('c'), ctrl)), typing.insert("c")); assertFalse(typing.ctrlLatched)
        assertEquals(listOf(Text("c")), typing.insert("c"))
        typing.toggleCtrl(); typing.toggleCtrl(); assertFalse(typing.ctrlLatched)
    }

    @Test fun ctrlWithAnUppercaseLetterSpaceOrReturn() {
        val typing = TerminalTyping()
        typing.toggleCtrl(); assertEquals(listOf(Key(TerminalKey.letter('c'), ctrl)), typing.insert("C"))
        typing.toggleCtrl(); assertEquals(listOf(Key(TerminalKey.SPACE, ctrl)), typing.insert(" "))
        typing.toggleCtrl(); assertEquals(listOf(Key(TerminalKey.ENTER, ctrl)), typing.insert("\n"))
    }

    @Test fun ctrlWithAnyOtherCharacterTypesItPlain() {
        val typing = TerminalTyping()
        typing.toggleCtrl(); assertEquals(listOf(Text("1x")), typing.insert("1x")); assertFalse(typing.ctrlLatched)
        typing.toggleCtrl(); assertEquals(listOf(Text("đ")), typing.insert("đ"))
    }

    @Test fun ctrlAppliesToTheKeyBarAndHardwareKeys() {
        val typing = TerminalTyping()
        typing.toggleCtrl(); assertEquals(listOf(Key(TerminalKey.LEFT, ctrl)), typing.key(TerminalKey.LEFT))
        assertEquals(listOf(Key(TerminalKey.LEFT)), typing.key(TerminalKey.LEFT))
        typing.toggleCtrl()
        assertEquals(listOf(Key(TerminalKey.letter('c'), ctrl)), typing.key(TerminalKey.letter('c'), ctrl))
    }

    @Test fun ctrlLatchedTakesTheFirstLetterOfANewComposition() {
        val typing = TerminalTyping()
        typing.toggleCtrl()
        assertEquals(listOf(Key(TerminalKey.letter('c'), ctrl)), typing.setMarked("c"))
        assertEquals("", typing.markedText); assertFalse(typing.ctrlLatched)
    }

    /** Review Focus 2 of plan 2C. */
    @Test fun ctrlTappedWhileComposingWaitsForTheNextKey() {
        val typing = TerminalTyping()
        typing.setMarked("việ"); typing.toggleCtrl()
        assertEquals(emptyList(), typing.setMarked("việt")); assertEquals("việt", typing.markedText)
        assertEquals(listOf(Text("việt")), typing.unmark()); assertTrue(typing.ctrlLatched)
        assertEquals(listOf(Key(TerminalKey.letter('c'), ctrl)), typing.key(TerminalKey.letter('c')))
        typing.setMarked("viê"); typing.toggleCtrl()
        assertEquals(listOf(Text("việt")), typing.insert("việt"), "committing a word is never a ctrl chord")
        assertTrue(typing.ctrlLatched)
    }

    /**
     * Review B2 I-2 (plan 3G A-g3): a key event that carries text (Enter, a digit, a hardware letter) commits the word
     * being composed first, as a named key does; a latched ctrl applies to the key's letter, not to the word.
     */
    @Test fun aKeyEventWhileComposingCommitsTheWordFirst() {
        val typing = TerminalTyping()
        typing.setMarked("việ")
        assertEquals(listOf(Text("việ"), Key(TerminalKey.ENTER)), typing.typeKey("\n"))
        assertEquals("", typing.markedText)
        typing.setMarked("việ")
        assertEquals(listOf(Text("việ"), Text("1")), typing.typeKey("1"))
        typing.setMarked("việ"); typing.toggleCtrl()
        assertEquals(listOf(Text("việ"), Key(TerminalKey.letter('c'), ctrl)), typing.typeKey("c"))
        assertFalse(typing.ctrlLatched)
        assertEquals(listOf(Text("x")), typing.typeKey("x"))
    }

    /** Review Focus 2 of plan 2C. */
    @Test fun aKeyWhileComposingCommitsTheWordFirst() {
        val typing = TerminalTyping()
        typing.setMarked("việ")
        assertEquals(listOf(Text("việ"), Key(TerminalKey.LEFT)), typing.key(TerminalKey.LEFT))
        assertEquals("", typing.markedText)
    }
}
