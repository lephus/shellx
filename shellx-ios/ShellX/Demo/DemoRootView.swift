import ShellXAppCore
import SwiftUI

/// The demo's screens: the signed-in app of the demo account, under the "Demo · Exit" banner.
struct DemoRootView: View {
    let graph: AppGraph
    let exit: () -> Void
    @State private var inbox = PairingInbox()
    @State private var pushTaps = PushTapInbox()

    private var coordinator: AppCoordinator { graph.coordinator }

    var body: some View {
        VStack(spacing: 0) {
            DemoBanner(exit: exit)
            if case let .signedIn(email) = coordinator.phase, let hub = coordinator.hub, hub.isLoaded,
                let scope = graph.scopes.scope(for: hub)
            {
                SignedInView(
                    scope: scope, email: email, inbox: inbox, pushTaps: pushTaps, push: nil, account: nil,
                    startDemo: nil)
                    .id(ObjectIdentifier(hub))
            } else {
                LaunchView()
            }
        }
        .background(Color.appBackground)
    }
}
