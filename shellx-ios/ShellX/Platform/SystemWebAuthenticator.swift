import AuthenticationServices
import ShellXAppCore
import UIKit

/// Google's page in the system's web sign-in sheet (S1 §4: never an embedded web view). The session catches its own
/// callback scheme, so no `CFBundleURLTypes` entry is needed.
@MainActor
final class SystemWebAuthenticator: NSObject, WebAuthenticating, @preconcurrency ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let completion: @Sendable (URL?, (any Error)?) -> Void = { callback, error in
                Task { @MainActor [weak self] in self?.session = nil }
                if let error {
                    let canceled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    continuation.resume(throwing: canceled ? IdentityProviderError.cancelled : IdentityProviderError.failed)
                } else if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: IdentityProviderError.failed)
                }
            }
            let session: ASWebAuthenticationSession
            if #available(iOS 17.4, *) {
                session = ASWebAuthenticationSession(
                    url: url, callback: .customScheme(callbackScheme), completionHandler: completion)
            } else {
                session = ASWebAuthenticationSession(
                    url: url, callbackURLScheme: callbackScheme, completionHandler: completion)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                self.session = nil
                continuation.resume(throwing: IdentityProviderError.failed)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        keyWindowAnchor()
    }
}

/// The key window of the foreground-active scene: where the system sheets appear.
@MainActor
func keyWindowAnchor() -> UIWindow {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    return scene?.keyWindow ?? scene?.windows.first ?? UIWindow()
}
