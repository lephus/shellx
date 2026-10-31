import Foundation

/// A ShellX Link v1 message. See `shellx-link/spec/PROTOCOL.md`.
///
/// Every request/answer pair carries the client's `callId` (PROTOCOL.md section 3).
public enum LinkMessage: Equatable, Sendable {
    case hello(clientVersion: String, deviceName: String)
    /// `features` lists what the host offers beyond the base protocol (PROTOCOL.md section 4); empty when none.
    case welcome(protocolVersion: Int, hostVersion: String, machineName: String, features: [String])
    /// `callId` is set when the error answers one specific client call.
    case error(code: String, message: String, callId: String?)
    case snapshotGet(callId: String)
    case snapshot(callId: String, revision: Int, pending: [PendingItem])
    case changed(revision: Int, added: [PendingItem], resolved: [String])
    case reply(callId: String, requestId: String, decision: LinkDecision)
    case replyResult(callId: String, requestId: String, outcome: ReplyOutcome)
    case ping(nonce: UInt64)
    case pong(nonce: UInt64)
    case sessionsGet(callId: String)
    case sessions(callId: String, revision: Int, sessions: [AgentSession])
    case sessionsChanged(revision: Int, upserted: [AgentSession], removed: [String])
    case chatHistoryGet(callId: String, sessionId: String, beforeSeq: Int?, limit: Int)
    case chatHistory(callId: String, sessionId: String, entries: [ChatEntry], hasMore: Bool)
    case chatEntries(sessionId: String, entries: [ChatEntry])
    /// The session's transcript was replaced: the client drops its entries and pages again (PROTOCOL.md 4).
    case chatReset(sessionId: String)
    /// `attachments` names uploads made with `attach.*` (PROTOCOL.md section 5); empty for a text-only message.
    case chatSend(callId: String, sessionId: String, text: String, attachments: [String])
    case chatSendResult(callId: String, outcome: ChatSendOutcome)
    case chatInterrupt(callId: String, sessionId: String, hard: Bool)
    case chatInterruptResult(callId: String, outcome: ChatInterruptOutcome)
    /// Starts an upload of `size` bytes (PROTOCOL.md section 5, "Attachments"); the host answers `attachReady`.
    case attachBegin(callId: String, kind: AttachmentKind, name: String, size: Int)
    case attachReady(callId: String, attachmentId: String)
    /// `data` is raw bytes in memory; on the wire it is standard base64 with padding.
    case attachChunk(callId: String, attachmentId: String, offset: Int, data: Data)
    /// `received` is the number of bytes the host holds so far.
    case attachChunkResult(callId: String, attachmentId: String, received: Int)
    /// `sha256` is the 32-byte digest of the whole upload; on the wire it is 64 lowercase hex characters.
    case attachEnd(callId: String, attachmentId: String, sha256: Data)
    case attachEndResult(callId: String, attachmentId: String)
    case workspacesGet(callId: String)
    case workspaces(callId: String, revision: Int, workspaces: [LinkWorkspace])
    case workspacesChanged(revision: Int, upserted: [LinkWorkspace], removed: [String])
    case workspaceCreate(callId: String)
    /// `workspaceId` is the new workspace's id, present only when `outcome` is `ok`.
    case workspaceCreateResult(callId: String, outcome: WorkspaceControlOutcome, workspaceId: String?)
    case workspaceRename(callId: String, workspaceId: String, title: String)
    case workspaceRenameResult(callId: String, outcome: WorkspaceControlOutcome)
    case workspaceClose(callId: String, workspaceId: String)
    case workspaceCloseResult(callId: String, outcome: WorkspaceControlOutcome)
    case agentClose(callId: String, sessionId: String)
    case agentCloseResult(callId: String, outcome: WorkspaceControlOutcome)
    /// Decode-only: a well-formed frame whose `t` this version does not know. `callId` is the frame's `call_id`
    /// when it is a valid one (1 to 64 UTF-8 bytes): such a frame is a call of a later version, which a host
    /// answers `error` `unsupported` (PROTOCOL.md section 3).
    case unknown(type: String, callId: String?)
}
