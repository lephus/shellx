import Foundation
import ShellXRemoteCore

/// Everything the remote sidebar UI reads, frozen at one moment. The app
/// builds it from the remote service (or fixtures in DEBUG).
public struct RemoteUISnapshot: Equatable, Sendable {
    /// The account's other machines (the service excludes this Mac).
    public var machines: [RemoteMachine]
    public var isSignedIn: Bool
    /// Workspace id → the remote machine it is attached to.
    public var remoteWorkspaces: [UUID: RemoteMachine.ID]
    public var pendingApprovals: [PairingRequest]
    public var outgoing: [OutgoingPairing]

    public init(
        machines: [RemoteMachine] = [],
        isSignedIn: Bool = false,
        remoteWorkspaces: [UUID: RemoteMachine.ID] = [:],
        pendingApprovals: [PairingRequest] = [],
        outgoing: [OutgoingPairing] = []
    ) {
        self.machines = machines
        self.isSignedIn = isSignedIn
        self.remoteWorkspaces = remoteWorkspaces
        self.pendingApprovals = pendingApprovals
        self.outgoing = outgoing
    }

    public static let signedOut = RemoteUISnapshot()

    public func remoteMachineID(forWorkspace workspaceID: UUID) -> RemoteMachine.ID? {
        remoteWorkspaces[workspaceID]
    }
}
