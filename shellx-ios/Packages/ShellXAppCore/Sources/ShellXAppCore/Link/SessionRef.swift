import Foundation

/// Points at one agent session on one Mac.
///
/// Identity is `machineID` and `sessionId`: two refs to the same session are equal even when one
/// carries an older `workspaceTitle`. `agent` and `workspaceTitle` are only labels for display.
public struct SessionRef: Codable, Hashable, Sendable {
    public var machineID: String
    public var sessionId: String
    public var agent: String
    public var workspaceTitle: String

    public init(machineID: String, sessionId: String, agent: String, workspaceTitle: String) {
        self.machineID = machineID
        self.sessionId = sessionId
        self.agent = agent
        self.workspaceTitle = workspaceTitle
    }

    public static func == (lhs: SessionRef, rhs: SessionRef) -> Bool {
        lhs.machineID == rhs.machineID && lhs.sessionId == rhs.sessionId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(machineID)
        hasher.combine(sessionId)
    }
}
