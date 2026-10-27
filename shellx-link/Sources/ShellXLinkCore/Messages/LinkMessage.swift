import Foundation

/// A ShellX Link v1 message. See `shellx-link/spec/PROTOCOL.md`.
///
/// Every request/answer pair carries the client's `callId` (PROTOCOL.md section 3).
public enum LinkMessage: Equatable, Sendable {
    case hello(clientVersion: String, deviceName: String)
    case welcome(protocolVersion: Int, hostVersion: String, machineName: String)
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
    case chatSend(callId: String, sessionId: String, text: String)
    case chatSendResult(callId: String, outcome: ChatSendOutcome)
    case chatInterrupt(callId: String, sessionId: String, hard: Bool)
    case chatInterruptResult(callId: String, outcome: ChatInterruptOutcome)
    /// Decode-only: a well-formed frame whose `t` this version does not know.
    case unknown(type: String)
}
