package com.shellx.app.ui.terminal

import android.content.ClipDescription
import android.content.Context
import android.net.Uri
import android.text.TextUtils
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.ExtractedTextRequest
import android.view.inputmethod.InputContentInfo
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.terminal.TerminalTextInput
import com.shellx.core.terminal.TerminalTyping
import com.shellx.link.core.TerminalInputUnit
import com.shellx.link.core.TerminalInputUnit.Key
import com.shellx.link.core.TerminalInputUnit.Paste
import com.shellx.link.core.TerminalInputUnit.Text
import com.shellx.link.core.TerminalKey
import com.shellx.link.core.TerminalModifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The keyboard's side of the terminal (plan 3G Design, "Soft keyboard"): the document is only the word being composed,
 * which stays on the phone; commits, Backspace and Enter reach the model once each whichever way the keyboard sends
 * them; nothing reaches it once the surface's terminal is no longer the one shown (Review Focus 1–3).
 */
@RunWith(AndroidJUnit4::class)
class TerminalInputConnectionTest {
    /** A real TerminalTyping, recording the units each call makes (a paste is its own unit). */
    private class TypingRecorder : TerminalTextInput {
        private val typing = TerminalTyping()
        val units = mutableListOf<TerminalInputUnit>()
        override val markedText: String get() = typing.markedText
        override fun insertText(text: String) { units += typing.insert(text) }
        override fun setMarkedText(text: String) { units += typing.setMarked(text) }
        override fun unmarkText() { units += typing.unmark() }
        override fun deleteBackward() { units += typing.deleteBackward() }
        override fun typeKey(text: String) { units += typing.typeKey(text) }
        override fun press(key: TerminalKey, mods: List<TerminalModifier>) { units += typing.key(key, mods) }
        override fun paste(text: String) { units += Paste(text) }
        fun toggleCtrl() = typing.toggleCtrl()
        val ctrlLatched: Boolean get() = typing.ctrlLatched
    }

    /** A selection the connection reported: the cursor and the composing region (-1, -1 when none). */
    private data class Reported(val selection: Int, val composingStart: Int, val composingEnd: Int)

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val recorder = TypingRecorder()
    private val reports = mutableListOf<Reported>()
    private val extracts = mutableListOf<Pair<Int, String>>()
    private var restarts = 0
    private val keyEvents = mutableListOf<KeyEvent>()

    private fun connection(accepts: () -> Boolean = { true }) = TerminalInputConnection(
        view = View(context),
        input = recorder,
        accepts = accepts,
        ctrlLatched = { recorder.ctrlLatched },
        sentInputs = { recorder.units.size },
        keys = { keyEvents += it; true },
        clipboardText = { null },
        report = { selection, composingStart, composingEnd -> reports += Reported(selection, composingStart, composingEnd) },
        extracted = { token, text -> extracts += token to text.text.toString() },
        restart = { restarts += 1 },
    )

    /**
     * The emulator check (Gboard 15.1, API 36, English): with nothing composed Gboard commits letter by letter and keeps
     * its own copy of the text ("ls "), which our document never shows; a second quick space then arrives as
     * `finishComposingText` + `commitText(". ")`, and the Mac got "ls . ". A commit that ends with a space restarts the
     * keyboard, so it reads the text before the cursor again (""), and a second space is a space (controller ruling).
     */
    @Test
    fun aCommitEndingWithASpaceRestartsTheKeyboard() {
        val c = connection()
        c.commitText("l", 1)
        c.commitText("s", 1)
        assertEquals(0, restarts)
        c.commitText(" ", 1)
        assertEquals(1, restarts)
        c.setComposingText("vi", 1)
        c.commitText("việt ", 1)
        assertEquals(2, restarts)
        assertEquals(listOf(Text("l"), Text("s"), Text(" "), Text("việt ")), recorder.units)
    }

    @Test
    fun composingStaysLocalAndACommitSendsTheWord() {
        val c = connection()
        c.setComposingText("v", 1)
        c.setComposingText("vi", 1)
        c.setComposingText("việ", 1)
        assertEquals(emptyList<TerminalInputUnit>(), recorder.units)
        assertEquals("việ", c.document)
        c.commitText("việt", 1)
        assertEquals(listOf(Text("việt")), recorder.units)
        assertEquals("", c.document)
    }

    @Test
    fun finishingTheCompositionSendsIt() {
        val c = connection()
        c.setComposingText("Tiế", 1)
        c.finishComposingText()
        assertEquals(listOf(Text("Tiế")), recorder.units)
    }

    @Test
    fun backspaceWhileComposingEditsTheWordOnThePhone() { // Review Focus 3
        val c = connection()
        c.setComposingText("việ", 1)
        c.setComposingText("vi", 1)
        assertEquals(emptyList<TerminalInputUnit>(), recorder.units)
        c.deleteSurroundingText(1, 0)
        assertEquals(emptyList<TerminalInputUnit>(), recorder.units)
        assertEquals("v", c.document)
    }

    @Test
    fun backspaceWithNothingComposedSendsOneBackspacePerCall() { // Review Focus 3
        val c = connection()
        c.deleteSurroundingText(1, 0)
        c.deleteSurroundingText(2, 0)
        c.deleteSurroundingTextInCodePoints(1, 0)
        assertEquals(List(3) { Key(TerminalKey.BACKSPACE) }, recorder.units)
        c.deleteSurroundingText(0, 1)
        assertEquals(3, recorder.units.size)
    }

    @Test
    fun enterArrivesOnceWhicheverWayTheKeyboardSendsIt() { // Review Focus 3
        val c = connection()
        c.commitText("\n", 1)
        assertEquals(listOf(Key(TerminalKey.ENTER)), recorder.units)
        c.performEditorAction(EditorInfo.IME_ACTION_UNSPECIFIED)
        assertEquals(listOf(Key(TerminalKey.ENTER), Key(TerminalKey.ENTER)), recorder.units)
        val enter = KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER)
        c.sendKeyEvent(enter)
        assertEquals(listOf(enter), keyEvents)
        assertEquals("the key event is the surface's to type", 2, recorder.units.size)
    }

    @Test
    fun aMultiLineCommitIsPastedNotTyped() { // Review Focus 2
        val c = connection()
        c.commitText("echo a\necho b", 1)
        assertEquals(listOf(Paste("echo a\necho b")), recorder.units)
        c.commitText("ls\n", 1)
        assertEquals(listOf(Paste("echo a\necho b"), Text("ls"), Key(TerminalKey.ENTER)), recorder.units)
    }

    @Test
    fun aCommitAfterTheTerminalChangedIsDropped() { // Review Focus 1
        val c = connection(accepts = { false })
        assertTrue(c.setComposingText("viê", 1))
        assertTrue(c.commitText("việt", 1))
        assertTrue(c.finishComposingText())
        assertTrue(c.deleteSurroundingText(1, 0))
        assertEquals(emptyList<TerminalInputUnit>(), recorder.units)
    }

    @Test
    fun theKeyboardSeesOnlyTheComposingText() {
        val c = connection()
        assertEquals("", c.getTextBeforeCursor(100, 0).toString())
        assertEquals("", c.getExtractedText(ExtractedTextRequest(), 0).text.toString())
        c.setComposingText("viê", 1)
        assertEquals("viê", c.getTextBeforeCursor(100, 0).toString())
        assertEquals("ê", c.getTextBeforeCursor(1, 0).toString())
        assertEquals("", c.getTextAfterCursor(9, 0).toString())
        assertNull(c.getSelectedText(0))
        assertEquals(0, c.getCursorCapsMode(TextUtils.CAP_MODE_SENTENCES))
    }

    @Test
    fun theSelectionIsReportedAfterEachChangeAndOnceForABatch() {
        val c = connection()
        c.setComposingText("vi", 1)
        assertEquals(Reported(2, 0, 2), reports.last())
        val before = reports.size
        c.beginBatchEdit()
        c.setComposingText("v", 1)
        c.setComposingText("vi", 1)
        c.endBatchEdit()
        assertEquals(before + 1, reports.size)
        assertEquals(Reported(2, 0, 2), reports.last())
    }

    @Test
    fun whenTheModelDoesNotKeepWhatTheKeyboardComposedItRestarts() {
        val c = connection()
        recorder.toggleCtrl()
        c.setComposingText("c", 1)
        assertEquals(listOf(Key(TerminalKey.letter('c'), listOf(TerminalModifier.CTRL))), recorder.units)
        assertEquals("", c.document)
        assertEquals(1, restarts)
    }

    @Test
    fun closingTheConnectionCommitsTheWord() {
        val c = connection()
        c.setComposingText("viê", 1)
        c.closeConnection()
        assertEquals(listOf(Text("viê")), recorder.units)
    }

    @Test
    fun aComposingRegionOutsideTheWordIsRefused() {
        val c = connection()
        assertFalse(c.setComposingRegion(0, 5))
        c.setComposingText("vi", 1)
        assertTrue(c.setComposingRegion(0, 2))
        assertEquals("vi", c.document)
    }

    @Test
    fun imagesFromTheKeyboardAreRefused() {
        val c = connection()
        val image = InputContentInfo(Uri.parse("content://x"), ClipDescription("i", arrayOf("image/png")))
        assertFalse(c.commitContent(image, 0, null))
    }
}
