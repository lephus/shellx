import Foundation
import Observation
import ShellXRemoteCore

/// State of the "Continue with Google" sheet. The sign-in itself is injected (`ShellXAccount.signInWithGoogle`),
/// so this module stays free of the account and the bundle.
@MainActor
@Observable
public final class GoogleSignInModel {
    public enum Phase: Equatable, Sendable {
        case ready
        case waiting
        case signedIn(email: String)
    }

    public private(set) var phase: Phase = .ready
    /// The last failure as a sentence; nil while waiting, after success and after a cancellation.
    public private(set) var errorText: String?
    public let purpose: GoogleSignInPurpose
    /// Called once when the sheet should close: `true` after the person confirmed success, `false` on cancel.
    @ObservationIgnored public var onFinished: (@MainActor (Bool) -> Void)?

    @ObservationIgnored private let labels: SignInErrorLabels
    @ObservationIgnored private let signIn: @MainActor () async throws -> String
    @ObservationIgnored private let cancelFlow: @MainActor () async -> Void
    @ObservationIgnored private var cancelRequested = false
    @ObservationIgnored private var reported = false

    public init(
        purpose: GoogleSignInPurpose, labels: SignInErrorLabels,
        signIn: @escaping @MainActor () async throws -> String, cancel: @escaping @MainActor () async -> Void
    ) {
        self.purpose = purpose
        self.labels = labels
        self.signIn = signIn
        self.cancelFlow = cancel
    }

    /// Opens Google and waits. Only from `.ready`; returns nil (and does nothing) in any other phase.
    @discardableResult
    public func start() -> Task<Void, Never>? {
        guard phase == .ready else { return nil }
        phase = .waiting
        errorText = nil
        cancelRequested = false
        return Task { [weak self] in
            guard let self else { return }
            do {
                let email = try await signIn()
                phase = cancelRequested ? .ready : .signedIn(email: email)
            } catch {
                phase = .ready
                errorText = cancelRequested || SignInErrorMessage.isCancellation(error)
                    ? nil : SignInErrorMessage.text(for: error, labels: labels)
            }
        }
    }

    /// Closes the sheet; while waiting it also ends the Google flow.
    @discardableResult
    public func cancel() -> Task<Void, Never>? {
        let wasWaiting = phase == .waiting
        cancelRequested = true
        if !reported {
            reported = true
            onFinished?(false)
        }
        guard wasWaiting else { return nil }
        return Task { [weak self] in await self?.cancelFlow() }
    }

    /// Forgets the shown failure (only in `.ready`), so the other flow's start or typing hides it.
    public func clearError() {
        guard phase == .ready else { return }
        errorText = nil
    }

    /// The person confirmed the "Signed in as" screen.
    public func finish() {
        guard case .signedIn = phase, !reported else { return }
        reported = true
        onFinished?(true)
    }
}
