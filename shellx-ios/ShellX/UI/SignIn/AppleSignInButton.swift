import AuthenticationServices
import SwiftUI

/// Apple's own button (HIG): `.whiteOutline` in light mode and `.white` in dark mode, 44 pt high with the same pill as
/// Google's. It only reports the tap: the app fetches the relay's nonce first, then runs the request. Give it
/// `.id(colorScheme)` so a change of appearance makes a new one.
struct AppleSignInButton: UIViewRepresentable {
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: .signIn,
            authorizationButtonStyle: colorScheme == .dark ? .white : .whiteOutline)
        button.cornerRadius = 22
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        button.accessibilityIdentifier = "signin.apple"
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = context.environment.isEnabled
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}
