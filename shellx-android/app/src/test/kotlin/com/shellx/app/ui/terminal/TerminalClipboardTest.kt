package com.shellx.app.ui.terminal

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric

/**
 * The clipboard as Paste reads it (review D1 M1): an item's own text only. A text file shared to the clipboard (a
 * content URI that says `text/plain`) is never opened, so a large log cannot be read whole on the main thread, and an
 * Intent is not text to paste.
 */
@RunWith(AndroidJUnit4::class)
class TerminalClipboardTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val clipboard = context.getSystemService(ClipboardManager::class.java)

    @Test
    fun plainTextIsPasted() {
        clipboard.setPrimaryClip(ClipData.newPlainText("", "echo a"))
        assertTrue(TerminalClipboard.hasText(context))
        assertEquals("echo a", TerminalClipboard.text(context))
    }

    /** A text file shared to the clipboard, served as a provider serves it; [opened] counts the opens. */
    class FilesProvider : ContentProvider() {
        var opened = 0
        lateinit var file: File

        override fun onCreate(): Boolean = true

        override fun getType(uri: Uri): String = "text/plain"

        override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
            opened += 1
            return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        }

        override fun query(uri: Uri, projection: Array<out String>?, selection: String?, args: Array<out String>?, sort: String?): Cursor? = null

        override fun insert(uri: Uri, values: ContentValues?): Uri? = null

        override fun delete(uri: Uri, selection: String?, args: Array<out String>?): Int = 0

        override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<out String>?): Int = 0
    }

    @Test
    fun aFileOnTheClipboardIsNeverRead() {
        val provider = Robolectric.buildContentProvider(FilesProvider::class.java).create("com.example.files").get()
        provider.file = File.createTempFile("big", ".log").apply {
            deleteOnExit()
            writeText("a".repeat(1_000_000))
        }
        val uri = Uri.parse("content://com.example.files/big.log")
        clipboard.setPrimaryClip(ClipData(ClipDescription("big.log", arrayOf("text/plain")), ClipData.Item(uri)))
        assertNull(TerminalClipboard.text(context))
        assertEquals("the file was opened", 0, provider.opened)
    }

    @Test
    fun anIntentIsNotPasted() {
        val item = ClipData.Item(Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com")))
        clipboard.setPrimaryClip(ClipData(ClipDescription("link", arrayOf(ClipDescription.MIMETYPE_TEXT_INTENT)), item))
        assertNull(TerminalClipboard.text(context))
    }
}
