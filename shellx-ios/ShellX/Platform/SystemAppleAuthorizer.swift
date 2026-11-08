import AuthenticationServices
import ShellXAppCore
import UIKit

/// Sign in with Apple through `ASAuthorizationController`: scope `.email` only, with the hashed relay nonce.
@MainActor
final class SystemAppleAuthorizer: NSObject, @preconcurrency ASAuthorizationControllerDelegate,
    @preconcurrency ASAuthorizationControllerPresentationContextProviding
{
    private var controller: ASAuthorizationController?
    private var continuation: CheckedContinuation<AppleCredential, any Error>?

    func authorize(requestNonce: String) async throws -> AppleCredential {
        try await withCheckedThrowingContinuation { continuation in
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.email]
            request.nonce = requestNonce
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken, let codeData = credential.authorizationCode,
            let token = String(data: tokenData, encoding: .utf8), let code = String(data: codeData, encoding: .utf8)
        else { return finish(.failure(IdentityProviderError.failed)) }
        finish(.success(AppleCredential(identityToken: token, authorizationCode: code)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        let canceled = (error as? ASAuthorizationError)?.code == .canceled
        finish(.failure(canceled ? IdentityProviderError.cancelled : IdentityProviderError.failed))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { keyWindowAnchor() }

    private func finish(_ result: Result<AppleCredential, any Error>) {
        let continuation = continuation
        self.continuation = nil
        controller = nil
        continuation?.resume(with: result)
    }
}
