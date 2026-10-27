import ShellXAppCore
import SwiftUI

/// Chooses the screen by the account phase: the logo while launching, sign-in, or Settings.
struct RootView: View {
    let coordinator: AppCoordinator

    var body: some View {
        switch coordinator.phase {
        case .launching:
            LaunchView()
        case let .signedOut(expired):
            SignInView(coordinator: coordinator, expired: expired)
        case let .signedIn(email):
            NavigationStack {
                SettingsView(email: email, signOut: { await coordinator.signOut() })
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
        .background(Color(uiColor: .systemBackground))
    }
}

#Preview {
    RootView(coordinator: .preview())
}
