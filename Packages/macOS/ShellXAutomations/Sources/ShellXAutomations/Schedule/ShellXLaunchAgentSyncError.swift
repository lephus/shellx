/// One or more automations could not be reconciled by `sync`; the rest were still processed.
public struct ShellXLaunchAgentSyncError: Error, Sendable {
    /// Automation ids that failed, with a readable message.
    public let failures: [(id: String, message: String)]

    /// Creates the error.
    public init(failures: [(id: String, message: String)]) {
        self.failures = failures
    }
}
