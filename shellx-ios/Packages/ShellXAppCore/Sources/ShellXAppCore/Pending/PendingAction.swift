import Foundation
import ShellXLinkCore

/// One thing a pending card lets the user do. `PendingItem.actions` lists the ones an item offers.
public enum PendingAction: Equatable, Sendable {
    /// Permission: allow this one call (`once`).
    case allowOnce
    /// Permission: refuse (`deny`).
    case deny
    /// Permission: allow this kind of call from now on (`always`).
    case allowAlways
    /// Permission: allow every tool from now on (`all`).
    case allowAllTools
    /// Question: open the answer sheet.
    case answer
    /// Plan: approve it in this mode.
    case approvePlan(ExitPlanMode)
    /// Plan: send it back with feedback (`deny` plus the user's text).
    case revisePlan
    /// Plan: refuse it (`deny`, no feedback).
    case rejectPlan
    /// Nothing the phone can answer: the card says to open it on the Mac.
    case openOnMac

    /// The decision this action sends as it is; nil when it needs more from a sheet (`answer`,
    /// `revisePlan`) or sends nothing (`openOnMac`).
    public var decision: LinkDecision? {
        switch self {
        case .allowOnce: return .permission(.once)
        case .deny: return .permission(.deny)
        case .allowAlways: return .permission(.always)
        case .allowAllTools: return .permission(.all)
        case let .approvePlan(mode): return .exitPlan(mode, feedback: nil)
        case .rejectPlan: return .exitPlan(.deny, feedback: nil)
        case .answer, .revisePlan, .openOnMac: return nil
        }
    }
}
