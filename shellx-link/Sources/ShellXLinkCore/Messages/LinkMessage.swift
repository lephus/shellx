import Foundation

/// A ShellX Link v1 message. See `shellx-link/spec/PROTOCOL.md`.
public enum LinkMessage: Equatable, Sendable {
    case hello(clientVersion: String, deviceName: String)
    case welcome(protocolVersion: Int, hostVersion: String, machineName: String)
    case error(code: String, message: String)
    case snapshotGet
    case snapshot(revision: Int, pending: [PendingItem])
    case changed(revision: Int, added: [PendingItem], resolved: [String])
    case reply(requestId: String, mode: PermissionMode)
    case replyResult(requestId: String, outcome: ReplyOutcome)
    case ping(nonce: UInt64)
    case pong(nonce: UInt64)
    /// Decode-only: a well-formed frame whose `t` this version does not know.
    case unknown(type: String)
}
