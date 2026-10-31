import Foundation

@MainActor
extension Workspace {
    /// Whether an agent in one of the workspace's panes waits for the person's answer, a
    /// permission or a question (spec 2026-10-29 mobile home focus, §6.7).
    ///
    /// Its sidebar row then runs the waiting border. It reads the per-pane lifecycles the status
    /// pill and the name effect read, but only the needs-input state: a failure elsewhere, which
    /// takes the pill, does not hide an agent that asks. A pane that closed and a manual workspace
    /// loader never count.
    var agentNeedsInput: Bool {
        agentLifecycleStatesByPanelId.contains { panelId, lifecycles in
            panels[panelId] != nil && lifecycles.contains { key, lifecycle in
                lifecycle == .needsInput && !AgentHibernationLifecycleStatusKeys.isManualKey(key)
            }
        }
    }
}
