package com.shellx.app.ui.terminal

import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.view.View
import android.view.inputmethod.ExtractedText
import android.view.inputmethod.InputMethodManager
import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.staticCompositionLocalOf

/** The keyboard calls the terminal surface makes: [SystemTerminalIme] asks Android's input method; tests record. */
interface TerminalIme {
    fun show(view: View)
    fun hide(view: View)

    /** The keyboard drops what it composes and asks the view for a new connection. */
    fun restart(view: View)

    fun updateSelection(view: View, selStart: Int, selEnd: Int, composingStart: Int, composingEnd: Int)

    /** The editor's text changed while the keyboard monitors it (`getExtractedText` with GET_EXTRACTED_TEXT_MONITOR). */
    fun updateExtractedText(view: View, token: Int, text: ExtractedText)
}

/** [TerminalIme] through [InputMethodManager]. */
class SystemTerminalIme(context: Context) : TerminalIme {
    private val manager: InputMethodManager? = context.getSystemService(InputMethodManager::class.java)

    override fun show(view: View) {
        manager?.showSoftInput(view, 0)
    }

    override fun hide(view: View) {
        manager?.hideSoftInputFromWindow(view.windowToken, 0)
    }

    override fun restart(view: View) {
        manager?.restartInput(view)
    }

    override fun updateSelection(view: View, selStart: Int, selEnd: Int, composingStart: Int, composingEnd: Int) {
        manager?.updateSelection(view, selStart, selEnd, composingStart, composingEnd)
    }

    override fun updateExtractedText(view: View, token: Int, text: ExtractedText) {
        manager?.updateExtractedText(view, token, text)
    }
}

/** The keyboard a terminal pane uses; null (the default) is [SystemTerminalIme]. */
val LocalTerminalIme: ProvidableCompositionLocal<TerminalIme?> = staticCompositionLocalOf { null }

/** The clipboard as Paste reads it. */
object TerminalClipboard {
    /**
     * Whether the clipboard holds text that [text] pastes. Reads only its description, never the text (Android 12 and
     * later say so): text of any kind but a list of URIs or an Intent, which paste nothing. A file that says it is
     * `text/plain` cannot be told apart without reading the clip, so Paste is offered for it and pastes nothing.
     */
    fun hasText(context: Context): Boolean {
        val manager = context.getSystemService(ClipboardManager::class.java) ?: return false
        if (!manager.hasPrimaryClip()) return false
        val types = manager.primaryClipDescription?.filterMimeTypes("text/*") ?: return false
        return types.any { it != ClipDescription.MIMETYPE_TEXT_URILIST && it != ClipDescription.MIMETYPE_TEXT_INTENT }
    }

    /**
     * The clipboard's text, or null when it holds none. An item's own text only (its styled text as plain text): a file
     * on the clipboard (a content URI, even one that says `text/plain`) is never opened, so nothing is read from disk or
     * from another app on the main thread, and an Intent is not text to paste. The iPhone pastes the pasteboard's
     * string, which no file fills either.
     */
    fun text(context: Context): String? {
        val manager = context.getSystemService(ClipboardManager::class.java) ?: return null
        val clip = manager.primaryClip ?: return null
        if (clip.itemCount == 0 || clip.description?.hasMimeType("text/*") != true) return null
        val item = clip.getItemAt(0)
        // coerceToText opens a URI and spells out an Intent; with neither it only turns styled text into plain text.
        if (item.uri != null || item.intent != null) return item.text?.toString()?.takeIf { it.isNotEmpty() }
        return item.coerceToText(context)?.toString()?.takeIf { it.isNotEmpty() }
    }
}
