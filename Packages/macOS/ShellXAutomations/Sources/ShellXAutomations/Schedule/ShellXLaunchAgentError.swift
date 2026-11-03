/// Failure while loading a launchd job.
public enum ShellXLaunchAgentError: Error, Sendable, Equatable {
    /// `launchctl bootstrap` exited non-zero; carries launchctl's output.
    case bootstrapFailed(status: Int32, output: String)
    /// `launchctl bootout` failed for a reason other than "not loaded".
    case bootoutFailed(status: Int32, output: String)
    /// The automation id is not a plain identifier (contains `.` or `/`, or is empty).
    case invalidIdentifier(id: String)
    /// The automation has no schedule to install.
    case notScheduled(id: String)
}
