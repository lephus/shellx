package com.shellx.app.ui.pairing

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/** The paste path of the pairing page (DemoCompositionTests' paste tests). */
@RunWith(AndroidJUnit4::class)
class PairingPasteTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val clipboard = context.getSystemService(ClipboardManager::class.java)

    private fun clipText(): String =
        clipboard.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString() ?: ""

    @Test
    fun aPastedCodeIsReadOnceAndCleared() {
        val code = "shellx-link://pair?v=1&m=m1&s=s1&k=k&c=c&n=Mac\n"
        clipboard.setPrimaryClip(ClipData.newPlainText("", code))

        assertEquals(code, PairingPaste.take(clipboard, context))
        assertEquals("the code is no longer on the clipboard", "", clipText())
    }

    @Test
    fun otherPastedTextIsLeftAlone() {
        clipboard.setPrimaryClip(ClipData.newPlainText("", "a note"))

        assertEquals("a note", PairingPaste.take(clipboard, context))
        assertEquals("a note", clipText())
    }

    @Test
    fun anEmptyClipboardIsEmptyText() {
        assertEquals("", PairingPaste.take(clipboard, context))
    }
}
