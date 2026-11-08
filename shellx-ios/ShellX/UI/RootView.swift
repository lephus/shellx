import ShellXAppCore
import SwiftUI

/// Chooses the screen by the account phase: the logo while launching, sign-in, or the signed-in
/// screens.
struct RootView: View {
    let graph: AppGraph
    /// A `shellx-link://` link opened from outside, held until a signed-in screen takes it.
    let inbox: PairingInbox
    /// Taps on a "needs you" alert, opened once signed in.
    var pushTaps = PushTapInbox()

    private var coordinator: AppCoordinator { graph.coordinator }

    var body: some View {
        switch coordinator.phase {
        case .launching:
            LaunchView()
        case let .signedOut(expired):
            SignInView(coordinator: coordinator, expired: expired)
        case .linkingApple:
            LaunchView()
        case let .signedIn(email):
            if let hub = coordinator.hub, hub.isLoaded, let scope = graph.scopes.scope(for: hub) {
                SignedInView(
                    scope: scope, email: email, inbox: inbox, pushTaps: pushTaps, push: graph.push,
                    signOut: { await coordinator.signOut() })
                    .id(ObjectIdentifier(hub))
            } else {
                LaunchView()
            }
        }
    }
}

/// The ShellX logo and name.
struct LaunchView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var logoSize: CGFloat = 96

    var body: some View {
        VStack(spacing: 16) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: logoSize, height: logoSize)
                .accessibilityHidden(true)
            Text(LocalizedStringResource("root.title"))
                .font(.largeTitle.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
}

#if DEBUG
#Preview {
    RootView(graph: .preview(), inbox: PairingInbox())
}
#endif
