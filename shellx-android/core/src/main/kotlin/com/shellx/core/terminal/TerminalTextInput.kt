package com.shellx.core.terminal

import com.shellx.link.core.TerminalKey
import com.shellx.link.core.TerminalModifier

/** The keyboard's calls in the iPhone's words (marked text = Android's composing text). TerminalViewModel implements it. */
interface TerminalTextInput {
    /** The word the input method is composing: drawn at the cursor, never sent. */
    val markedText: String

    /** Committed text (`commitText`): it goes to the Mac, a line break as `enter`. */
    fun insertText(text: String)

    /** The input method's word in progress (`setComposingText`). */
    fun setMarkedText(text: String)

    /** The word in progress is committed (`finishComposingText`). */
    fun unmarkText()

    /** Edits the word in progress, or sends one backspace when there is none. */
    fun deleteBackward()

    /**
     * Text a key event types (TerminalHardwareAction.Type, and a soft keyboard's key events): the word in progress
     * goes first, then [text] as committed text (`TerminalTyping.typeKey`, sent as one message). Not [insertText],
     * which replaces the word as Android's `commitText` does.
     */
    fun typeKey(text: String)

    /** A key bar or hardware key; the word in progress goes first. */
    fun press(key: TerminalKey, mods: List<TerminalModifier> = emptyList())

    /** Pasted text, sent as one paste. */
    fun paste(text: String)
}
