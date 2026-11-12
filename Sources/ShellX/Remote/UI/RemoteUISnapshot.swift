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
            browser: String(localized: "remote.signin.error.browser", defaultValue: "Couldn't open your browser."),
            invalidEmail: String(
                localized: "remote.signin.error.invalidEmail",
                defaultValue: "That doesn't look like an email address."
            ),
            disposableEmail: String(
                localized: "remote.signin.error.disposableEmail",
                defaultValue: "Temporary email addresses can't be used. Try another address."
            ),
            invalidCode: String(
                localized: "remote.signin.error.invalidCode",
                defaultValue: "That code isn't right. Check the email and try again."
            ),
            codeExpired: String(
                localized: "remote.signin.error.codeExpired",
                defaultValue: "That code no longer works. Send a new one."
            ),
            emailSendFailed: String(
                localized: "remote.signin.error.emailSendFailed",
                defaultValue: "Couldn't send the email. Try again in a moment."
            ),
            unavailable: String(
                localized: "remote.signin.error.unavailable",
                defaultValue: "This way of signing in isn't available in this build."
            ),
            rateLimited: String(localized: "remote.signin.error.rateLimited", defaultValue: "Try again in a few minutes."),
            server: String(
                localized: "remote.signin.error.server",
                defaultValue: "ShellX is having a problem. Try again later."
            )
        )
    }
}

extension EmailSignInTexts {
    static var localized: EmailSignInTexts {
        EmailSignInTexts(
            field: String(localized: "remote.signin.email.field", defaultValue: "Email address"),
            send: String(localized: "remote.signin.email.send", defaultValue: "Send code"),
            or: String(localized: "remote.signin.email.or", defaultValue: "or"),
            sentToFormat: String(
                localized: "remote.signin.email.sentTo",
                defaultValue: "We sent a 6-digit code to %@. If it isn't there in a minute, check your spam folder."
            ),
            code: String(localized: "remote.signin.email.code", defaultValue: "6-digit code"),
            verify: String(localized: "remote.signin.email.verify", defaultValue: "Verify"),
            resend: String(localized: "remote.signin.email.resend", defaultValue: "Resend code"),
            resendInFormat: String(localized: "remote.signin.email.resendIn", defaultValue: "Resend code in %@ s"),
            change: String(localized: "remote.signin.email.change", defaultValue: "Use a different email")
        )
    }
}
