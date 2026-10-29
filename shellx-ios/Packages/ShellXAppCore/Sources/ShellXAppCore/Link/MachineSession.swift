import Foundation
import ShellXLinkCore

/// An agent session with the Mac it runs on.
public struct MachineSession: Identifiable, Equatable, Sendable {
    public var machineID: String
    public var machineName: String
    /// Whether the Mac is online now. An offline Mac's sessions are its last known ones.
    public var online: Bool
    public var session: AgentSession

    public init(machineID: String, machineName: String, online: Bool, session: AgentSession) {
        self.machineID = machineID
        self.machineName = machineName
        self.online = online
        self.session = session
    }

    public var ref: SessionRef {
        SessionRef(
            machineID: machineID, sessionId: session.sessionId, agent: session.agent,
            workspaceTitle: session.workspaceTitle)
    }

    public var id: SessionRef { ref }
}
