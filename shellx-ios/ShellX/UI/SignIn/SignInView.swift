import ShellXAppCore
import SwiftUI

/// Sign in with Google or Apple. There is no password field.
///
/// Above the buttons, an intro: the logo whose chevrons slide in (`SignInLogoView`), the title, three taglines typed
/// one after another (`TypedTaglineView`) and three steps that appear in turn (`SignInGuideView`). The buttons are
/// there and work from the first frame; the intro never holds them back or moves them. With Reduce Motion on, and
/// in tests and screenshots, the intro is still (`SignInIntroMotion`).
///
/// The layout follows the room inside the safe area (`SignInLayout`). Portrait: one column, top to bottom. Landscape:
/// the logo, the title and the taglines on the left, the steps and the buttons on the right.
struct SignInView: View {
    let coordinator: AppCoordinator
    let expired: Bool
    let notice: SignInNotice?
    let startDemo: (() -> Void)?
    /// The intro's motion when the caller fixes it (render tests); nil: decided from Reduce Motion and the kind of
    /// run.
    private let fixedMotion: SignInIntroMotion?

    @State private var error: SignInError?
    @State private var running: Provider?
    /// When this screen appeared: the intro plays once from then, however often the view is drawn or turned.
    @State private var introStart = Date()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Provider { case google, apple }

    init(
        coordinator: AppCoordinator, expired: Bool, notice: SignInNotice? = nil, startDemo: (() -> Void)? = nil,
        initialError: SignInError? = nil, motion: SignInIntroMotion? = nil
    ) {
        self.coordinator = coordinator
        self.expired = expired
        self.notice = notice
        self.startDemo = startDemo
        fixedMotion = motion
        _error = State(initialValue: initialError)
    }

    private var motion: SignInIntroMotion {
        fixedMotion ?? SignInIntroMotion.decide(reduceMotion: reduceMotion, underTest: SignInIntroMotion.underTest)
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = SignInLayout(size: proxy.size)
            ScrollView {
                content(layout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color.appBackground)
    }

    @ViewBuilder
    private func content(_ layout: SignInLayout) -> some View {
        if layout.sideBySide {
            HStack(alignment: .top, spacing: 32) {
                hero(layout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 16) {
                    if layout.showsGuide { SignInGuideView(motion: motion, start: introStart) }
                    notices
                    actions
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 820)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                hero(layout)
                if layout.showsGuide { SignInGuideView(motion: motion, start: introStart) }
                notices
                actions
            }
            .frame(maxWidth: 520)
        }
    }

    /// The logo, the title, the typed taglines and, in a tall window, the subtitle.
    private func hero(_ layout: SignInLayout) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SignInLogoView(size: layout.logoSize, motion: motion, start: introStart)
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringResource("signin.title"))
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                TypedTaglineView(motion: motion, start: introStart)
            }
            if layout.showsSubtitle {
                Text(LocalizedStringResource("signin.subtitle"))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// What the screen has to say before the buttons: the session expired, a notice, the last failure.
    @ViewBuilder private var notices: some View {
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
    }

    /// The buttons, one under the other, 12 points apart: a further way to sign in is one more row.
    private var actions: some View {
        VStack(spacing: 12) {
            Group {
                GoogleSignInButton(busy: running == .google) { run(.google) }
                AppleSignInButton { run(.apple) }
                    .id(colorScheme)
                    .frame(height: 44)
            }
            .disabled(running != nil)

            if let startDemo {
                Button(action: startDemo) {
                    Text(LocalizedStringResource("signin.demo"))
                        .foregroundStyle(Color("AccentText"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("signin.demo")
            }
        }
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
