import Foundation
import ShellXRemoteCore

/// Localized sign-in failures, injected so this module needs no bundle.
public struct SignInErrorLabels: Equatable, Sendable {
    public let credentials: String
    public let network: String

    public init(credentials: String, network: String) {
        self.credentials = credentials
        self.network = network
    }

    public static let english = SignInErrorLabels(
        credentials: "Email or password is incorrect",
        network: "Can't reach relay.shellx.pro"
    )
}

/// The inline text the sign-in sheet shows for a failed attempt.
public enum SignInErrorMessage {
    /// `invalid_credentials` and `network` read as sentences; any other code
    /// is shown as is.
    public static func text(forCode code: String, labels: SignInErrorLabels) -> String {
        switch code {
        case "invalid_credentials": return labels.credentials
        case "network": return labels.network
        default: return code
        }
    }

    /// A non-core error (the transport threw before the core answered) reads
    /// as a network failure.
    public static func text(for error: any Error, labels: SignInErrorLabels) -> String {
        guard let coreError = error as? ShellXCoreError else { return labels.network }
        return text(forCode: coreError.code, labels: labels)
    }
}
