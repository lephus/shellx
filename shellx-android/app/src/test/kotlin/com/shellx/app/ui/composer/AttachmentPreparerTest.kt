package com.shellx.app.ui.composer

import android.content.Context
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.TestAttachmentProvider
import com.shellx.core.composer.AttachmentPick
import com.shellx.core.composer.AttachmentReadException
import com.shellx.link.core.AttachmentKind
import com.shellx.link.core.ShellXLink
import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf

/** The file rules of AttachmentPreparerTests, over a ContentResolver. */
@RunWith(AndroidJUnit4::class)
class AttachmentPreparerTest {
    @get:Rule val temp = TemporaryFolder()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val preparer = AttachmentPreparer(context.contentResolver, Dispatchers.Unconfined)
    private val authority = "com.shellx.test.attachments"

    @Before
    fun setUp() {
        Robolectric.setupContentProvider(TestAttachmentProvider::class.java, authority)
        TestAttachmentProvider.entries.clear()
    }

    private fun content(name: String, size: Long?, mime: String?, bytes: InputStream): String {
        TestAttachmentProvider.entries[name] = TestAttachmentProvider.Entry(name, size, mime)
        val uri = Uri.parse("content://$authority/$name")
        shadowOf(context.contentResolver).registerInputStream(uri, bytes)
        return uri.toString()
    }

    @Test
    fun aPickedFileIsReadWholeUnderItsName() {
        runTest {
            val f = temp.newFile("build-output.log").apply { writeText("error: missing import\n") }
            val a = preparer.read(AttachmentPick(Uri.fromFile(f).toString(), AttachmentKind.FILE), emptyList())
            assertEquals("build-output.log", a.name)
            assertEquals(AttachmentKind.FILE, a.kind)
            assertArrayEquals("error: missing import\n".toByteArray(), a.data)
        }
    }

    @Test
    fun aPhotoIsNamedAfterItsTypeAndTheNamesTaken() {
        runTest {
            val uri = content("IMG_0001", 3, "image/png", ByteArrayInputStream(byteArrayOf(1, 2, 3)))
            val a = preparer.read(AttachmentPick(uri, AttachmentKind.IMAGE), listOf("photo-1.png"))
            assertEquals("photo-2.png", a.name)
            assertArrayEquals(byteArrayOf(1, 2, 3), a.data)
        }
    }

    @Test
    fun aReportedSizeOverTheLimitIsRefusedBeforeReading() {
        runTest {
            val untouched = object : InputStream() {
                override fun read(): Int = error("read")
            }
            val uri = content("big.mov", 10_485_761, "video/quicktime", untouched)
            val e = runCatching { preparer.read(AttachmentPick(uri, AttachmentKind.FILE), emptyList()) }.exceptionOrNull()
            assertEquals("big.mov", (e as AttachmentReadException.TooLarge).name)
        }
    }

    /** RF 2. */
    @Test
    fun anUnknownSizeStreamStopsJustPastTheLimit() {
        runTest {
            var served = 0L
            val endless = object : InputStream() {
                override fun read(): Int {
                    served++
                    return 0
                }

                override fun read(b: ByteArray, off: Int, len: Int): Int {
                    served += len
                    return len
                }
            }
            val uri = Uri.parse("content://com.shellx.test.nowhere/stream")
            shadowOf(context.contentResolver).registerInputStream(uri, endless)
            val e = runCatching { preparer.read(AttachmentPick(uri.toString(), AttachmentKind.FILE), emptyList()) }.exceptionOrNull()
            assertEquals("stream", (e as AttachmentReadException.TooLarge).name)
            assertTrue(served <= ShellXLink.MAX_ATTACHMENT_BYTES + AttachmentPreparer.CHUNK_BYTES)
        }
    }

    @Test
    fun aMissingOrEmptyFileSaysWhichOne() {
        runTest {
            val gone = runCatching {
                preparer.read(AttachmentPick(Uri.fromFile(File(temp.root, "gone.txt")).toString(), AttachmentKind.FILE), emptyList())
            }
            assertEquals("gone.txt", (gone.exceptionOrNull() as AttachmentReadException.Unreadable).name)
            val empty = runCatching { preparer.read(AttachmentPick(Uri.fromFile(temp.newFile("empty.txt")).toString(), AttachmentKind.FILE), emptyList()) }
            assertEquals("empty.txt", (empty.exceptionOrNull() as AttachmentReadException.Unreadable).name)
        }
    }

    /** The HEIC ruling (2026-11-09): a HEIC/HEIF photo goes as JPEG, as the iPhone's photo picker hands it over. */
    @Test
    fun aHeicPhotoGoesAsJpeg() {
        runTest {
            val converting = AttachmentPreparer(context.contentResolver, Dispatchers.Unconfined) { heic ->
                assertArrayEquals(byteArrayOf(7, 7, 7), heic)
                byteArrayOf(9, 9)
            }
            val uri = content("IMG_0002", 3, "image/heic", ByteArrayInputStream(byteArrayOf(7, 7, 7)))
            val a = converting.read(AttachmentPick(uri, AttachmentKind.IMAGE), listOf("photo-1.jpg"))
            assertEquals("photo-2.jpg", a.name)
            assertArrayEquals(byteArrayOf(9, 9), a.data)
        }
    }

    /** A phone that cannot decode it (before API 28) sends the photo as picked, under its own type. */
    @Test
    fun aHeifPhotoThatCannotBeConvertedGoesAsPicked() {
        runTest {
            val unable = AttachmentPreparer(context.contentResolver, Dispatchers.Unconfined) { null }
            val uri = content("IMG_0003", 3, "image/heif", ByteArrayInputStream(byteArrayOf(7, 7, 7)))
            val a = unable.read(AttachmentPick(uri, AttachmentKind.IMAGE), emptyList())
            assertEquals("photo-1.heic", a.name)
            assertArrayEquals(byteArrayOf(7, 7, 7), a.data)
        }
    }
}
