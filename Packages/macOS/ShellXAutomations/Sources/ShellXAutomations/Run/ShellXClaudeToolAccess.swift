/// Which tools one headless Claude Code invocation may use.
public enum ShellXClaudeToolAccess: Sendable, Equatable {
    /// The tools the user's settings grant, plus the run's `allowedTools`. Automation runs use this.
    case granted
    /// No tools, no MCP servers and no saved session, for a one-off text answer such as a flowchart.
    case none

    /// Tools that write, run commands or reach the network; denied wherever untrusted text steers Claude.
    public static let writingAndNetworkTools = "Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch"
}
