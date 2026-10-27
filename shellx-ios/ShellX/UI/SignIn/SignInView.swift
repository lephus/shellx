import ShellXAppCore
import SwiftUI

/// Email and password sign-in. Email and password carry the AutoFill content types, so the system
/// can offer saved credentials.
struct SignInView: View {
    let coordinator: AppCoordinator
    let expired: Bool

    @State private var email = ""
    @State private var password = ""
    @State private var error: SignInError?
    @State private var isSigningIn = false
    @FocusState private var focus: Field?
    @ScaledMetric(relativeTo: .largeTitle) private var logoSize: CGFloat = 64

    private enum Field { case email, password }

    init(coordinator: AppCoordinator, expired: Bool, initialError: SignInError? = nil) {
        self.coordinator = coordinator
        self.expired = expired
        _error = State(initialValue: initialError)
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isSigningIn
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

                field {
                    TextField(String(localized: "signin.email"), text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focus, equals: .email)
                        .onSubmit { focus = .password }
                }
                field {
                    SecureField(String(localized: "signin.password"), text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focus, equals: .password)
                        .onSubmit(submit)
                }

                if let error {
                    Text(message(for: error))
                        .font(.callout)
                        .foregroundStyle(Color("StatusError"))
                        .accessibilityIdentifier("signin.error")
                }

                Button(action: submit) {
                    HStack {
                        if isSigningIn { ProgressView() }
                        Text(LocalizedStringResource("signin.button"))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .systemBackground))
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.body)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func message(for error: SignInError) -> String {
        switch error {
        case .invalidCredentials: String(localized: "signin.error.invalidCredentials")
        case .rateLimited: String(localized: "signin.error.rateLimited")
        case .network: String(localized: "signin.error.network")
        case .server: String(localized: "signin.error.server")
        case .localWipePending: String(localized: "signin.error.localWipePending")
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isSigningIn = true
        error = nil
        let address = email.trimmingCharacters(in: .whitespaces)
        let secret = password
        Task {
            do {
                try await coordinator.signIn(email: address, password: secret)
            } catch {
                let failure = error as? SignInError ?? .server(code: "unknown")
                self.error = failure
                AccessibilityNotification.Announcement(message(for: failure)).post()
            }
            isSigningIn = false
        }
    }
}

#if DEBUG
#Preview {
    SignInView(coordinator: .preview(), expired: false)
}
#endif
