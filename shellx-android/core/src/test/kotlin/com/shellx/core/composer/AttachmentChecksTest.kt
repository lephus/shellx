package com.shellx.core.composer

import com.shellx.link.core.AttachmentKind
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** The size, empty and naming rules of the iPhone's AttachmentPreparer, for 3E's AttachmentReader. */
class AttachmentChecksTest {
    @Test fun aPickedImageIsSentAsIs() {
        val b = ByteArray(3) { 7 }
        val a = AttachmentChecks.checked(AttachmentKind.IMAGE, "photo-1.jpg", b)
        assertContentEquals(b, a.data)
        assertEquals("photo-1.jpg", a.name)
    }

    @Test fun overTenMiBIsRefusedWithItsName() {
        assertEquals(
            "big.mov",
            assertFailsWith<AttachmentReadException.TooLarge> {
                AttachmentChecks.checked(AttachmentKind.FILE, "big.mov", ByteArray(10_485_761))
            }.name,
        )
        assertFailsWith<AttachmentReadException.TooLarge> { AttachmentChecks.refuseIfTooLarge("x", 10_485_761) }
        AttachmentChecks.refuseIfTooLarge("x", 10_485_760)
        AttachmentChecks.refuseIfTooLarge("x", null)
    }

    @Test fun anEmptyFileIsUnreadable() {
        assertEquals(
            "empty.txt",
            assertFailsWith<AttachmentReadException.Unreadable> {
                AttachmentChecks.checked(AttachmentKind.FILE, "empty.txt", ByteArray(0))
            }.name,
        )
    }

    @Test fun photosAreNamedFromWhatTheyAre() {
        assertEquals("photo-1.jpg", AttachmentChecks.photoName("jpg", emptyList()))
        assertEquals("photo-3.png", AttachmentChecks.photoName("png", listOf("photo-1.png", "photo-2.png", "photo-1.jpg")))
        assertEquals(
            listOf("jpg", "png", "heic", "heic", "gif", "webp", "jpg", "jpg"),
            listOf("image/jpeg", "image/png", "image/heic", "image/heif", "image/gif", "image/webp", "application/pdf", null)
                .map { AttachmentChecks.photoExtension(it) },
        )
    }

    @Test fun failuresNeverPrintTheBytes() {
        val a = OutgoingAttachment(kind = AttachmentKind.FILE, name = "secret.txt", data = ByteArray(4))
        assertFalse("secret" in a.toString())
        assertTrue("4 bytes" in a.toString())
    }

    @Test fun everyFailureSaysWhichAttachment() {
        listOf(AttachmentReadException.TooLarge("a.pdf"), AttachmentReadException.Unreadable("a.pdf"))
            .forEach { assertEquals("a.pdf", it.name) }
    }
}
