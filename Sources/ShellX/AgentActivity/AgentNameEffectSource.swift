import CmuxSidebar

/// The effect a session row plays and the agent behind it (spec 2026-10-23 tab selection and agent
/// effects, §6.3 and §6.5).
///
/// A session row plays the strongest effect among its panes. While it does, one status row says
/// what the agent behind that effect does ("Thinking…", "Skill · name"), in place of that agent's
/// own status. An agent can show its status on more than one row: Claude Code reports a turn
/// through its hooks (the `claude_code` row) and over OSC 7501 (the program-status row,
/// "claude-code · Working"). The first such row in display order takes the activity and the others
/// leave, so the session shows the agent's status once and gains no line when a turn starts.
/// Other agents' rows keep their own status.
///
/// ```swift
/// if let source = workspace.strongestAgentNameEffectSource {
///     let status = source.foldingAgentStatus(of: rows)
///     // status.rows: what the row lists; status.activityStatusKey: the row that says what the agent does
/// }
/// ```
struct AgentNameEffectSource: Equatable {
    /// The strongest effect among the workspace's panes.
    let effect: AgentNameEffect

    /// The status key of the agent behind ``effect``, such as `claude_code` or `codex`.
    let statusKey: String

    /// Whether the workspace's program-status row is that agent's own report that it works, sent
    /// from a pane where it plays the effect.
    let ownsProgramStatusRow: Bool

    /// The status rows with the agent's status on one row.
    ///
    /// - Parameter rows: The workspace's status rows in display order.
    /// - Returns: `rows` without the agent's later status rows, and the key of the row that says
    ///   what the agent does, or `nil` when no row shows the agent.
    func foldingAgentStatus(
        of rows: [SidebarStatusEntry]
    ) -> (rows: [SidebarStatusEntry], activityStatusKey: String?) {
        var activityStatusKey: String?
        let folded = rows.filter { entry in
            guard showsAgentStatus(entry) else { return true }
            guard activityStatusKey == nil else { return false }
            activityStatusKey = entry.key
            return true
        }
        return (folded, activityStatusKey)
    }

    private func showsAgentStatus(_ entry: SidebarStatusEntry) -> Bool {
        entry.key == statusKey || (ownsProgramStatusRow && entry.key == Workspace.programStatusKey)
    }
}
