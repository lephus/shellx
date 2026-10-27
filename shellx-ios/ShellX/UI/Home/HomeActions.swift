import ShellXAppCore
import SwiftUI

/// What the home's controls do, wired to the signed-in scope. Built outside the view body, so a
/// test can run each action and see the model call it makes:
/// - the toolbar and "See all" push `HomeRoute`s through `open`;
/// - "Send to:" sets `HomeModel.target`; the composer starts a message (`HomeModel.beginMessage`)
///   when the mic is pressed or the field focused, and sends it with `HomeModel.submit` to
///   `messageTarget`, read when the user sends (`viaVoice` for what was said into the mic, which
///   also ends the message);
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
            beginMessage: { home.beginMessage() },
            endMessage: { home.endMessage() },
            send: { text in
                // Typed: where the chip pointed when the field got focus. The field stays open, so
                // the message goes on until the keyboard closes empty.
                let target = home.messageTarget
                sent(Task { await home.submit(text, to: target, viaVoice: false) })
            },
            sendVoice: { text in
                // Said: where the chip pointed when the mic was pressed; the release ends it.
                let target = home.messageTarget
                home.endMessage()
                sent(Task { await home.submit(text, to: target, viaVoice: true) })
            },
            card: { item in PendingCardsSection.actions(for: item, hub: hub, center: center, route: route) })
    }
}
