package com.shellx.app.ui.terminal

import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.CompletionInfo
import android.view.inputmethod.CorrectionInfo
import android.view.inputmethod.ExtractedText
import android.view.inputmethod.ExtractedTextRequest
import android.view.inputmethod.InputContentInfo
import android.view.inputmethod.TextAttribute
import androidx.annotation.RequiresApi
import com.shellx.core.terminal.TerminalTextInput
import com.shellx.core.text.utf8Size
import com.shellx.link.core.ShellXLink
import com.shellx.link.core.TerminalKey

/**
 * The terminal as the keyboard's editor (plan 3G Design, "Soft keyboard"; `TerminalSurfaceView+TextInput.swift`). The
 * keyboard's document is only the word being composed ([TerminalTextInput.markedText], Telex or VNI), with the cursor at
 * its end, which stays on the phone; committed text went to the Mac and is not kept.
 *
 * Every call that forwards to [input] first checks [accepts] (the surface's terminal is the one shown, and it takes
 * input): otherwise it is dropped and answers true, so a word the keyboard commits after the page moved never reaches
 * either terminal (Review Focus 1). Text that still holds a line break once one trailing break is set aside, or is longer
 * than one input message, is pasted as one paste under the paste limit, not typed ([isPaste]; Review Focus 2, A-32).
 * Backspace and Enter arrive once whichever way the keyboard sends them (Review Focus 3); a Backspace key event inside a
 * word being composed edits the word here, as deleteSurroundingText does, so the keyboard is not restarted (a restart
 * closes the connection, which commits the word). After each change the connection [report]s the document; inside a batch edit, once at its
 * end. When the model did not keep what the keyboard composed (a latched ctrl took the first letter), it asks to
 * [restart] the keyboard. Main thread only.
 */
class TerminalInputConnection(
    view: View,
    private val input: TerminalTextInput,
    private val accepts: () -> Boolean,
    /** Whether the key bar's ctrl is latched: the model then sends the next character as a chord. */
    private val ctrlLatched: () -> Boolean,
    /** The model's count of input messages sent (`TerminalViewState.sentInputs`). */
    private val sentInputs: () -> Int,
    private val keys: (KeyEvent) -> Boolean,
    private val clipboardText: () -> String?,
    /** `InputMethodManager.updateSelection`: the cursor (= the text's length) and the composing region, (-1, -1) when none. */
    private val report: (selection: Int, composingStart: Int, composingEnd: Int) -> Unit,
    /** `InputMethodManager.updateExtractedText`, for a keyboard that asked to monitor the text. */
    private val extracted: (token: Int, text: ExtractedText) -> Unit,
    private val restart: () -> Unit,
) : BaseInputConnection(view, true) {
    /** What the keyboard sees: the word being composed. */
    var document: String = input.markedText
        private set

    private var batch = 0
    private var changedInBatch = false

    /** The model's marked text changed outside the keyboard: take it as the document and restart the keyboard. */
    fun resync(markedText: String) {
        document = markedText
        restart()
    }

    private fun changed() {
        if (batch > 0) {
            changedInBatch = true
        } else {
            reportNow()
        }
    }

    private fun reportNow() {
        val composing = document.isNotEmpty()
        report(document.length, if (composing) 0 else -1, if (composing) document.length else -1)
    }

    private inline fun forward(change: () -> Unit): Boolean {
        if (!accepts()) return true
        change()
        changed()
        return true
    }

    // Composing

    override fun setComposingText(text: CharSequence?, newCursorPosition: Int): Boolean = forward {
        val sent = text?.toString().orEmpty()
        input.setMarkedText(sent)
        document = input.markedText
        if (document != sent) restart()
    }

    override fun setComposingRegion(start: Int, end: Int): Boolean {
        if (!accepts()) return true
        val from = minOf(start, end)
        val to = maxOf(start, end)
        return from >= 0 && to <= document.length && (from < to || document.isEmpty())
    }

    override fun finishComposingText(): Boolean = forward {
        input.unmarkText()
        document = input.markedText
    }

    override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean = forward {
        val sent = text?.toString().orEmpty()
        if (isPaste(sent)) input.paste(sent) else input.insertText(sent)
        document = input.markedText
        // A keyboard keeps its own copy of what it committed, which the document never shows: after a word's space it
        // reads the text before the cursor again (""), so a second space is not taken for a double-space period (". ").
        if (sent.endsWith(' ')) restart()
    }

    /**
     * API 34: a range inside the word being composed is replaced and the word committed; any other range is text the Mac
     * already has, which the phone cannot edit, so [text] is committed after the word.
     */
    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    override fun replaceText(start: Int, end: Int, text: CharSequence, newCursorPosition: Int, textAttribute: TextAttribute?): Boolean {
        if (!accepts()) return true
        val from = minOf(start, end)
        val to = maxOf(start, end)
        if (from >= 0 && to <= document.length) {
            return commitText(document.substring(0, from) + text + document.substring(to), newCursorPosition)
        }
        beginBatchEdit()
        finishComposingText()
        commitText(text, newCursorPosition)
        endBatchEdit()
        return true
    }

    override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean = forward {
        if (beforeLength > 0) input.deleteBackward()
        document = input.markedText
    }

    override fun deleteSurroundingTextInCodePoints(beforeLength: Int, afterLength: Int): Boolean =
        deleteSurroundingText(beforeLength, afterLength)

    // Keys and actions

    override fun sendKeyEvent(event: KeyEvent): Boolean {
        if (!accepts()) return true
        val chorded = event.isCtrlPressed || event.isAltPressed || event.isMetaPressed
        if (event.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_DEL && !chorded && document.isNotEmpty()) {
            // Its up goes on to the surface, which takes only the ups of downs it took.
            input.deleteBackward()
            document = input.markedText
            changed()
            return true
        }
        keys(event)
        return true
    }

    override fun performEditorAction(editorAction: Int): Boolean = forward {
        input.press(TerminalKey.ENTER)
        document = input.markedText
    }

    override fun performContextMenuAction(id: Int): Boolean {
        if (id != android.R.id.paste) return false
        return forward {
            clipboardText()?.let(input::paste)
            document = input.markedText
        }
    }

    // What the keyboard reads

    override fun getTextBeforeCursor(n: Int, flags: Int): CharSequence = document.takeLast(maxOf(n, 0))

    override fun getTextAfterCursor(n: Int, flags: Int): CharSequence = ""

    override fun getSelectedText(flags: Int): CharSequence? = null

    override fun getCursorCapsMode(reqModes: Int): Int = 0

    override fun getExtractedText(request: ExtractedTextRequest?, flags: Int): ExtractedText = ExtractedText().apply {
        text = document
        startOffset = 0
        partialStartOffset = -1
        partialEndOffset = -1
        selectionStart = document.length
        selectionEnd = document.length
    }

    /** The cursor stays at the end of the word. */
    override fun setSelection(start: Int, end: Int): Boolean = true

    override fun beginBatchEdit(): Boolean {
        batch += 1
        return true
    }

    override fun endBatchEdit(): Boolean {
        if (batch > 0) batch -= 1
        if (batch == 0 && changedInBatch) {
            changedInBatch = false
            reportNow()
        }
        return batch > 0
    }

    // What a terminal takes no part in

    override fun commitContent(inputContentInfo: InputContentInfo, flags: Int, opts: Bundle?): Boolean = false

    override fun commitCompletion(text: CompletionInfo?): Boolean = true

    override fun commitCorrection(correctionInfo: CorrectionInfo?): Boolean = true

    override fun requestCursorUpdates(cursorUpdateMode: Int): Boolean = false

    override fun closeConnection() {
        finishComposingText()
        super.closeConnection()
    }

    companion object {
        /**
         * Whether keyboard text goes out as a paste (A-32): it holds a line break once one trailing break (the keyboard's
         * Enter) is set aside, or it is longer than one input message (a long line from the clipboard chip or voice
         * typing), so the paste limit applies and the Mac's 64-message queue never cuts it.
         */
        fun isPaste(text: String): Boolean {
            val body = when {
                text.endsWith("\r\n") -> text.dropLast(2)
                text.endsWith('\n') || text.endsWith('\r') -> text.dropLast(1)
                else -> text
            }
            return '\n' in body || '\r' in body || text.utf8Size > ShellXLink.TERMINAL_MAX_TEXT_BYTES
        }
    }
}
