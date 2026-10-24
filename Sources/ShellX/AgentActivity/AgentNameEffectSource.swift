import CmuxSidebar

/// The effect a session row plays and the agent behind it (spec 2026-10-23 tab selection and agent
/// effects, §6.3 and §6.5).
///
/// A session row plays the strongest effect among its panes. While it does, the status row of the
/// agent behind that effect says what the agent does ("Thinking…", "Skill · name"), in place of
/// that agent's own status. Other rows, including Claude Code's own OSC program-status row, keep
/// their own status and stay their own lines, so the row keeps its height across a turn.
///
/// ```swift
/// if let source = workspace.strongestAgentNameEffectSource {
///     let key = source.activityStatusKey(in: rows)
///     // key: the row that says what the agent does
/// }
/// ```
struct AgentNameEffectSource: Equatable {
    /// The strongest effect among the workspace's panes.
    let effect: AgentNameEffect

    /// The status key of the agent behind ``effect``, such as `claude_code` or `codex`.
    let statusKey: String

    /// The key of the row that says what the agent does.
    ///
    /// - Parameter rows: The workspace's status rows in display order.
    /// - Returns: The first row that shows the agent, or `nil` when no row does.
    func activityStatusKey(in rows: [SidebarStatusEntry]) -> String? {
        rows.first { $0.key == statusKey }?.key
    }
}
