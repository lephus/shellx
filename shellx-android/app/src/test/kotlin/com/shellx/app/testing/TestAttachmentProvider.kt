package com.shellx.app.testing

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.provider.OpenableColumns
import java.util.concurrent.ConcurrentHashMap

/**
 * A ContentProvider for `content://com.shellx.test.attachments/<name>`: query gives DISPLAY_NAME and SIZE from
 * [entries], getType the entry's MIME type. Register it with `Robolectric.setupContentProvider`; the bytes come from
 * `shadowOf(contentResolver).registerInputStream`.
 */
class TestAttachmentProvider : ContentProvider() {
    companion object {
        val entries: MutableMap<String, Entry> = ConcurrentHashMap()
    }

    data class Entry(val name: String, val size: Long?, val mime: String?)

    override fun onCreate(): Boolean = true

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? {
        val entry = entries[uri.lastPathSegment] ?: return null
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        return MatrixCursor(columns).apply {
            addRow(
                columns.map {
                    when (it) {
                        OpenableColumns.DISPLAY_NAME -> entry.name
                        OpenableColumns.SIZE -> entry.size
                        else -> null
                    }
                },
            )
        }
    }

    override fun getType(uri: Uri): String? = entries[uri.lastPathSegment]?.mime

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
