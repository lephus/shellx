import CmuxSidebar
import Foundation

/// The words for an agent name effect on a sidebar row's agent status line
/// (spec 2026-10-23 tab selection and agent effects, §6.5).
///
/// "Thinking…" while the agent works, "Skill · ‹name›" or "Workflow · ‹name›"
/// while it runs one, and just the kind when the hook payload carried no name.
/// Pane tabs read the same words to VoiceOver.
struct AgentActivityText {
    /// Where the words are looked up: the app bundle, in the app's language.
    let bundle: Bundle

    /// Creates the text source.
    ///
    /// - Parameter bundle: Where the words are looked up. Tests pass one
    ///   language's `.lproj` folder to read that language whatever the host's is.
    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// The localized activity text for an effect.
    func text(for effect: AgentNameEffect) -> String {
        switch effect {
        case .working:
            return String(localized: "sidebar.agentActivity.thinking", defaultValue: "Thinking…", bundle: bundle)
        case .skill(let name, _):
            guard let name else {
                return String(localized: "sidebar.agentActivity.skillUnnamed", defaultValue: "Skill", bundle: bundle)
            }
            return String(
                format: String(localized: "sidebar.agentActivity.skill", defaultValue: "Skill · %@", bundle: bundle),
                name
            )
        case .workflow(let name, _):
            guard let name else {
                return String(localized: "sidebar.agentActivity.workflowUnnamed", defaultValue: "Workflow", bundle: bundle)
            }
            return String(
                format: String(localized: "sidebar.agentActivity.workflow", defaultValue: "Workflow · %@", bundle: bundle),
                name
            )
        }
    }
}
