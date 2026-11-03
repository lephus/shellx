/// Runs `launchctl` with arguments and reports its exit status and combined output.
public protocol ShellXLaunchctlRunning: Sendable {
    /// Runs launchctl; a non-zero status is returned, not thrown.
    func run(_ arguments: [String]) async throws -> (status: Int32, output: String)
}
