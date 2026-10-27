import Foundation
import ShellXLinkCore

extension PendingItem {
    /// The buttons this item's card offers, in the order the card shows them. A mode only becomes a
    /// button when the Mac listed it in `modes`; a mode this app does not know (`bypass`,
    /// `bypassPermissions` or anything newer) never does. With nothing to offer the card says to
    /// open it on the Mac (`[.openOnMac]`), as for a kind this app does not know.
    public var actions: [PendingAction] {
        let offered: [PendingAction]
        switch kind {
        case .permission:
            let buttons: [(PermissionMode, PendingAction)] = [
                (.once, .allowOnce), (.deny, .deny), (.always, .allowAlways), (.all, .allowAllTools),
            ]
            offered = buttons.filter { modes.contains($0.0.wire) }.map(\.1)
        case .question:
            let questions = questions ?? []
            // Answers are kept by question id, so two questions sharing one cannot be answered here.
            let answerable = !questions.isEmpty && questions.allSatisfy { !$0.options.isEmpty }
                && Set(questions.map(\.id)).count == questions.count
            offered = answerable ? [.answer] : []
        case .exitPlan:
            let approvals = [ExitPlanMode.manual, .autoAccept, .ultraplan]
                .filter { modes.contains($0.wire) }
                .map(PendingAction.approvePlan)
            let refusals: [PendingAction] = modes.contains(ExitPlanMode.deny.wire) ? [.revisePlan, .rejectPlan] : []
            offered = approvals + refusals
        case .other:
            offered = []
        }
        return offered.isEmpty ? [.openOnMac] : offered
    }
}
