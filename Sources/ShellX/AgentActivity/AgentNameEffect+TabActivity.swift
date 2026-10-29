import Bonsplit
import CmuxSidebar

/// How Bonsplit plays an agent name effect, on pane tabs and on sidebar session names alike
/// (spec 2026-10-23 tab selection and agent effects, §6.4).
///
/// The tab activity sync and the sidebar row both read this mapping, so a tab and the session row
/// beside it never disagree on which effect plays or when a skill or workflow flashes.
extension AgentNameEffect {
    /// The Bonsplit effect: ``TabActivity/Kind/working`` shimmers while the agent works, and a
    /// skill or a workflow is a ``TabActivity/Kind/highlight``.
    var tabActivityKind: TabActivity.Kind {
        switch self {
        case .working:
            return .working
        case .skill, .workflow:
            return .highlight
        }
    }

    /// The marker generation of a skill or a workflow, whose change plays the one-time flash, or
    /// `nil` while the agent only works.
    var highlightGeneration: UInt64? {
        switch self {
        case .working:
            return nil
        case .skill(_, let generation), .workflow(_, let generation):
            return generation
        }
    }

    /// The tab activity that plays the effect.
    ///
    /// - Parameter accessibilityLabel: What VoiceOver reads after the tab's title, such as "Thinking…".
    func tabActivity(accessibilityLabel: String) -> TabActivity {
        TabActivity(
            kind: tabActivityKind,
            generation: highlightGeneration ?? 0,
            accessibilityLabel: accessibilityLabel
        )
    }
}
