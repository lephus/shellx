import ShellXAppCore
import SwiftUI

/// The words for a failure or a notice; shared by the sign-in screen and Settings › Account.
enum SignInErrorText {
    /// nil for `.cancelled`: closing Google's or Apple's sheet is not an error.
    static func message(for error: SignInError) -> String? {
        switch error {
        case .invalidCredentials: String(localized: "signin.error.invalidCredentials")
        case .rateLimited: String(localized: "signin.error.rateLimited")
        case .network: String(localized: "signin.error.network")
        case .server: String(localized: "signin.error.server")
        case .localWipePending: String(localized: "signin.error.localWipePending")
        case .cancelled: nil
        case .switchFromSignedInDevice: String(localized: "signin.error.switchFromSignedInDevice")
        case .emailInUse: String(localized: "signin.error.emailInUse")
        case .identityInUse: String(localized: "signin.error.identityInUse")
        case .reauthRequired: String(localized: "signin.error.reauthRequired")
        case .providerUnavailable: String(localized: "signin.error.providerUnavailable")
        case .providerFailed: String(localized: "signin.error.providerFailed")
        case .switchToGoogleFirst: String(localized: "settings.account.delete.switchFirst")
        }
    }

    static func message(for notice: SignInNotice) -> String {
        switch notice {
        case .appleLinkDenied: String(localized: "signin.apple.linkDenied")
        case .appleLinkExpired: String(localized: "signin.apple.linkExpired")
        case .appleLinkFailed: String(localized: "signin.apple.linkFailed")
        }
    }
}
