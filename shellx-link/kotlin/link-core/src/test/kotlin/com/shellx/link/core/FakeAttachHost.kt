package com.shellx.link.core

import java.io.ByteArrayOutputStream
import java.util.concurrent.CopyOnWriteArrayList

/**
 * The host side of the attachment rules (PROTOCOL.md section 5, "Attachments") over one [SecureChannel], for the
 * client upload tests. Ids are `U<n>`, where n counts accepted begins.
 *
 * With [stallSecondChunkOfFirstUpload] it never answers the second chunk of `U1`; with [answerChatSend] false it never
 * answers a `chat.send`.
 */
class FakeAttachHost(
    private val channel: SecureChannel,
    private val stallSecondChunkOfFirstUpload: Boolean = false,
    private val answerChatSend: Boolean = true,
) {
    /** One `chat.send` the host accepted, with its attachments in order. */
    class Sent(val text: String, val names: List<String>, val bytes: List<ByteArray>)

    private class Upload(val kind: AttachmentKind, val name: String, val size: Int) {
        val data = ByteArrayOutputStream()
        var finishOrder: Int? = null
    }

    /** `begin:U1`, `chunk:U1:<offset>`, `end:U1`, `send:<text>`, in arrival order; refusals as `refused:<code>`. */
    val events: MutableList<String> = CopyOnWriteArrayList()
    val sent: MutableList<Sent> = CopyOnWriteArrayList()

    /** (attachment id, offset, size) of each chunk received. */
    val chunks: MutableList<Triple<String, Int, Int>> = CopyOnWriteArrayList()

    /** The digest of each `attach.end` received. */
    val digests: MutableList<ByteArray> = CopyOnWriteArrayList()

    private val uploads = LinkedHashMap<String, Upload>()
    private var accepted = 0
    private var finished = 0

    /** Answers the client until the circuit closes. */
    suspend fun serve() {
        try {
            while (true) {
                val answer = answer(channel.request()) ?: continue
                channel.send(answer)
            }
        } catch (_: RelayException.Closed) {
            // The session ended.
        }
    }

    private fun refuse(code: String, callId: String): LinkMessage {
        events += "refused:$code"
        return LinkMessage.Error(code, "refused", callId)
    }

    private fun answer(m: LinkMessage): LinkMessage? = when (m) {
        is LinkMessage.AttachBegin -> begin(m)
        is LinkMessage.AttachChunk -> chunk(m)
        is LinkMessage.AttachEnd -> end(m)
        is LinkMessage.ChatSend -> chatSend(m)
        else -> null
    }

    private fun begin(m: LinkMessage.AttachBegin): LinkMessage {
        // One upload at a time: whatever has not ended was given up.
        uploads.entries.removeIf { it.value.finishOrder == null }
        if (m.kind != AttachmentKind.IMAGE && m.kind != AttachmentKind.FILE) return refuse("bad_request", m.callId)
        if (m.size < 1) return refuse("bad_request", m.callId)
        if (m.size > ShellXLink.MAX_ATTACHMENT_BYTES) return refuse("too_large", m.callId)
        while (uploads.size >= ShellXLink.MAX_PENDING_UPLOADS) {
            uploads.remove(uploads.minByOrNull { it.value.finishOrder ?: 0 }!!.key)
        }
        accepted += 1
        val id = "U$accepted"
        uploads[id] = Upload(m.kind, m.name, m.size)
        events += "begin:$id"
        return LinkMessage.AttachReady(m.callId, id)
    }

    private fun chunk(m: LinkMessage.AttachChunk): LinkMessage? {
        events += "chunk:${m.attachmentId}:${m.offset}"
        chunks += Triple(m.attachmentId, m.offset, m.data.size)
        if (stallSecondChunkOfFirstUpload && m.attachmentId == "U1" && m.offset > 0) return null
        val upload = uploads[m.attachmentId]?.takeIf { it.finishOrder == null } ?: return refuse("bad_request", m.callId)
        val held = upload.data.size()
        if (m.offset != held || m.data.size !in 1..ShellXLink.MAX_ATTACHMENT_CHUNK_BYTES || held + m.data.size > upload.size) {
            return refuse("bad_request", m.callId)
        }
        upload.data.write(m.data)
        return LinkMessage.AttachChunkResult(m.callId, m.attachmentId, held + m.data.size)
    }

    private fun end(m: LinkMessage.AttachEnd): LinkMessage {
        digests += m.sha256
        val upload = uploads[m.attachmentId]?.takeIf { it.finishOrder == null } ?: return refuse("bad_request", m.callId)
        if (upload.data.size() != upload.size || !sha256(upload.data.toByteArray()).contentEquals(m.sha256)) {
            uploads.remove(m.attachmentId)
            return refuse("bad_request", m.callId)
        }
        finished += 1
        upload.finishOrder = finished
        events += "end:${m.attachmentId}"
        return LinkMessage.AttachEndResult(m.callId, m.attachmentId)
    }

    private fun chatSend(m: LinkMessage.ChatSend): LinkMessage? {
        events += "send:${m.text}"
        if (!answerChatSend) return null
        val ids = m.attachments
        val held = ids.mapNotNull { id -> uploads[id]?.takeIf { it.finishOrder != null } }
        if (ids.size > ShellXLink.MAX_ATTACHMENTS_PER_MESSAGE || ids.toSet().size != ids.size || held.size != ids.size) {
            return refuse("bad_request", m.callId)
        }
        ids.forEach { uploads.remove(it) }
        sent += Sent(m.text, held.map { it.name }, held.map { it.data.toByteArray() })
        return LinkMessage.ChatSendResult(m.callId, ChatSendOutcome.SUBMITTED)
    }
}
