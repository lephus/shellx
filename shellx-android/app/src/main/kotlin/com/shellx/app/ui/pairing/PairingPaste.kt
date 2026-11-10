package com.shellx.app.ui.pairing

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import com.shellx.core.pairing.PairingScanFilter

/** Reads a pasted pairing code (`PairingPaste.swift`). */
object PairingPaste {
    /** The clipboard's text, read once. A pairing code is then cleared from the clipboard: it carries a one-time secret
     *  that should not stay around for other apps. */
    fun take(clipboard: ClipboardManager, context: Context): String {
        val clip = clipboard.primaryClip
        val text = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString() ?: ""
        if (PairingScanFilter.isPairingText(text)) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                clipboard.clearPrimaryClip()
            } else {
                clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
            }
        }
        return text
    }
}
