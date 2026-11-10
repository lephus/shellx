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
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputContentInfo
import android.view.inputmethod.TextAttribute
import androidx.annotation.RequiresApi
import com.shellx.core.terminal.TerminalTextInput
import com.shellx.core.text.dropLastGrapheme
import com.shellx.core.text.graphemes
import com.shellx.core.text.utf8Size
import com.shellx.link.core.ShellXLink
import com.shellx.link.core.TerminalKey

/**
 * The terminal as the keyboard's editor (plan 3G Design, "Soft keyboard", and the Telex ruling of its final fix round;
 * `TerminalSurfaceView+TextInput.swift`). The keyboard's text is the word it committed since the last word boundary
 * (the [shadow], at most [SHADOW_CAP] UTF-16 units) followed by the word being composed ([document], the model's marked
 * text, Telex or VNI, which stays on the phone), with the cursor at the end and nothing after it. The Mac is the only
 * truth: the shadow is a memory of what went out, kept so that a keyboard that rewrites a word it committed (Gboard's
 * Telex and VNI with suggestions off, which composed nothing into an editor that showed it no text; an autocorrection)
 * is translated into backspaces and the new text, and a keyboard that composes sees its composing region after the word.
 * A word boundary clears the shadow: a space, tab or line break in a commit, Enter, a paste, a key that is not text (a
 * named key, a chord, a key bar key), a character taken as a ctrl chord, input sent past the keyboard, the focus lost,
 * a restart (a new connection starts empty). The shadow lives here only: never logged ([toString] gives lengths), never saved.
 *
 * Every call that forwards to [input] first checks [accepts] (the surface's terminal is the one shown, and it takes
 * input): otherwise it is dropped and answers true, so a word the keyboard commits after the page moved never reaches
 * either terminal (Review Focus 1). Text that still holds a line break once one trailing break is set aside, or is longer
 * than one input message, is pasted as one paste under the paste limit, not typed ([isPaste]; Review Focus 2, A-32).
 * Backspace and Enter arrive once whichever way the keyboard sends them (Review Focus 3); a Backspace key event inside a
 * word being composed edits the word here, as deleteSurroundingText does, so the keyboard is not restarted (a restart
 * closes the connection, which commits the word). After each change the connection [report]s the cursor and the
 * composing region, and the text to a keyboard that monitors it ([extracted]); inside a batch edit, once at its end. When
 * the model did not keep what the keyboard sent (a latched ctrl took the first letter), it asks to [restart] the
 * keyboard. Main thread only.
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
    /**
     * The word being composed, as the model keeps it (the surface resyncs it when the model changed it past the
     * keyboard); the keyboard sees it after the word it committed.
     */
    var document: String = input.markedText
        private set

    /** Text the keyboard committed since the last word boundary, as it went to the Mac: whole clusters, at most [SHADOW_CAP] units. */
    private var shadow = ""

    /** The model's input count after this connection's last send: a higher count is input that went out past it. */
    private var inputsSeen = sentInputs()

    /** The token of the keyboard's request to monitor the text (`GET_EXTRACTED_TEXT_MONITOR`), told each change. */
    private var extractToken: Int? = null

    private var batch = 0
    private var changedInBatch = false

    /** The keyboard's text: the word committed, then the word being composed. */
    private val shown: String get() = shadow + document

    /** The model's marked text changed outside the keyboard: take it as the document and restart the keyboard, which starts a new word. */
    fun resync(markedText: String) {
        document = markedText
        shadow = ""
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
        val end = shown.length
        val composing = document.isNotEmpty()
        report(end, if (composing) shadow.length else -1, if (composing) end else -1)
        extractToken?.let { extracted(it, extractedText()) }
    }

    /** Input went out past this connection since it last sent (a key bar key, the long press's Paste, a drag's scroll): the word ended. */
    private fun outsideInput(): Boolean {
        val count = sentInputs()
        if (count == inputsSeen) return false
        inputsSeen = count
        return true
    }

    private inline fun forward(change: () -> Unit): Boolean {
        if (!accepts()) return true
        if (outsideInput()) shadow = ""
        change()
        changed()
        return true
    }

    // The model's calls, each noting the input count after it, so that a send of this connection's own never reads as input from outside.

    private fun insert(text: String) {
        input.insertText(text)
        inputsSeen = sentInputs()
    }

    private fun mark(text: String) {
        input.setMarkedText(text)
        inputsSeen = sentInputs()
    }

    private fun unmark() {
        input.unmarkText()
        inputsSeen = sentInputs()
    }

    /** One backspace to the Mac, or one character less of the word being composed. */
    private fun backspace() {
        input.deleteBackward()
        inputsSeen = sentInputs()
    }

    private fun press(key: TerminalKey) {
        input.press(key)
        inputsSeen = sentInputs()
    }

    private fun paste(text: String) {
        input.paste(text)
        inputsSeen = sentInputs()
    }

    // What the surface did past the keyboard's calls: hardware keys, and the key events the keyboard sends

    /** Input went out past this connection: the word ended, and the keyboard is told. The surface calls it on every render. */
    fun checkOutsideInput() {
        if (outsideInput()) endWord()
    }

    /**
     * The surface typed [text] by a key: the keyboard's word grows as a real editor's would. A word being composed went
     * first and the model dropped it, so the surface's next render resyncs this connection and restarts the keyboard.
     */
    fun typedByKey(text: String) {
        inputsSeen = sentInputs()
        if (document.isNotEmpty()) {
            shadow = ""
            return
        }
        shadow = shadowAfter(shadow + text)
        changed()
    }

    /** The surface sent one backspace by a key (a hardware Backspace, the keyboard's Backspace key event): the word loses a character. */
    fun deletedByKey() {
        inputsSeen = sentInputs()
        if (document.isNotEmpty()) {
            // A hardware Backspace edited the word being composed in the model: the next render resyncs and restarts.
            shadow = ""
            return
        }
        if (shadow.isEmpty()) return
        shadow = shadow.dropLastGrapheme()
        changed()
    }

    /** A key that ends the word went out past the keyboard's calls (a named key, a chord, a paste), or the focus was lost. */
    fun wordEnded() {
        inputsSeen = sentInputs()
        endWord()
    }

    private fun endWord() {
        if (shadow.isEmpty()) return
        shadow = ""
        changed()
    }

    // Composing

    override fun setComposingText(text: CharSequence?, newCursorPosition: Int): Boolean = forward {
        val sent = text?.toString().orEmpty()
        mark(sent)
        document = input.markedText
        // A latched ctrl took the first letter as a chord: the Mac has no word, and the keyboard starts again.
        if (document != sent) {
            shadow = ""
            restart()
        }
    }

    /**
     * A composing region inside the word being composed changes nothing (the whole word stays composed); an empty one
     * is the framework's "nothing is composing", so the word is committed. A region that starts in the word committed
     * (the keyboard composing a word it committed, or its end) takes the characters from there to the end back from the
     * Mac with backspaces and composes them on the phone, before any word already composed; the keyboard's
     * `setComposingText` then replaces them. A region that ends before the text's end still runs to it: committed text
     * cannot follow the word composed at the cursor.
     */
    override fun setComposingRegion(start: Int, end: Int): Boolean {
        if (!accepts()) return true
        val length = shown.length
        val from = minOf(start, end).coerceIn(0, length)
        val to = maxOf(start, end).coerceIn(0, length)
        if (from == to) return finishComposingText()
        if (from >= shadow.length) return true
        return forward {
            val cut = clusterStart(from)
            val taken = shadow.substring(cut)
            val word = taken + document
            // Nothing composed while the backspaces go, or the model would edit the word instead of sending them.
            if (document.isNotEmpty()) mark("")
            repeat(taken.graphemes().size) { backspace() }
            shadow = shadow.substring(0, cut)
            mark(word)
            document = input.markedText
            if (document != word) {
                shadow = ""
                restart()
            }
        }
    }

    override fun finishComposingText(): Boolean = forward {
        val word = document
        unmark()
        document = input.markedText
        shadow = shadowAfter(shadow + word)
    }

    override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean = forward {
        commit(text?.toString().orEmpty())
    }

    /** [text] goes to the Mac (a paste when [isPaste]) and joins the word, or ends it. */
    private fun commit(text: String) {
        if (isPaste(text)) {
            paste(text)
            document = input.markedText
            shadow = ""
            return
        }
        // With nothing composed, a latched ctrl takes the first character as a chord: the Mac has no letter, so the
        // keyboard's word is gone and it starts again.
        val chord = document.isEmpty() && text.isNotEmpty() && ctrlLatched()
        insert(text)
        document = input.markedText
        shadow = if (chord) "" else shadowAfter(shadow + text)
        if (chord) restart()
    }

    /**
     * API 34: the keyboard replaces a range of its text. Inside the word being composed, the word is replaced and
     * committed; a range that starts in the word committed takes the word back from there with backspaces, and the new
     * text goes out followed by what came after the range (the base class would edit its own empty buffer and say it
     * worked).
     */
    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    override fun replaceText(start: Int, end: Int, text: CharSequence, newCursorPosition: Int, textAttribute: TextAttribute?): Boolean {
        if (!accepts()) return true
        val all = shown
        val from = minOf(start, end).coerceIn(0, all.length)
        val to = maxOf(start, end).coerceIn(0, all.length)
        if (from >= shadow.length) {
            val at = shadow.length
            return commitText(document.substring(0, from - at) + text + document.substring(to - at), newCursorPosition)
        }
        return forward {
            val kept = all.substring(to)
            // The word being composed is in the range or in what follows it: it is not on the Mac, so it just goes.
            if (document.isNotEmpty()) {
                mark("")
                document = input.markedText
            }
            val cut = clusterStart(from)
            repeat(shadow.substring(cut).graphemes().size) { backspace() }
            shadow = shadow.substring(0, cut)
            commit(text.toString() + kept)
        }
    }

    /**
     * With nothing composed, the keyboard deletes committed text: one backspace (the Backspace key's unit) per character
     * taken back, counted as the keyboard counts them (UTF-16 units, or code points), whole clusters; one per character
     * asked for beyond the word shown, as a real editor would delete it; and a forward delete (the hardware Delete key's
     * unit) per character after the cursor. At most [SHADOW_CAP] of each. While composing, the word on the phone is
     * edited, one character per call.
     */
    override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean = delete(beforeLength, afterLength) { it.length }

    override fun deleteSurroundingTextInCodePoints(beforeLength: Int, afterLength: Int): Boolean =
        delete(beforeLength, afterLength) { it.codePointCount(0, it.length) }

    private fun delete(before: Int, after: Int, measure: (String) -> Int): Boolean = forward {
        if (document.isNotEmpty()) {
            if (before > 0) backspace()
            document = input.markedText
        } else {
            takeBack(before, measure)
            repeat(after.coerceIn(0, SHADOW_CAP)) { press(TerminalKey.DELETE) }
        }
    }

    /** Backspaces for the last [count] characters of the shadow as [measure] counts them (whole clusters), and one per character beyond it. */
    private fun takeBack(count: Int, measure: (String) -> Int) {
        if (count <= 0) return
        val clusters = shadow.graphemes()
        var dropped = 0
        var measured = 0
        while (measured < count && dropped < clusters.size) {
            measured += measure(clusters[clusters.size - 1 - dropped])
            dropped += 1
        }
        shadow = clusters.subList(0, clusters.size - dropped).joinToString("")
        val beyond = (count - measured).coerceAtLeast(0)
        repeat((dropped + beyond).coerceAtMost(SHADOW_CAP)) { backspace() }
    }

    // Keys and actions

    /** The surface takes the key and tells this connection what it did ([typedByKey], [deletedByKey], [wordEnded]). */
    override fun sendKeyEvent(event: KeyEvent): Boolean {
        if (!accepts()) return true
        val chorded = event.isCtrlPressed || event.isAltPressed || event.isMetaPressed
        if (event.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_DEL && !chorded && document.isNotEmpty()) {
            // Its up goes on to the surface, which takes only the ups of downs it took.
            return forward {
                backspace()
                document = input.markedText
            }
        }
        keys(event)
        return true
    }

    override fun performEditorAction(editorAction: Int): Boolean = forward {
        press(TerminalKey.ENTER)
        document = input.markedText
        shadow = ""
    }

    override fun performContextMenuAction(id: Int): Boolean {
        if (id != android.R.id.paste) return false
        return forward {
            clipboardText()?.let {
                paste(it)
                shadow = ""
            }
            document = input.markedText
        }
    }

    // What the keyboard reads

    override fun getTextBeforeCursor(n: Int, flags: Int): CharSequence = shown.takeLast(maxOf(n, 0))

    override fun getTextAfterCursor(n: Int, flags: Int): CharSequence = ""

    override fun getSelectedText(flags: Int): CharSequence? = null

    /** The editor's inputType has no CAP flag: nothing is capitalised (every word would start a sentence after its space). */
    override fun getCursorCapsMode(reqModes: Int): Int = 0

    override fun getExtractedText(request: ExtractedTextRequest?, flags: Int): ExtractedText {
        if (request != null && flags and InputConnection.GET_EXTRACTED_TEXT_MONITOR != 0) extractToken = request.token
        return extractedText()
    }

    private fun extractedText(): ExtractedText = ExtractedText().apply {
        val all = shown
        text = all
        startOffset = 0
        partialStartOffset = -1
        partialEndOffset = -1
        selectionStart = all.length
        selectionEnd = all.length
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
        shadow = ""
        extractToken = null
        super.closeConnection()
    }

    /** Lengths only: what was typed stays out of logs and crash reports. */
    override fun toString(): String = "TerminalInputConnection(committed=<${shadow.length} chars>, composing=<${document.length} chars>)"

    // The shadow's text

    /** [text] as the shadow keeps it: what follows its last word boundary, cut to [SHADOW_CAP] units at a cluster's start. */
    private fun shadowAfter(text: String): String {
        val start = text.indexOfLast { it.isWhitespace() || it.isISOControl() } + 1
        val tail = text.substring(start)
        if (tail.length <= SHADOW_CAP) return tail
        val clusters = tail.graphemes()
        var drop = 0
        var length = tail.length
        while (length > SHADOW_CAP && drop < clusters.size) {
            length -= clusters[drop].length
            drop += 1
        }
        return clusters.subList(drop, clusters.size).joinToString("")
    }

    /** The start of the shadow's cluster that holds [index] ([index] itself at a cluster's start, or at the end). */
    private fun clusterStart(index: Int): Int {
        var at = 0
        for (cluster in shadow.graphemes()) {
            val next = at + cluster.length
            if (next > index) return at
            at = next
        }
        return at
    }

    companion object {
        /** The most of a word the keyboard is shown, in UTF-16 units: a Vietnamese word is under ten, a shell word rarely over this. */
        const val SHADOW_CAP = 64

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
