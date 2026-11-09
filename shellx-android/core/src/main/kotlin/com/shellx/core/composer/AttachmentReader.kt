package com.shellx.core.composer

import com.shellx.link.core.AttachmentKind

/** A picked photo or file (contracts §5). [uri] is the content URI; it never prints. */
data class AttachmentPick(val uri: String, val kind: AttachmentKind) {
    override fun toString(): String = "AttachmentPick(uri=<redacted>, kind=${kind.wire})"
}

/**
 * Reads a pick (contracts §5; 3E implements it with the Photo Picker / OpenMultipleDocuments through ContentResolver,
 * off the main thread, cancellable).
 */
interface AttachmentReader {
    /**
     * A photo is named AttachmentChecks.photoName(AttachmentChecks.photoExtension(mime), taken); a file keeps its
     * display name. It checks the size first when the provider reports it (AttachmentChecks.refuseIfTooLarge), then
     * the bytes (AttachmentChecks.checked). Throws [AttachmentReadException].
     */
    suspend fun read(pick: AttachmentPick, taken: List<String>): OutgoingAttachment
}

/** Why a pick could not be attached. [name] is for the screen's message; it never prints. */
sealed class AttachmentReadException(val name: String) : Exception("attachment_unreadable") {
    /** Bigger than one upload may be. */
    class TooLarge(name: String) : AttachmentReadException(name)

    /** Empty, or it could not be read. */
    class Unreadable(name: String) : AttachmentReadException(name)
}
