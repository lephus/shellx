import Foundation

/// What a Mac tells the phones granted to it (`notify.phones`, `POST /v2/notifications`).
public enum PhoneNotification: Equatable, Sendable {
    /// An agent waits for the user. The phones' alert names the agent and the workspace, never what
    /// the agent asks; `requestID` is the pending request's id.
    case needsYou(requestID: String, agent: String, workspaceTitle: String)
    /// The request was handled (on the Mac, on a phone, or it went away): the phones take the alert away.
    case resolved(requestID: String)
}

extension ShellXCoreClient {
    /// Sends `notification` through the relay; returns how many phones APNs took it for. The relay
    /// answers `push_unavailable` while it has no APNs key.
    @discardableResult
    public func notifyPhones(_ notification: PhoneNotification) throws -> Int {
        struct Reply: Decodable { let sent: Int }
        let params: [String: JSONValue]
        switch notification {
        case let .needsYou(requestID, agent, workspaceTitle):
            params = [
                "kind": .string("needs_you"), "request_id": .string(requestID),
                "agent": .string(agent), "workspace_title": .string(workspaceTitle),
            ]
        case let .resolved(requestID):
            params = ["kind": .string("resolved"), "request_id": .string(requestID)]
        }
        return try call("notify.phones", params, as: Reply.self).sent
    }
}
