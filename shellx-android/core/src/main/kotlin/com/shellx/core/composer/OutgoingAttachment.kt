package com.shellx.core.composer

import com.shellx.link.core.AttachmentKind
import java.util.UUID

/**
 * A photo or file waiting in the composer, sent with the next message (PROTOCOL.md section 5, "Attachments"): its
 * bytes as picked, and the name the Mac is told (only a label: the Mac sanitises it). Never logged: toString shows
 * neither the bytes nor the name.
 */
data class OutgoingAttachment(
    val id: String = UUID.randomUUID().toString(),
    val kind: AttachmentKind,
    val name: String,
    val data: ByteArray,
) {
    override fun equals(other: Any?): Boolean = other is OutgoingAttachment && id == other.id && kind == other.kind &&
        name == other.name && data.contentEquals(other.data)

    override fun hashCode(): Int = ((id.hashCode() * 31 + kind.hashCode()) * 31 + name.hashCode()) * 31 + data.contentHashCode()

    override fun toString(): String = "OutgoingAttachment(id=$id, kind=${kind.wire}, <${data.size} bytes>)"
}
