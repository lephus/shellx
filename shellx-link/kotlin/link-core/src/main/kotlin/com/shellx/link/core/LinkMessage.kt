package com.shellx.link.core

/**
 * A ShellX Link v1 message (PROTOCOL.md section 4). Each property is sent under its snake_case name, in the
 * order declared. Every request that expects one answer carries a `callId` of 1 to 64 UTF-8 bytes. User content
 * prints as `<redacted>` (Global Constraint "Secrets"); the models it nests redact themselves.
 */
sealed interface LinkMessage {
    /** The one answer to a client call (PROTOCOL.md section 3). */
    sealed interface Answer : LinkMessage {
        val callId: String
    }

    data class Hello(val clientVersion: String, val deviceName: String) : LinkMessage {
        override fun toString(): String = "Hello(clientVersion=$clientVersion, deviceName=<redacted>)"
    }

    /** `features` lists what the host offers beyond the base protocol; empty when none. */
    data class Welcome(
        val protocolVersion: Int,
        val hostVersion: String,
        val machineName: String,
        val features: List<String> = emptyList(),
    ) : LinkMessage {
        override fun toString(): String =
            "Welcome(protocolVersion=$protocolVersion, hostVersion=$hostVersion, machineName=<redacted>, features=$features)"
    }

    /** `callId` is set when the error answers one specific client call. */
    data class Error(val code: String, val message: String, val callId: String? = null) : LinkMessage {
        override fun toString(): String = "Error(code=$code, message=<redacted>, callId=$callId)"
    }

    data class SnapshotGet(val callId: String) : LinkMessage

    data class Snapshot(override val callId: String, val revision: Long, val pending: List<PendingItem>) : Answer

    data class Changed(val revision: Long, val added: List<PendingItem>, val resolved: List<String>) : LinkMessage

    data class Reply(val callId: String, val requestId: String, val decision: LinkDecision) : LinkMessage

    data class ReplyResult(override val callId: String, val requestId: String, val outcome: ReplyOutcome) : Answer

    data class Ping(val nonce: ULong) : LinkMessage

    data class Pong(val nonce: ULong) : LinkMessage

    data class SessionsGet(val callId: String) : LinkMessage

    data class Sessions(override val callId: String, val revision: Long, val sessions: List<AgentSession>) : Answer

    data class SessionsChanged(val revision: Long, val upserted: List<AgentSession>, val removed: List<String>) : LinkMessage

    data class ChatHistoryGet(val callId: String, val sessionId: String, val beforeSeq: Long? = null, val limit: Int) : LinkMessage

    data class ChatHistory(
        override val callId: String,
        val sessionId: String,
        val entries: List<ChatEntry>,
        val hasMore: Boolean,
    ) : Answer

    data class ChatEntries(val sessionId: String, val entries: List<ChatEntry>) : LinkMessage

    /** The session's transcript was replaced: the client drops its entries and pages again. */
    data class ChatReset(val sessionId: String) : LinkMessage

    /** `attachments` names uploads made with `attach.*`; empty for a text-only message. */
    data class ChatSend(
        val callId: String,
        val sessionId: String,
        val text: String,
        val attachments: List<String> = emptyList(),
    ) : LinkMessage {
        override fun toString(): String =
            "ChatSend(callId=$callId, sessionId=$sessionId, text=<redacted>, attachments=$attachments)"
    }

    data class ChatSendResult(override val callId: String, val outcome: ChatSendOutcome) : Answer

    data class ChatInterrupt(val callId: String, val sessionId: String, val hard: Boolean) : LinkMessage

    data class ChatInterruptResult(override val callId: String, val outcome: ChatInterruptOutcome) : Answer

    /** Starts an upload of `size` bytes; the host answers [AttachReady]. */
    data class AttachBegin(val callId: String, val kind: AttachmentKind, val name: String, val size: Int) : LinkMessage {
        override fun toString(): String = "AttachBegin(callId=$callId, kind=$kind, name=<redacted>, size=$size)"
    }

    data class AttachReady(override val callId: String, val attachmentId: String) : Answer

    /** `data` is raw bytes; on the wire it is standard base64 with padding. */
    data class AttachChunk(val callId: String, val attachmentId: String, val offset: Int, val data: ByteArray) : LinkMessage {
        override fun equals(other: Any?): Boolean = other is AttachChunk && callId == other.callId &&
            attachmentId == other.attachmentId && offset == other.offset && data.contentEquals(other.data)

        override fun hashCode(): Int = ((callId.hashCode() * 31 + attachmentId.hashCode()) * 31 + offset) * 31 + data.contentHashCode()

        override fun toString(): String =
            "AttachChunk(callId=$callId, attachmentId=$attachmentId, offset=$offset, data=<${data.size} bytes>)"
    }

    /** `received` is the number of bytes the host holds so far. */
    data class AttachChunkResult(override val callId: String, val attachmentId: String, val received: Int) : Answer

    /** `sha256` is the 32-byte digest of the whole upload; on the wire it is 64 lowercase hex characters. */
    data class AttachEnd(val callId: String, val attachmentId: String, val sha256: ByteArray) : LinkMessage {
        override fun equals(other: Any?): Boolean = other is AttachEnd && callId == other.callId &&
            attachmentId == other.attachmentId && sha256.contentEquals(other.sha256)

        override fun hashCode(): Int = (callId.hashCode() * 31 + attachmentId.hashCode()) * 31 + sha256.contentHashCode()

        override fun toString(): String = "AttachEnd(callId=$callId, attachmentId=$attachmentId, sha256=<${sha256.size} bytes>)"
    }

    data class AttachEndResult(override val callId: String, val attachmentId: String) : Answer

    data class WorkspacesGet(val callId: String) : LinkMessage

    data class Workspaces(override val callId: String, val revision: Long, val workspaces: List<LinkWorkspace>) : Answer

    data class WorkspacesChanged(val revision: Long, val upserted: List<LinkWorkspace>, val removed: List<String>) : LinkMessage

    data class WorkspaceCreate(val callId: String) : LinkMessage

    /** `workspaceId` is the new workspace's id, present only when `outcome` is `ok`. */
    data class WorkspaceCreateResult(
        override val callId: String,
        val outcome: WorkspaceControlOutcome,
        val workspaceId: String? = null,
    ) : Answer

    data class WorkspaceRename(val callId: String, val workspaceId: String, val title: String) : LinkMessage {
        override fun toString(): String = "WorkspaceRename(callId=$callId, workspaceId=$workspaceId, title=<redacted>)"
    }

    data class WorkspaceRenameResult(override val callId: String, val outcome: WorkspaceControlOutcome) : Answer

    data class WorkspaceClose(val callId: String, val workspaceId: String) : LinkMessage

    data class WorkspaceCloseResult(override val callId: String, val outcome: WorkspaceControlOutcome) : Answer

    data class AgentClose(val callId: String, val sessionId: String) : LinkMessage

    data class AgentCloseResult(override val callId: String, val outcome: WorkspaceControlOutcome) : Answer

    data class TerminalClose(val callId: String, val workspaceId: String, val terminalId: String) : LinkMessage

    data class TerminalCloseResult(override val callId: String, val outcome: WorkspaceControlOutcome) : Answer

    /**
     * Decode-only: a well-formed frame whose `t` this version does not know. `callId` is the frame's `call_id` when
     * it is a valid one (1 to 64 UTF-8 bytes). [LinkCodec.encode] refuses it.
     */
    data class Unknown(val type: String, val callId: String? = null) : LinkMessage
}
