/// Why the notifier helper could not be launched.
public enum ShellXNotifierError: Error, Equatable, Sendable {
    /// `/usr/bin/open` exited with `status`.
    case openFailed(status: Int32)
}
