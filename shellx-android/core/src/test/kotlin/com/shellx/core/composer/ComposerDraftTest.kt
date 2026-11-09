package com.shellx.core.composer

import com.shellx.link.core.AttachmentKind
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * What the composer keeps once a message with attachments is answered: what went is cleared, what was added meanwhile
 * (a photo still loading when Send was tapped) stays, and nothing is cleared when the message is to be sent again.
 */
class ComposerDraftTest {
    private fun attachment(name: String) = OutgoingAttachment(kind = AttachmentKind.IMAGE, name = name, data = name.encodeToByteArray())

    @Test fun lateAttachmentSurvivesASuccessfulSend() {
        val first = attachment("photo-1.jpg")
        val second = attachment("photo-2.jpg")
        val late = attachment("photo-3.jpg")
        var draft = ComposerDraft(text = "sửa lỗi này", attachments = listOf(first, second))

        draft = draft.sendStarted()
        assertTrue(draft.isSending)
        // The third photo finishes loading while the first two go up.
        draft = draft.copy(attachments = draft.attachments + late)
        draft = draft.sendEnded(keepsDraft = false)

        assertFalse(draft.isSending)
        assertEquals("", draft.text)
        assertEquals(listOf(late), draft.attachments, "only what went is cleared")
    }

    @Test fun messageToSendAgainKeepsEverything() {
        val first = attachment("photo-1.jpg")
        val late = attachment("photo-2.jpg")
        var draft = ComposerDraft(text = "sửa lỗi này", attachments = listOf(first))

        draft = draft.sendStarted()
        draft = draft.copy(attachments = draft.attachments + late)
        draft = draft.sendEnded(keepsDraft = true)

        assertFalse(draft.isSending)
        assertEquals("sửa lỗi này", draft.text)
        assertEquals(listOf(first, late), draft.attachments)
    }

    @Test fun answerWithoutASendChangesNothing() {
        val first = attachment("photo-1.jpg")
        var draft = ComposerDraft(text = "chưa gửi", attachments = listOf(first))

        draft = draft.sendEnded(keepsDraft = false)

        assertEquals(ComposerDraft(text = "chưa gửi", attachments = listOf(first)), draft)
    }
}
