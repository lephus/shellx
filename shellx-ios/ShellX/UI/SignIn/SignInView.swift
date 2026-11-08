import ShellXAppCore
import SwiftUI

/// Sign in with Google or Apple. There is no password field.
struct SignInView: View {
    let coordinator: AppCoordinator
    let expired: Bool
    let notice: SignInNotice?

    @State private var error: SignInError?
    @State private var running: Provider?
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .largeTitle) private var logoSize: CGFloat = 64

    private enum Provider { case google, apple }

    init(coordinator: AppCoordinator, expired: Bool, notice: SignInNotice? = nil, initialError: SignInError? = nil) {
        self.coordinator = coordinator
        self.expired = expired
        self.notice = notice
        _error = State(initialValue: initialError)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: logoSize, height: logoSize)
                    .accessibilityHidden(true)
                Text(LocalizedStringResource("signin.title"))
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(LocalizedStringResource("signin.subtitle"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                if expired {
                    Text(LocalizedStringResource("signin.expired"))
                        .font(.callout)
                        .foregroundStyle(Color("StatusNeedsYou"))
                        .accessibilityIdentifier("signin.expired")
                }
                if let notice {
                    Text(SignInErrorText.message(for: notice))
                        .font(.callout)
                        .foregroundStyle(Color("StatusNeedsYou"))
                        .accessibilityIdentifier("signin.notice")
                }
                if let error, let text = SignInErrorText.message(for: error) {
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(Color("StatusError"))
                        .accessibilityIdentifier("signin.error")
                }

                VStack(spacing: 12) {
                    GoogleSignInButton(busy: running == .google) { run(.google) }
                    AppleSignInButton { run(.apple) }
                        .id(colorScheme)
                        .frame(height: 44)
                }
                .disabled(running != nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
    }

    private func run(_ provider: Provider) {
        guard running == nil else { return }
        running = provider
        error = nil
        Task {
            do {
                switch provider {
                case .google: try await coordinator.signInWithGoogle()
                case .apple: try await coordinator.signInWithApple()
                }
            } catch {
                let failure = error as? SignInError ?? .server(code: "unknown")
                // Closing Google's or Apple's sheet is not an error: nothing is shown.
                if let text = SignInErrorText.message(for: failure) {
                    self.error = failure
                    AccessibilityNotification.Announcement(text).post()
                }
            }
            running = nil
        }
    }
}
