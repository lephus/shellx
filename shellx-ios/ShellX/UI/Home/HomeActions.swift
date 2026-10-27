import ShellXAppCore
import SwiftUI

/// What the home's controls do, wired to the signed-in scope. Built outside the view body, so a
/// test can run each action and see the model call it makes:
/// - the toolbar and "See all" push `HomeRoute`s through `open`;
/// - "Send to:" sets `HomeModel.target`; the composer calls `HomeModel.submit`;
/// - a card's decisions go to `DecisionCenter`; "Answer", "Review plan" and "Show more" set `route`.
@MainActor
enum HomeActions {
    /// `sent` gets the task of each send, so a caller (a test) can wait for it.
    static func make(
        scope: SignedInScope, open: @escaping (HomeRoute) -> Void, route: Binding<PendingRoute?>,
        sent: @escaping (Task<ComposerValidation, Never>) -> Void = { _ in }
    ) -> HomeScreen.Actions {
        let home = scope.home
        let hub = scope.hub
        let center = scope.decisions
        return HomeScreen.Actions(
            openMachines: { open(.machines) },
            openSettings: { open(.settings) },
            seeAllPending: { open(.pending) },
            choose: { home.target = $0 },
            send: { text in sent(Task { await home.submit(text, viaVoice: false) }) },
            card: { item in PendingCardsSection.actions(for: item, hub: hub, center: center, route: route) })
    }
}
