package com.shellx.app.ui.terminal

import android.view.View
import android.view.inputmethod.ExtractedText

/** A keyboard that only counts what the surface asks of it. Main thread only. */
class RecordingIme : TerminalIme {
    data class Selection(val selStart: Int, val selEnd: Int, val composingStart: Int, val composingEnd: Int)

    /** What a monitored extracted text said: its token, the text, and the cursor. */
    data class Extracted(val token: Int, val text: String, val selectionEnd: Int)

    var shows = 0
        private set
    var hides = 0
        private set
    var restarts = 0
        private set
    val selections = mutableListOf<Selection>()
    val extracted = mutableListOf<Extracted>()

    override fun show(view: View) {
        shows += 1
    }

    override fun hide(view: View) {
        hides += 1
    }

    override fun restart(view: View) {
        restarts += 1
    }

    override fun updateSelection(view: View, selStart: Int, selEnd: Int, composingStart: Int, composingEnd: Int) {
        selections += Selection(selStart, selEnd, composingStart, composingEnd)
    }

    override fun updateExtractedText(view: View, token: Int, text: ExtractedText) {
        extracted += Extracted(token, text.text.toString(), text.selectionEnd)
    }
}
