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
                defaultValue: "Google sign-in didn't work. Try again."
            ),
            network: String(localized: "remote.signin.error.network", defaultValue: "Can't reach relay.shellx.pro"),
            timeout: String(
                localized: "remote.signin.error.timeout",
                defaultValue: "Google sign-in timed out. Try again."
            ),
            stateMismatch: String(
                localized: "remote.signin.error.stateMismatch",
                defaultValue: "Sign-in didn't finish. Try again."
            ),
            switchFromSignedInDevice: String(
                localized: "remote.signin.error.switchFromSignedInDevice",
                defaultValue: "This email already has a ShellX account. Open ShellX on a device that is still signed in, go to Settings › Account › Switch to Google sign-in, then try again."
            ),
            emailInUse: String(
                localized: "remote.signin.error.emailInUse",
                defaultValue: "Another ShellX account already uses this Google account's email. Choose a different Google account."
            ),
            identityInUse: String(
                localized: "remote.signin.error.identityInUse",
                defaultValue: "This Google account already signs in to another ShellX account, or this account already uses another Google account."
            ),
            browser: String(localized: "remote.signin.error.browser", defaultValue: "Couldn't open your browser.")
        )
    }
}
