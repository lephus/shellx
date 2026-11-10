package com.shellx.app.ui.terminal

import android.content.ClipDescription
import android.content.Context
import android.net.Uri
import android.text.TextUtils
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.ExtractedTextRequest
import android.view.inputmethod.InputConnection
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
 * The keyboard's side of the terminal (plan 3G Design, "Soft keyboard"; the Telex ruling): the keyboard sees the word it
 * committed since the last word boundary (the shadow) and the word being composed, which stays on the phone; a rewrite
 * of committed text (Telex, VNI, an autocorrection) becomes backspaces and the new text, so the Mac's line reads as the
 * keyboard's; commits, Backspace and Enter reach the model once each whichever way the keyboard sends them; nothing
 * reaches it once the surface's terminal is no longer the one shown (Review Focus 1–3).
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

    private fun connection(accepts: () -> Boolean = { true }, clipboard: String? = null) = TerminalInputConnection(
        view = View(context),
        input = recorder,
        accepts = accepts,
        ctrlLatched = { recorder.ctrlLatched },
        sentInputs = { recorder.units.size },
        keys = { keyEvents += it; true },
        clipboardText = { clipboard },
        report = { selection, composingStart, composingEnd -> reports += Reported(selection, composingStart, composingEnd) },
        extracted = { token, text -> extracts += token to text.text.toString() },
        restart = { restarts += 1 },
    )

    /** What the keyboard reads before the cursor. */
    private fun TerminalInputConnection.sees(): String = getTextBeforeCursor(1000, 0).toString()

    /** Letters committed one by one, as Gboard types them with nothing composed. */
    private fun TerminalInputConnection.type(letters: String) {
        for (letter in letters) commitText(letter.toString(), 1)
    }

    /** Gboard's rewrite of the last [before] characters into [text], inside its batch edit. */
    private fun TerminalInputConnection.rewrite(before: Int, text: String) {
        beginBatchEdit()
        deleteSurroundingText(before, 0)
        commitText(text, 1)
        endBatchEdit()
    }

    // The word the keyboard sees (the Telex ruling)

    /**
     * The emulator checks (Gboard 15.1, API 36): Gboard commits letter by letter and keeps its own copy of the text; with
     * an editor that showed it nothing it took a second quick space for a double-space period (". "). It now reads the
     * word it committed, and after the space it reads "" again, so a second space is a space and the Mac gets `ls  x`.
     */
    @Test
    fun aSpaceEndsTheWordTheKeyboardSees() {
        val c = connection()
        c.type("ls")
        assertEquals("ls", c.sees())
        assertEquals(Reported(2, -1, -1), reports.last())
        c.commitText(" ", 1)
        assertEquals("", c.sees())
        assertEquals(Reported(0, -1, -1), reports.last())
        c.commitText(" ", 1)
        c.commitText("x", 1)
        assertEquals("x", c.sees())
        assertEquals("ls  x", macLine(recorder.units))
        c.setComposingText("vi", 1)
        c.commitText("việt ", 1)
        assertEquals("", c.sees())
        assertEquals("ls  xviệt ", macLine(recorder.units))
    }

    /**
     * The Telex rewrite as Gboard sends it to an editor that shows its text: `tie` + `e` is `deleteSurroundingText(1)` +
     * `commitText("ê")`, and `tiêng` + `s` is `deleteSurroundingText(3)` + `commitText("ếng")`. The Mac's line reads
     * `tiếng`, one backspace per character taken back.
     */
    @Test
    fun telexRewritesByDeleteAndCommitReachTheMacAsTheWord() {
        val c = connection()
        c.type("tie")
        c.rewrite(1, "ê")
        assertEquals("tiê", c.sees())
        c.type("ng")
        c.rewrite(3, "ếng")
        assertEquals("tiếng", c.sees())
        assertEquals(Reported(5, -1, -1), reports.last())
        val backspace = Key(TerminalKey.BACKSPACE)
        assertEquals(
            listOf(Text("t"), Text("i"), Text("e"), backspace, Text("ê"), Text("n"), Text("g"), backspace, backspace, backspace, Text("ếng")),
            recorder.units,
        )
        assertEquals("tiếng", macLine(recorder.units))
    }

    /**
     * The rewrite through a composing region: the keyboard marks `e` of `tie` as composing, then composes `ê` and commits
     * it. The Mac takes the marked characters back and the phone composes them, so what follows is a plain composition.
     */
    @Test
    fun telexRewritesByAComposingRegionReachTheMacAsTheWord() {
        val c = connection()
        c.type("tie")
        assertTrue(c.setComposingRegion(2, 3))
        assertEquals("tie", c.sees())
        assertEquals(Reported(3, 2, 3), reports.last())
        assertEquals(listOf(Text("t"), Text("i"), Text("e"), Key(TerminalKey.BACKSPACE)), recorder.units)
        c.setComposingText("ê", 1)
        c.commitText("ê", 1)
        assertEquals("tiê", c.sees())
        c.type("ng")
        assertTrue(c.setComposingRegion(2, 5))
        c.setComposingText("ếng", 1)
        assertEquals("tiếng", c.sees())
        assertEquals(Reported(5, 2, 5), reports.last())
        c.finishComposingText()
        assertEquals("tiếng", c.sees())
        assertEquals(Reported(5, -1, -1), reports.last())
        assertEquals("tiếng", macLine(recorder.units))
    }

    /** VNI: `tie` + `6` rewrites `e` to `ê`, then `1` rewrites `ê` to `ế`. */
    @Test
    fun vniRewritesReachTheMacAsTheWord() {
        val c = connection()
        c.type("tie")
        c.rewrite(1, "ê")
        c.rewrite(1, "ế")
        c.type("ng")
        assertEquals("tiếng", c.sees())
        assertEquals("tiếng", macLine(recorder.units))
    }

    /**
     * An autocorrection (`grpe` + space → `deleteSurroundingText(4)` + `commitText("grape ")`), seen on the emulator with
     * suggestions on: four backspaces and the word. NO_SUGGESTIONS keeps Gboard from sending it, but the translation holds.
     */
    @Test
    fun anAutocorrectionIsTranslatedFaithfully() {
        val c = connection()
        c.type("grpe")
        c.rewrite(4, "grape ")
        val backspace = Key(TerminalKey.BACKSPACE)
        assertEquals(listOf(Text("g"), Text("r"), Text("p"), Text("e"), backspace, backspace, backspace, backspace, Text("grape ")), recorder.units)
        assertEquals("grape ", macLine(recorder.units))
        assertEquals("", c.sees())
    }

    /** Deletes count what the keyboard counts (UTF-16 units, or code points), and send one backspace per character. */
    @Test
    fun deletesSendOneBackspacePerCharacterTakenBack() {
        val c = connection()
        c.commitText("a👍🏽", 1)
        c.deleteSurroundingText(4, 0)
        assertEquals("one backspace for a four-unit emoji", listOf(Text("a👍🏽"), Key(TerminalKey.BACKSPACE)), recorder.units)
        assertEquals("a", c.sees())
        c.commitText("bc", 1)
        c.deleteSurroundingTextInCodePoints(2, 0)
        assertEquals(List(3) { Key(TerminalKey.BACKSPACE) }, recorder.units.filterIsInstance<Key>())
        assertEquals("a", c.sees())
        // Beyond what the keyboard was shown: one per unit asked for, as a real editor would delete them.
        c.deleteSurroundingText(3, 0)
        assertEquals(List(6) { Key(TerminalKey.BACKSPACE) }, recorder.units.filterIsInstance<Key>())
        assertEquals("", c.sees())
    }

    @Test
    fun backspacesWithNothingComposedSendOnePerCharacterDeleted() { // Review Focus 3
        val c = connection()
        c.deleteSurroundingText(1, 0)
        c.deleteSurroundingText(2, 0)
        c.deleteSurroundingTextInCodePoints(1, 0)
        assertEquals(List(4) { Key(TerminalKey.BACKSPACE) }, recorder.units)
        // After the cursor: the hardware Delete key's unit.
        c.deleteSurroundingText(0, 1)
        assertEquals(Key(TerminalKey.DELETE), recorder.units.last())
        c.commitText("a", 1)
        c.deleteSurroundingText(1, 1)
        assertEquals(listOf(Text("a"), Key(TerminalKey.BACKSPACE), Key(TerminalKey.DELETE)), recorder.units.takeLast(3))
    }

    /**
     * The shadow keeps about a word (32 UTF-16 units; re-review M-4: a rewrite of all of it is then 32 backspace messages
     * and the text, inside the host's 64-message input queue), whole characters only.
     */
    @Test
    fun theWordTheKeyboardSeesIsCapped() {
        val c = connection()
        c.type("a".repeat(40))
        assertEquals("a".repeat(32), c.sees())
        assertEquals(Reported(32, -1, -1), reports.last())
        c.commitText(" ", 1)
        c.commitText("b".repeat(100), 1)
        assertEquals("b".repeat(32), c.sees())
        c.commitText(" ", 1)
        c.commitText("x" + "👍🏽".repeat(8), 1)
        assertEquals("never half an emoji", "👍🏽".repeat(8), c.sees())
        c.commitText("👍🏽", 1)
        assertEquals("👍🏽".repeat(8), c.sees())
    }

    /**
     * API 31+: Gboard reads the text around the cursor through getSurroundingText (the emulator's logcat, right after
     * its start of input), which BaseInputConnection answers from its own empty editable unless overridden: it must say
     * what every other read and the reported selection say (re-review I-1).
     */
    @Test
    fun theKeyboardReadsTheSameTextThroughGetSurroundingText() {
        val c = connection()
        c.type("ti")
        c.setComposingText("ê", 1)
        val around = checkNotNull(c.getSurroundingText(100, 100, 0))
        assertEquals("tiê", around.text.toString())
        assertEquals(3, around.selectionStart)
        assertEquals(3, around.selectionEnd)
        assertEquals(0, around.offset)
        val last = checkNotNull(c.getSurroundingText(1, 0, 0))
        assertEquals("ê", last.text.toString())
        assertEquals(2, last.offset)
        assertEquals(1, last.selectionStart)
        assertEquals(1, last.selectionEnd)
        assertEquals(c.getTextBeforeCursor(100, 0).toString(), around.text.toString())
        assertEquals(reports.last().selection, around.selectionEnd)
    }

    /** Every read (and the snapshot) says the same as the last report: after a commit, a composing change, inside a batch, and on a new connection. */
    private fun TerminalInputConnection.assertReadsAgree(text: String, composing: IntRange?, reported: Boolean = true) {
        val end = text.length
        assertEquals(text, getTextBeforeCursor(1000, 0).toString())
        assertEquals("", getTextAfterCursor(1000, 0).toString())
        val around = checkNotNull(getSurroundingText(1000, 1000, 0))
        assertEquals(text, around.text.toString())
        assertEquals(end, around.selectionStart)
        assertEquals(end, around.selectionEnd)
        assertEquals(0, around.offset)
        val extracted = getExtractedText(ExtractedTextRequest(), 0)
        assertEquals(text, extracted.text.toString())
        assertEquals(end, extracted.selectionStart)
        assertEquals(end, extracted.selectionEnd)
        val snapshot = checkNotNull(takeSnapshot())
        assertEquals(text, snapshot.surroundingText.text.toString())
        assertEquals(end, snapshot.surroundingText.selectionEnd)
        assertEquals(composing?.first ?: -1, snapshot.compositionStart)
        assertEquals(composing?.let { it.last + 1 } ?: -1, snapshot.compositionEnd)
        assertEquals(0, snapshot.cursorCapsMode)
        if (reported) assertEquals(Reported(end, composing?.first ?: -1, composing?.let { it.last + 1 } ?: -1), reports.last())
    }

    @Test
    fun everyReadAgreesWithTheReportedSelection() {
        val c = connection()
        c.type("ab")
        c.assertReadsAgree("ab", composing = null)
        c.setComposingText("c", 1)
        c.assertReadsAgree("abc", composing = 2..2)
        c.setComposingText("cd", 1)
        c.assertReadsAgree("abcd", composing = 2..3)
        // Inside a batch the reads are live while the report waits for its end.
        val before = reports.size
        c.beginBatchEdit()
        c.commitText("x", 1)
        c.assertReadsAgree("abx", composing = null, reported = false)
        assertEquals(before, reports.size)
        c.endBatchEdit()
        c.assertReadsAgree("abx", composing = null)
        // A new connection (a restart) starts a new word, keeping the word being composed; nothing is reported until a change.
        c.setComposingText("e", 1)
        val restarted = connection()
        restarted.assertReadsAgree("e", composing = 0..0, reported = false)
        restarted.commitText("e ", 1)
        restarted.assertReadsAgree("", composing = null)
    }

    /**
     * Pinned deviations (re-review M-5): a region that ends before the text's end runs to the end (committed text cannot
     * follow the word composed at the cursor), and a region inside the word being composed leaves the whole word
     * composed. A change here must be deliberate.
     */
    @Test
    fun aComposingRegionEndingBeforeTheEndRunsToIt() {
        val c = connection()
        c.type("tie")
        assertTrue(c.setComposingRegion(0, 1))
        assertEquals(Reported(3, 0, 3), reports.last())
        assertEquals("tie", c.sees())
        assertEquals("tie", c.document)
        assertEquals(List(3) { Key(TerminalKey.BACKSPACE) }, recorder.units.takeLast(3))
        c.setComposingText("tiê", 1)
        assertEquals("tiê", c.sees())
        assertTrue(c.setComposingRegion(0, 1))
        assertEquals("inside the word, nothing changes", Reported(3, 0, 3), reports.last())
        assertEquals("tiê", c.document)
        assertEquals(3, recorder.units.count { it is Key })
    }

    /** Enter, a paste and a line break end the word: the keyboard reads "" after them. */
    @Test
    fun enterAndAPasteEndTheWordTheKeyboardSees() {
        val c = connection(clipboard = "pasted")
        c.type("ls")
        c.commitText("\n", 1)
        assertEquals("", c.sees())
        c.type("ls")
        c.performEditorAction(EditorInfo.IME_ACTION_UNSPECIFIED)
        assertEquals("", c.sees())
        c.type("ls")
        assertTrue(c.performContextMenuAction(android.R.id.paste))
        assertEquals("", c.sees())
        c.type("ls")
        c.commitText("echo a\necho b", 1)
        assertEquals("", c.sees())
        c.commitText("a b", 1)
        assertEquals("b", c.sees())
        c.commitText("c\td", 1)
        assertEquals("d", c.sees())
    }

    /** Input the model sent past this connection (a key bar key, the long press's Paste) ended the word before the next call. */
    @Test
    fun inputSentPastTheConnectionEndsTheWord() {
        val c = connection()
        c.type("ti")
        recorder.units += Key(TerminalKey.LEFT)
        c.commitText("e", 1)
        assertEquals("e", c.sees())
        assertEquals(Reported(1, -1, -1), reports.last())
    }

    /** A latched ctrl takes the committed character as a chord: the Mac has no letter, so the keyboard forgets it too. */
    @Test
    fun aCharacterTakenAsAChordRestartsTheKeyboard() {
        val c = connection()
        c.type("a")
        recorder.toggleCtrl()
        c.commitText("c", 1)
        assertEquals(listOf(Text("a"), Key(TerminalKey.letter('c'), listOf(TerminalModifier.CTRL))), recorder.units)
        assertEquals("", c.sees())
        assertEquals(1, restarts)
    }

    /** `getExtractedText` with the monitor flag: every change is told under the request's token. */
    @Test
    fun aKeyboardThatMonitorsTheTextIsToldEachChange() {
        val c = connection()
        val request = ExtractedTextRequest().apply { token = 7 }
        assertEquals("", c.getExtractedText(request, InputConnection.GET_EXTRACTED_TEXT_MONITOR).text.toString())
        c.commitText("a", 1)
        assertEquals(7 to "a", extracts.last())
        c.setComposingText("b", 1)
        assertEquals(7 to "ab", extracts.last())
        val before = extracts.size
        c.beginBatchEdit()
        c.setComposingText("bc", 1)
        c.finishComposingText()
        c.endBatchEdit()
        assertEquals(before + 1, extracts.size)
        assertEquals(7 to "abc", extracts.last())
    }

    /** An empty composing region is the framework's "nothing is composing": the word is committed. */
    @Test
    fun anEmptyComposingRegionCommitsTheWord() {
        val c = connection()
        c.setComposingText("vi", 1)
        assertTrue(c.setComposingRegion(2, 2))
        assertEquals(listOf(Text("vi")), recorder.units)
        assertEquals("vi", c.sees())
        assertEquals(Reported(2, -1, -1), reports.last())
        c.commitText("t", 1)
        assertEquals("vit", macLine(recorder.units))
    }

    @Test
    fun toStringHidesTheWord() {
        val c = connection()
        c.type("secret")
        c.setComposingText("wordd", 1)
        val string = c.toString()
        assertFalse(string, string.contains("secret") || string.contains("wordd"))
        assertTrue(string, string.contains("6") && string.contains("5"))
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

    /** The keyboard reads the word it committed and the word being composed, the cursor at the end, nothing after it. */
    @Test
    fun theKeyboardSeesTheWordCommittedAndTheWordBeingComposed() {
        val c = connection()
        assertEquals("", c.getTextBeforeCursor(100, 0).toString())
        assertEquals("", c.getExtractedText(ExtractedTextRequest(), 0).text.toString())
        c.type("ti")
        assertEquals("ti", c.getTextBeforeCursor(100, 0).toString())
        assertEquals("i", c.getTextBeforeCursor(1, 0).toString())
        c.setComposingText("ê", 1)
        assertEquals("tiê", c.getTextBeforeCursor(100, 0).toString())
        assertEquals("ê", c.getTextBeforeCursor(1, 0).toString())
        assertEquals("", c.getTextAfterCursor(9, 0).toString())
        assertNull(c.getSelectedText(0))
        // The editor's inputType has no CAP flag: nothing is capitalised, and every word would otherwise start a sentence.
        assertEquals(0, c.getCursorCapsMode(TextUtils.CAP_MODE_SENTENCES))
        val extracted = c.getExtractedText(ExtractedTextRequest(), 0)
        assertEquals("tiê", extracted.text.toString())
        assertEquals(3, extracted.selectionStart)
        assertEquals(3, extracted.selectionEnd)
        assertEquals(0, extracted.startOffset)
    }

    /** The cursor is the text's length; the composing region is the word being composed, after the word committed. */
    @Test
    fun theSelectionIsReportedAfterEachChangeAndOnceForABatch() {
        val c = connection()
        c.commitText("a", 1)
        assertEquals(Reported(1, -1, -1), reports.last())
        c.setComposingText("vi", 1)
        assertEquals(Reported(3, 1, 3), reports.last())
        val before = reports.size
        c.beginBatchEdit()
        c.setComposingText("v", 1)
        c.setComposingText("vi", 1)
        c.endBatchEdit()
        assertEquals(before + 1, reports.size)
        assertEquals(Reported(3, 1, 3), reports.last())
        c.finishComposingText()
        assertEquals(Reported(3, -1, -1), reports.last())
        c.deleteSurroundingText(1, 0)
        assertEquals(Reported(2, -1, -1), reports.last())
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

    /** A composing region inside the word being composed changes nothing: the whole word stays composed. */
    @Test
    fun aComposingRegionInsideTheWordLeavesIt() {
        val c = connection()
        c.type("ab")
        c.setComposingText("vi", 1)
        assertTrue(c.setComposingRegion(2, 4))
        assertTrue(c.setComposingRegion(3, 4))
        assertEquals("vi", c.document)
        assertEquals(listOf(Text("a"), Text("b")), recorder.units)
        assertEquals("abvi", c.sees())
    }

    @Test
    fun imagesFromTheKeyboardAreRefused() {
        val c = connection()
        val image = InputContentInfo(Uri.parse("content://x"), ClipDescription("i", arrayOf("image/png")))
        assertFalse(c.commitContent(image, 0, null))
    }
}
