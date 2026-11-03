/// Failure while loading a launchd job.
public enum ShellXLaunchAgentError: Error, Sendable, Equatable {
    /// `launchctl bootstrap` exited non-zero; carries launchctl's output.
    case bootstrapFailed(status: Int32, output: String)
    /// The automation has no schedule to install.
    case notScheduled(id: String)
}
