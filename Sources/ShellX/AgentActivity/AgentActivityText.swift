import CmuxSidebar
import Foundation

/// The words for an agent name effect on a sidebar row's agent status line
/// (spec 2026-10-23 tab selection and agent effects, §6.5).
///
/// "Thinking…" while the agent works, "Skill · ‹name›" or "Workflow · ‹name›"
/// while it runs one, and just the kind when the hook payload carried no name.
struct AgentActivityText {
    /// The localized activity text for an effect.
    func text(for effect: AgentNameEffect) -> String {
        switch effect {
        case .working:
            return String(localized: "sidebar.agentActivity.thinking", defaultValue: "Thinking…")
        case .skill(let name, _):
            guard let name else {
                return String(localized: "sidebar.agentActivity.skillUnnamed", defaultValue: "Skill")
            }
            return String(
                format: String(localized: "sidebar.agentActivity.skill", defaultValue: "Skill · %@"),
                name
            )
        case .workflow(let name, _):
            guard let name else {
                return String(localized: "sidebar.agentActivity.workflowUnnamed", defaultValue: "Workflow")
            }
            return String(
                format: String(localized: "sidebar.agentActivity.workflow", defaultValue: "Workflow · %@"),
                name
            )
        }
    }
}
