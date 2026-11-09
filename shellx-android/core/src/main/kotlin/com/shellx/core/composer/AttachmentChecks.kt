package com.shellx.core.composer

import com.shellx.link.core.AttachmentKind
import com.shellx.link.core.ShellXLink

/** The size, empty and naming rules of a picked attachment (the iPhone's AttachmentPreparer; ledger A-9). */
object AttachmentChecks {
    /** Over ShellXLink.MAX_ATTACHMENT_BYTES → TooLarge(name); empty → Unreadable(name); else the attachment as
     *  picked. */
    fun checked(kind: AttachmentKind, name: String, data: ByteArray): OutgoingAttachment {
        if (data.size > ShellXLink.MAX_ATTACHMENT_BYTES) throw AttachmentReadException.TooLarge(name)
        if (data.isEmpty()) throw AttachmentReadException.Unreadable(name)
        return OutgoingAttachment(kind = kind, name = name, data = data)
    }

    /** [size] over ShellXLink.MAX_ATTACHMENT_BYTES → TooLarge(name); null (the provider does not say) or within the
     *  limit → nothing. */
    fun refuseIfTooLarge(name: String, size: Long?) {
        if (size != null && size > ShellXLink.MAX_ATTACHMENT_BYTES) throw AttachmentReadException.TooLarge(name)
    }

    /** "photo-<n>.<extension>", with the first n from 1 that no name in [taken] has. */
    fun photoName(extension: String, taken: List<String>): String {
        val used = taken.toSet()
        var number = 1
        while ("photo-$number.$extension" in used) number += 1
        return "photo-$number.$extension"
    }

    /** image/jpeg → "jpg", image/png → "png", image/heic and image/heif → "heic", image/gif → "gif", image/webp →
     *  "webp"; anything else or null → "jpg". */
    fun photoExtension(mimeType: String?): String = when (mimeType) {
        "image/png" -> "png"
        "image/heic", "image/heif" -> "heic"
        "image/gif" -> "gif"
        "image/webp" -> "webp"
        else -> "jpg"
    }
}
