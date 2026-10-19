import Foundation
import ShellXRemoteCore
import ShellXRemoteUI

extension RemoteUISnapshot {
    /// Reads the service's published state at this moment.
    @MainActor
    init(service: any ShellXRemoteServicing) {
        self.init(
            machines: service.machines.filter { !$0.isThisMachine },
            isSignedIn: service.isSignedIn,
            remoteWorkspaces: service.remoteWorkspaces,
            pendingApprovals: service.pendingApprovals,
            outgoing: service.outgoing
        )
    }
}

extension RemoteMachineLabels {
    static var localized: RemoteMachineLabels {
        RemoteMachineLabels(
            offlineLastSeen: String(localized: "remote.machine.offline", defaultValue: "offline · last seen %@"),
            neverSeen: "\u{2014}"
        )
    }
}

extension SignInErrorLabels {
    static var localized: SignInErrorLabels {
        SignInErrorLabels(
            credentials: String(
                localized: "remote.signin.error.credentials",
                defaultValue: "Email or password is incorrect"
            ),
            network: String(localized: "remote.signin.error.network", defaultValue: "Can't reach relay.shellx.pro")
        )
    }
}
