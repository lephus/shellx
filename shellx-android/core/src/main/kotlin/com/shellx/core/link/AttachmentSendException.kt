package com.shellx.core.link

/**
 * Why a message with attachments surely did not reach its session (`MachineHub.chatSend` with attachments). Nothing
 * was typed, so the message can be sent again as it is.
 */
sealed class AttachmentSendException(message: String) : Exception(message) {
    /** The link failed while an attachment went up (a timeout, the session closed): the message itself was never sent. */
    class UploadFailed : AttachmentSendException("upload_failed")

    /** The Mac refused an upload or the message that named them (`too_large`, `bad_request`, `unsupported`), or it
     *  does not take attachments (`unsupported`, never asked). */
    data class Refused(val code: String) : AttachmentSendException("refused")
}
