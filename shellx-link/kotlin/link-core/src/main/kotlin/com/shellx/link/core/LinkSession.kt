package com.shellx.link.core

import kotlinx.coroutines.flow.Flow

/** The full pending set and its revision (`agent.snapshot`). */
data class PendingSnapshot(val revision: Long, val pending: List<PendingItem>)

/**
 * One `agent.changed` push. Compared with the revision of the last change or snapshot applied: at or below it, skip
 * it; exactly one above, apply it; further above, a change was missed and the caller resyncs with `snapshot()`
 * (PROTOCOL.md section 4). The same rule holds for [SessionChange] and [WorkspaceChange].
 */
data class PendingChange(val revision: Long, val added: List<PendingItem>, val resolved: List<String>)

/** The full list of agent sessions and its revision (`agent.sessions`). */
data class SessionList(val revision: Long, val sessions: List<AgentSession>)

/** One `agent.sessions.changed` push. */
data class SessionChange(val revision: Long, val upserted: List<AgentSession>, val removed: List<String>)

/** The full list of workspaces, in the Mac's sidebar order, and its revision (`workspace.list`). */
data class WorkspaceList(val revision: Long, val workspaces: List<LinkWorkspace>)

/** One `workspace.changed` push: `upserted` replaces a workspace by id (with all its terminals). */
data class WorkspaceChange(val revision: Long, val upserted: List<LinkWorkspace>, val removed: List<String>)

/** A page of a transcript, oldest entry first. [hasMore] tells whether older entries exist. */
data class ChatHistoryPage(val entries: List<ChatEntry>, val hasMore: Boolean)

/** The answer to `workspace.create`: [workspaceId] is set only when [outcome] is `ok`. */
data class WorkspaceCreated(val outcome: WorkspaceControlOutcome, val workspaceId: String?)

/** One `chat.entries` or `chat.reset` push. */
sealed interface ChatPush {
    val sessionId: String

    /** Empty for [Reset]. */
    val entries: List<ChatEntry>

    /** Upserts by [ChatEntry.id], keeping the higher `rev`. */
    data class Upsert(override val sessionId: String, override val entries: List<ChatEntry>) : ChatPush

    /**
     * The session's transcript was replaced: drop every entry held for it, drop the result of any `chatHistory` call
     * for it that started before the reset, and page again from the newest.
     */
    data class Reset(override val sessionId: String) : ChatPush {
        override val entries: List<ChatEntry> get() = emptyList()
    }
}

/** A photo or file to upload with a message. Neither the name nor the bytes print. */
data class ChatAttachment(val kind: AttachmentKind, val name: String, val data: ByteArray) {
    override fun equals(other: Any?): Boolean =
        other is ChatAttachment && kind == other.kind && name == other.name && data.contentEquals(other.data)

    override fun hashCode(): Int = (kind.hashCode() * 31 + name.hashCode()) * 31 + data.contentHashCode()

    override fun toString(): String = "ChatAttachment(kind=${kind.wire}, name=<redacted>, data=<${data.size} bytes>)"
}

/**
 * An attachment of a message failed to go up, so the message's `chat.send` was never sent: nothing was typed, and
 * sending it again is safe. [cause] is what the upload threw: a [LinkClientException] (`Remote` when the host refused
 * a step) or a [LinkCodecException]. It never wraps a `CancellationException`, which propagates as it is.
 */
class MessageUploadException(override val cause: Exception) : Exception("message_upload", cause)

/** Failures of a Link session. Host text ([ProtocolMismatch.detail], `detail` of the others) never prints. */
sealed class LinkClientException(message: String) : Exception(message) {
    /** The host speaks another protocol version; the user should update the app (PROTOCOL.md section 7). */
    data class ProtocolMismatch(val detail: String) : LinkClientException("protocol_mismatch") {
        override fun toString(): String = "ProtocolMismatch(detail=<redacted>)"
    }

    /** The host answered `hello` with an `error`. */
    data class Rejected(val code: String, val detail: String) : LinkClientException("rejected") {
        override fun toString(): String = "Rejected(code=$code, detail=<redacted>)"
    }

    /** The session ended (closed by either side, or found dead) before an answer arrived. */
    class SessionClosed : LinkClientException("session_closed")

    /** No answer within the request timeout. The session stays usable, and a late answer is dropped. */
    class TimedOut : LinkClientException("timed_out")

    /**
     * The host answered this call with an `error` (PROTOCOL.md section 7): `unsupported`, `too_large`, `bad_request`
     * or `not_found`, for example.
     */
    data class Remote(val code: String, val detail: String) : LinkClientException("remote") {
        override fun toString(): String = "Remote(code=$code, detail=<redacted>)"
    }

    /** The host answered with a message of another type than the call expects. */
    class UnexpectedAnswer : LinkClientException("unexpected_answer")
}

/** A new instance of the same failure, so every caller gets its own exception (Global Constraint "Exceptions"). */
internal fun LinkClientException.fresh(): LinkClientException = when (this) {
    is LinkClientException.ProtocolMismatch -> copy()
    is LinkClientException.Rejected -> copy()
    is LinkClientException.SessionClosed -> LinkClientException.SessionClosed()
    is LinkClientException.TimedOut -> LinkClientException.TimedOut()
    is LinkClientException.Remote -> copy()
    is LinkClientException.UnexpectedAnswer -> LinkClientException.UnexpectedAnswer()
}

/**
 * One established Link session with one host (PROTOCOL.md section 7). 3C fakes it for tests and the demo.
 *
 * Every call throws [LinkClientException.Remote] when the host answers it with an `error`,
 * [LinkClientException.TimedOut] after the request timeout (the session stays usable), the session's end error
 * ([LinkClientException.SessionClosed] by default) when the session ends first, [LinkClientException.UnexpectedAnswer]
 * for an answer of another type, and a [LinkCodecException] when the request cannot be encoded (nothing is sent).
 * A call made after the session ended throws the end error at once.
 */
interface LinkSession {
    /** `welcome.features`; strings this version does not know are kept. */
    val hostFeatures: Set<String>

    /** Each push in arrival order. Single consumer. Completes normally when the session ends. */
    val changes: Flow<PendingChange>

    /** As [changes], for `agent.sessions.changed`. */
    val sessionChanges: Flow<SessionChange>

    /** As [changes], for `workspace.changed`. A host without `workspaces` pushes none. */
    val workspaceChanges: Flow<WorkspaceChange>

    /** As [changes], for `chat.entries` and `chat.reset`. */
    val chatEntries: Flow<ChatPush>

    suspend fun snapshot(): PendingSnapshot

    /** Safe to repeat: the host answers `already_handled` for a resolved request. */
    suspend fun reply(requestId: String, decision: LinkDecision): ReplyOutcome

    suspend fun sessions(): SessionList

    /** The newest [limit] (1 to 50) entries with `seq` below [beforeSeq], or the newest when it is null. */
    suspend fun chatHistory(sessionId: String, beforeSeq: Long?, limit: Int): ChatHistoryPage

    /** Not safe to repeat: after a timeout it is unknown whether the host typed it. */
    suspend fun chatSend(sessionId: String, text: String, attachments: List<String> = emptyList()): ChatSendOutcome

    /**
     * Uploads a photo or file (PROTOCOL.md section 5, "Attachments") and returns the host's id, to name in [chatSend].
     * Sends `attach.begin`, then chunks of at most [ShellXLink.MAX_ATTACHMENT_CHUNK_BYTES] bytes, each after the result
     * of the one before, then `attach.end` with the SHA-256 of [data]. [progress] gets the bytes sent so far after each
     * chunk's result, so its last value is `data.size`. Call it only when [hostFeatures] contains
     * [ShellXLink.ATTACHMENTS_FEATURE].
     *
     * Uploads of one client run one at a time, in call order, and wait for a message of the `uploading` [chatSend] to
     * be answered. A failed or cancelled upload gives up its turn; so does a caller cancelled while it waits. The host
     * refuses a size outside 1 to [ShellXLink.MAX_ATTACHMENT_BYTES] with `too_large` or `bad_request` ([LinkClientException.Remote]).
     */
    suspend fun uploadAttachment(kind: AttachmentKind, name: String, data: ByteArray, progress: (Int) -> Unit = {}): String

    /**
     * Uploads [uploading] in order, then `chat.send` with their ids: one message, holding the upload turn from the first
     * `attach.begin` until the `chat.send` is answered, so no other upload of this client comes in between. [progress]
     * gets the bytes of all the attachments sent so far. An upload failure throws [MessageUploadException]: the
     * `chat.send` never left, so nothing was typed. Otherwise as the [chatSend] with ids. Call it only when
     * [hostFeatures] contains [ShellXLink.ATTACHMENTS_FEATURE].
     */
    suspend fun chatSend(
        sessionId: String,
        text: String,
        uploading: List<ChatAttachment>,
        progress: (Int) -> Unit = {},
    ): ChatSendOutcome

    suspend fun chatInterrupt(sessionId: String, hard: Boolean): ChatInterruptOutcome

    suspend fun workspaces(): WorkspaceList

    suspend fun createWorkspace(): WorkspaceCreated

    suspend fun renameWorkspace(workspaceId: String, title: String): WorkspaceControlOutcome

    suspend fun closeWorkspace(workspaceId: String): WorkspaceControlOutcome

    suspend fun closeAgent(sessionId: String): WorkspaceControlOutcome

    suspend fun closeTerminal(workspaceId: String, terminalId: String): WorkspaceControlOutcome

    /** Ends the session: pending calls throw SessionClosed, every Flow completes, the circuit closes. Idempotent. */
    fun close()
}
