/// What one headless `claude` invocation produced.
public struct ShellXClaudeResult: Sendable, Equatable {
    /// Session id from `system/init` or the result event.
    public var sessionId: String?
    /// Final result text.
    public var resultText: String?
    /// Whether the result event reported an error.
    public var isError: Bool
    /// Tool names whose use was denied.
    public var permissionDenials: [String]
    /// Process exit status.
    public var exitCode: Int32
    /// Last part of standard error.
    public var stderrTail: String

    /// Creates a result.
    public init(
        sessionId: String? = nil,
        resultText: String? = nil,
        isError: Bool = false,
        permissionDenials: [String] = [],
        exitCode: Int32 = 0,
        stderrTail: String = ""
    ) {
        self.sessionId = sessionId
        self.resultText = resultText
        self.isError = isError
        self.permissionDenials = permissionDenials
        self.exitCode = exitCode
        self.stderrTail = stderrTail
    }
}
