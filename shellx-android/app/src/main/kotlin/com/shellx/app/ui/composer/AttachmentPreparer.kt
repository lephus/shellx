package com.shellx.app.ui.composer

import android.content.ContentResolver
import android.content.res.Resources
import android.graphics.Bitmap
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.staticCompositionLocalOf
import com.shellx.app.R
import com.shellx.core.composer.AttachmentChecks
import com.shellx.core.composer.AttachmentPick
import com.shellx.core.composer.AttachmentReadException
import com.shellx.core.composer.AttachmentReader
import com.shellx.core.composer.OutgoingAttachment
import com.shellx.core.platform.CoreLog
import com.shellx.link.core.AttachmentKind
import com.shellx.link.core.ShellXLink
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.nio.ByteBuffer
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

/**
 * 3C's [AttachmentReader] over a [ContentResolver] (`AttachmentPreparer.swift`): turns a picked photo or file into an
 * [OutgoingAttachment], off the main thread and cancellable between chunks.
 *
 * - A file keeps its display name; a photo is named `photo-<n>.<type>` after the names already taken.
 * - A size the provider reports over the limit is refused before reading; a stream of unknown size is read at most
 *   [ShellXLink.MAX_ATTACHMENT_BYTES] plus one chunk, never whole (RF 2).
 * - A HEIC/HEIF photo is sent as JPEG, as the iPhone's photo picker hands it over (ruling 2026-11-09, ledger A-9), at
 *   most [HEIF_MAX_EDGE] px on its long side; a phone that cannot decode it (before API 28) sends it as picked.
 *
 * Never logs a name or bytes.
 */
class AttachmentPreparer(
    private val resolver: ContentResolver,
    private val io: CoroutineDispatcher,
    /** HEIC/HEIF bytes as JPEG; null when the phone cannot decode them. */
    private val heifToJpeg: (ByteArray) -> ByteArray? = ::systemHeifToJpeg,
) : AttachmentReader {
    override suspend fun read(pick: AttachmentPick, taken: List<String>): OutgoingAttachment = withContext(io) {
        val uri = Uri.parse(pick.uri)
        val (displayName, size) = describe(uri)
        val photo = pick.kind == AttachmentKind.IMAGE
        val mime = if (photo) typeOf(uri) else null
        val heif = photo && mime in HEIF_TYPES
        val name = when {
            heif -> AttachmentChecks.photoName("jpg", taken)
            photo -> AttachmentChecks.photoName(AttachmentChecks.photoExtension(mime), taken)
            else -> displayName ?: uri.lastPathSegment ?: "file"
        }
        // A HEIF's size says nothing about its JPEG's: only its read is bounded.
        if (!heif) AttachmentChecks.refuseIfTooLarge(name, size)
        val bytes = readBounded(uri, name, size)
        if (!heif) return@withContext AttachmentChecks.checked(pick.kind, name, bytes)
        val jpeg = if (bytes.isEmpty()) null else heifToJpeg(bytes)
        if (jpeg != null) {
            AttachmentChecks.checked(pick.kind, name, jpeg)
        } else {
            AttachmentChecks.checked(pick.kind, AttachmentChecks.photoName(AttachmentChecks.photoExtension(mime), taken), bytes)
        }
    }

    /** The display name and size the provider reports; null for what it does not say (or a URI it does not serve). */
    private fun describe(uri: Uri): Pair<String?, Long?> = try {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null to null
            val nameColumn = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val sizeColumn = cursor.getColumnIndex(OpenableColumns.SIZE)
            val name = if (nameColumn >= 0 && !cursor.isNull(nameColumn)) cursor.getString(nameColumn) else null
            val size = if (sizeColumn >= 0 && !cursor.isNull(sizeColumn)) cursor.getLong(sizeColumn) else null
            name?.takeIf { it.isNotBlank() } to size
        } ?: (null to null)
    } catch (e: RuntimeException) {
        CoreLog.log("attach_query_failed ${e.javaClass.simpleName}")
        null to null
    }

    private fun typeOf(uri: Uri): String? = try {
        resolver.getType(uri)
    } catch (e: RuntimeException) {
        null
    }

    /** The whole stream, read [CHUNK_BYTES] at a time; [AttachmentReadException.TooLarge] as soon as it passes the
     *  limit, [AttachmentReadException.Unreadable] when it cannot be opened or read. */
    private suspend fun readBounded(uri: Uri, name: String, size: Long?): ByteArray {
        val limit = ShellXLink.MAX_ATTACHMENT_BYTES.toLong()
        try {
            val input: InputStream = resolver.openInputStream(uri) ?: throw AttachmentReadException.Unreadable(name)
            input.use { stream ->
                val out = ByteArrayOutputStream(size?.coerceIn(0, limit)?.toInt() ?: CHUNK_BYTES)
                val chunk = ByteArray(CHUNK_BYTES)
                var total = 0L
                while (true) {
                    currentCoroutineContext().ensureActive()
                    val read = stream.read(chunk)
                    if (read < 0) break
                    total += read
                    if (total > limit) throw AttachmentReadException.TooLarge(name)
                    out.write(chunk, 0, read)
                }
                return out.toByteArray()
            }
        } catch (e: IOException) {
            CoreLog.log("attach_file_unreadable ${e.javaClass.simpleName}")
            throw AttachmentReadException.Unreadable(name)
        } catch (e: SecurityException) {
            CoreLog.log("attach_file_unreadable ${e.javaClass.simpleName}")
            throw AttachmentReadException.Unreadable(name)
        }
    }

    companion object {
        const val CHUNK_BYTES = 65_536

        private val HEIF_TYPES = setOf("image/heic", "image/heif", "image/heic-sequence", "image/heif-sequence")

        /** The red line under the composer for [failure]. */
        fun message(failure: AttachmentReadException, res: Resources): String = when (failure) {
            is AttachmentReadException.TooLarge -> res.getString(R.string.composer_attach_too_large, failure.name)
            is AttachmentReadException.Unreadable -> res.getString(R.string.composer_attach_unreadable, failure.name)
        }

        /** The longest side a converted photo keeps: about 12 MP at 4:3, so a 50–108 MP HEIC never decodes whole
         *  (review A M-3). */
        const val HEIF_MAX_EDGE = 4096

        /** The size [width] × [height] decodes to: the same shape with the long side at most [HEIF_MAX_EDGE], each side
         *  at least 1 px; unchanged when it already fits. */
        fun decodedSize(width: Int, height: Int): Pair<Int, Int> {
            val long = maxOf(width, height)
            if (long <= HEIF_MAX_EDGE) return width to height
            val scale = HEIF_MAX_EDGE.toDouble() / long
            return (width * scale).roundToInt().coerceIn(1, HEIF_MAX_EDGE) to (height * scale).roundToInt().coerceIn(1, HEIF_MAX_EDGE)
        }

        /** Decodes HEIC/HEIF bytes (API 28+, turned upright by their orientation) at most [HEIF_MAX_EDGE] px on the
         *  long side, in sRGB, and encodes them as JPEG at quality 90; null when the phone cannot. Called off the main
         *  thread (the preparer's `io`). */
        fun systemHeifToJpeg(data: ByteArray): ByteArray? {
            if (Build.VERSION.SDK_INT < 28) return null
            return try {
                val bitmap = ImageDecoder.decodeBitmap(ImageDecoder.createSource(ByteBuffer.wrap(data))) { decoder, info, _ ->
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    // The size is the upright one: ImageDecoder applies the orientation, the target size included.
                    val (width, height) = decodedSize(info.size.width, info.size.height)
                    if (width != info.size.width || height != info.size.height) decoder.setTargetSize(width, height)
                    decoder.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB))
                }
                try {
                    ByteArrayOutputStream().use { out ->
                        if (!bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)) return null
                        out.toByteArray()
                    }
                } finally {
                    bitmap.recycle()
                }
            } catch (e: IOException) {
                CoreLog.log("attach_heif_not_converted ${e.javaClass.simpleName}")
                null
            } catch (e: RuntimeException) {
                CoreLog.log("attach_heif_not_converted ${e.javaClass.simpleName}")
                null
            } catch (e: OutOfMemoryError) {
                CoreLog.log("attach_heif_not_converted OutOfMemoryError")
                null
            }
        }

        private const val JPEG_QUALITY = 90
    }
}

/** The reader the composer uses; null → `AttachmentPreparer(LocalContext.current.contentResolver, Dispatchers.IO)`. */
val LocalAttachmentReader: ProvidableCompositionLocal<AttachmentReader?> = staticCompositionLocalOf { null }
