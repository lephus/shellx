import ShellXAppCore
import SwiftUI
import UIKit

/// Sign in with a code sent by email, with Google or with Apple. There is no password field.
///
/// The first screen is the email step: an intro, then the email field with Send code, "or", Google, Apple and the
/// demo link. The intro is the logo whose chevrons slide in (`SignInLogoView`), the title, three taglines typed one
/// after another (`TypedTaglineView`) and three steps that appear in turn (`SignInGuideView`). The field and the
/// buttons are there and work from the first frame; the intro never holds them back or moves them. With Reduce Motion
/// on, and in tests and screenshots, the intro is still (`SignInIntroMotion`). Nothing takes the keyboard when the
/// screen appears.
///
/// The layout follows the room inside the safe area (`SignInLayout`). Portrait: one column, top to bottom. Landscape:
/// the logo, the title and the taglines on the left, the steps, the field and the buttons on the right. While the
/// keyboard is up, an address is typed or the code step shows, the intro folds to a small logo and the title. One
/// tree serves both arrangements, so turning the phone keeps what is typed and the keyboard.
struct SignInView: View {
    let coordinator: AppCoordinator
    let expired: Bool
    let notice: SignInNotice?
    let startDemo: (() -> Void)?
    /// The intro's motion when the caller fixes it (render tests); nil: decided from Reduce Motion and the kind of
    /// run.
    private let fixedMotion: SignInIntroMotion?
    /// Whether the keyboard is up, when the caller fixes it (render tests); nil: as the system says.
    private let fixedKeyboard: Bool?

    @State private var error: SignInError?
    @State private var running: Provider?
    @State private var keyboardUp = false
    /// A new value puts the keyboard in the email field: on the way back from the code step.
    @State private var emailFocus = 0
    /// When this screen appeared: the intro plays once from then, however often the view is drawn or turned.
    @State private var introStart = Date()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Provider { case google, apple }

    init(
        coordinator: AppCoordinator, expired: Bool, notice: SignInNotice? = nil, startDemo: (() -> Void)? = nil,
        initialError: SignInError? = nil, motion: SignInIntroMotion? = nil, keyboardUp: Bool? = nil
    ) {
        self.coordinator = coordinator
        self.expired = expired
        self.notice = notice
        self.startDemo = startDemo
        fixedMotion = motion
        fixedKeyboard = keyboardUp
        _error = State(initialValue: initialError)
    }

    private var motion: SignInIntroMotion {
        fixedMotion ?? SignInIntroMotion.decide(reduceMotion: reduceMotion, underTest: SignInIntroMotion.underTest)
    }

    private var model: EmailSignInModel { coordinator.emailSignIn }

    /// The intro folds while the keyboard is up, while an address is typed (so it does not unfold under the user's
    /// eyes when the keyboard goes down), and in the code step.
    private var folded: Bool {
        (fixedKeyboard ?? keyboardUp) || model.panel == .code
            || !model.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// How a change of step or of the fold moves: not at all with Reduce Motion.
    private var change: Animation? {
        motion == .animated ? .snappy(duration: 0.25) : nil
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = SignInLayout(size: proxy.size, folded: folded)
            ScrollView {
                content(layout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.appBackground)
        .animation(change, value: model.panel)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(change) { keyboardUp = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(change) { keyboardUp = false }
        }
        // The screen starts at the email step (the model starts idle, and is done after a sign-in).
        .onAppear { model.begin() }
        .onChange(of: model.error) { _, failure in
            // A new failure is read out, as Google's is.
            if let failure, let text = SignInErrorText.message(for: failure) {
                AccessibilityNotification.Announcement(text).post()
            }
        }
    }

    /// One tree for both arrangements: turning the phone moves the parts and keeps them (the field, its text and the
    /// keyboard).
    private func content(_ layout: SignInLayout) -> some View {
        let arrangement = layout.sideBySide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 32))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
        return arrangement {
            hero(layout)
                .frame(maxWidth: layout.sideBySide ? .infinity : nil, alignment: .leading)
            VStack(alignment: .leading, spacing: 16) {
                if layout.showsGuide { SignInGuideView(motion: motion, start: introStart) }
                if model.panel != .code { notices }
                actions
            }
            .frame(maxWidth: layout.sideBySide ? .infinity : nil)
        }
        .frame(maxWidth: layout.sideBySide ? 820 : 520)
    }

    /// The logo, the title, the typed taglines and, in a tall window, the subtitle; folded, the logo and the title.
    private func hero(_ layout: SignInLayout) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SignInLogoView(size: layout.logoSize, motion: motion, start: introStart)
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringResource("signin.title"))
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if layout.showsTaglines { TypedTaglineView(motion: motion, start: introStart) }
            }
            if layout.showsSubtitle {
                Text(LocalizedStringResource("signin.subtitle"))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// What the first screen has to say over the field: the session expired, a notice, Google's or Apple's last
    /// failure. A failure of the email step shows under the field instead.
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

    /// The rows under the intro, one under the other, 12 points apart: the email field and Send code, "or", Google,
    /// Apple and the demo link. A further way to sign in is one more row.
    private var actions: some View {
        VStack(spacing: 12) {
            EmailEntryRows(model: model, focusRequest: emailFocus, enabled: running == nil, send: sendCode)

            SignInOrDivider()

            // While a code is asked for, the other ways in wait.
            Group {
                GoogleSignInButton(busy: running == .google) { run(.google) }
                AppleSignInButton { run(.apple) }
                    .id(colorScheme)
                    .frame(height: 44)
            }
            .disabled(running != nil || model.isBusy)

            if let startDemo {
                Button(action: startDemo) {
                    Text(LocalizedStringResource("signin.demo"))
                        .foregroundStyle(Color("AccentText"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(model.isBusy)
                .accessibilityIdentifier("signin.demo")
            }
        }
    }

    /// Send code, or the return key of the email field: mails a code to the address.
    private func sendCode() {
        model.begin()
        guard running == nil, model.canSend else { return }
        error = nil
        Task { await model.sendCode() }
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
