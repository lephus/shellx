import ShellXAppCore
import SwiftUI

/// The sheet over the pending cards, fed by its `PendingSheetModel`: it closes once its own
/// decision is taken, and tells VoiceOver when the item was decided elsewhere meanwhile. While it is
/// up it counts in the environment's `SheetPresence`, so a pairing link opened meanwhile waits.
struct PendingSheetHost: View {
    let route: PendingRoute
    let close: () -> Void

    @Environment(SheetPresence.self) private var sheets: SheetPresence?

    private var model: PendingSheetModel { route.model }

    var body: some View {
        let state = PendingSheetState(model)
        Group {
            if let item = model.opened {
                switch route.kind {
                case .question:
                    QuestionAnswerSheet(item: item, state: state, send: send, close: close)
                case .plan:
                    PlanReviewSheet(item: item, state: state, send: send, close: close)
                case .fullText:
                    FullTextSheet(item: item.item, close: close)
                }
            }
        }
        .onChange(of: state.status) { _, status in
            if status == .done { close() }
        }
        .onChange(of: state.handledElsewhere) { _, handled in
            guard handled else { return }
            AccessibilityNotification.Announcement(String(localized: "pending.status.handledElsewhere")).post()
        }
        .onAppear { sheets?.opened() }
        .onDisappear { sheets?.closed() }
    }

    private func send(_ decision: LinkDecision) {
        Task { await model.send(decision) }
    }
}
