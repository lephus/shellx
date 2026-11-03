public import Foundation

/// Why the notifier helper could not be launched.
public enum ShellXNotifierError: Error, Equatable, Sendable, LocalizedError {
    /// `/usr/bin/open` exited with `status`.
    case openFailed(status: Int32)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let status): "open exited with status \(status) while launching ShellX Notifier."
        }
    }
}
