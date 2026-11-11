import Foundation
import Observation

/// The ShellX account this Mac is signed in to, for Settings → Account. Works whether or not the
/// remote service runs (`gateEnabled`, on while this Mac serves phones):
///
/// * gate off: only `config.set` and `auth.login` / `auth.logout` through the core; no host, bridge or
///   remote session starts;
/// * gate on: the remote service signs in and out, and its session starts and stops with the account.
///
/// The core keeps the session token; `stateRoot/account.json` (owner-only) keeps the user id and the email
/// typed at sign-in, because the core never tells the email back. It is the signed-in state at launch.
@MainActor
@Observable
public final class ShellXAccount {
    public struct Identity: Codable, Equatable, Sendable {
        public let userID: String
        public let email: String
        /// When this Mac last signed in. Nil for records saved before it was kept.
        public let signedInAt: Date?
        /// `"google"`, `"email"` or `"password"`. Nil in records saved before Google sign-in (they were password sign-ins).
        public let authMethod: String?

        public init(userID: String, email: String, signedInAt: Date? = nil, authMethod: String? = nil) {
            self.userID = userID; self.email = email; self.signedInAt = signedInAt; self.authMethod = authMethod
        }

        public var usesPassword: Bool { authMethod == nil || authMethod == "password" }
    }

    /// What a Google sign-in is doing right now.
    public enum GoogleStep: Equatable, Sendable {
        case idle
        case waiting(GoogleSignInPurpose)
    }

    public private(set) var identity: Identity?
    /// True while a sign-out runs. The sign-in sheet shows its own progress.
    public private(set) var isWorking = false
    public private(set) var googleStep: GoogleStep = .idle
    /// The account's sign-in methods (Settings › Account); the last good list stays when a refresh fails.
    public private(set) var signInMethods: [AccountSignInMethod] = []
    /// Core code of the last failed list or removal; nil when the last attempt worked.
    public private(set) var signInMethodsErrorCode: String?
    public private(set) var removingSignInMethodIDs: Set<String> = []
    /// Runs after the server ended the session and the saved identity was forgotten (the app shows sign-in).
    @ObservationIgnored public var onSignedOutByServer: (@MainActor () -> Void)?
    /// `UserDefaults` key recording that the one-time "switch to Google" offer was made.
    public static let googleSwitchOfferedKey = "shellx.account.googleSwitchOffered"

    @ObservationIgnored private let service: ShellXRemoteService
    @ObservationIgnored private let file: URL
    @ObservationIgnored private let openURL: @MainActor (URL) -> Bool
    @ObservationIgnored private var waitingFlowID: String?
    @ObservationIgnored private var googleCancelRequested = false
    @ObservationIgnored private var googleToken: UUID?
    /// Email codes being verified right now (a closed sheet's verify runs on, Ruling 12); Google waits for none.
    @ObservationIgnored private var emailVerifications = 0

    public init(service: ShellXRemoteService, openURL: @escaping @MainActor (URL) -> Bool = { _ in false }) {
        self.service = service
        self.openURL = openURL
        file = Self.recordFile(stateRoot: service.env.paths.stateRoot)
        identity = Self.readRecord(file)
        service.onSessionEndedByServer = { [weak self] in self?.handleServerSignOut() }
    }

    /// `account.json` under `stateRoot`.
    nonisolated static func recordFile(stateRoot: URL) -> URL {
        stateRoot.appendingPathComponent("account.json")
    }

    /// The identity saved in `file`, or nil when there is none or it cannot be read.
    nonisolated static func readRecord(_ file: URL) -> Identity? {
        (try? OwnerOnlyFile.read(file)).flatMap { $0 }.flatMap { try? JSONDecoder().decode(Identity.self, from: $0) }
    }

    /// Throws the core's error (`invalid_credentials`, `rate_limited`, `network`, …); the identity is
    /// kept only after the server accepted the password.
    public func signIn(email: String, password: String) async throws {
        let userID: String
        if service.env.gateEnabled() {
            try await service.signIn(email: email, password: password)
            userID = service.accountOwnerID ?? ""
        } else {
            try await service.ensureConfigured()
            let params: [String: JSONValue] = ["email": .string(email), "password": .string(password)]
            userID = try await service.call("auth.login", params, as: LoginReply.self).user_id
        }
        await save(Identity(userID: userID, email: email, signedInAt: Date(), authMethod: "password"))
        RemoteLog.service.info("account signed in")
    }

    /// Writes `account.json` (owner-only) and shows `signedIn`. A failed write only means the next launch shows signed out.
    private func save(_ signedIn: Identity) async {
        let file = self.file
        do {
            let data = try JSONEncoder().encode(signedIn)
            try await ShellXRemoteService.offMain {
                try OwnerOnlyFile.ensurePrivateDirectory(file.deletingLastPathComponent())
                try OwnerOnlyFile.write(data, to: file)
            }
        } catch {
            RemoteLog.service.error("account record not saved: \(RemoteLog.code(error), privacy: .public)")
        }
        identity = signedIn
    }

    // MARK: - Google

    /// Opens Google in the browser and waits for the person. `.signIn` creates the session (and starts the
    /// remote session with the gate on); `.link` switches the current session to Google in place.
    /// Throws the core's code (`google_cancelled`, `google_timeout`, `switch_from_signed_in_device`, ...),
    /// `google_in_progress` while another flow waits, `email_sign_in_in_progress` while an email code is being
    /// verified (so two session writes never race), or `browser_unavailable`.
    @discardableResult
    public func signInWithGoogle(purpose: GoogleSignInPurpose) async throws -> Identity {
        guard googleStep == .idle else {
            throw ShellXCoreError(code: "google_in_progress", message: "a Google sign-in is already waiting")
        }
        guard emailVerifications == 0 else {
            throw ShellXCoreError(code: "email_sign_in_in_progress", message: "an email sign-in code is being verified")
        }
        // Busy from the first await on, so a second click or a cancel during begin is seen.
        googleStep = .waiting(purpose)
        googleCancelRequested = false
        let token = UUID()
        googleToken = token
        defer {
            if googleToken == token {
                googleStep = .idle
                waitingFlowID = nil
                googleToken = nil
            }
        }
        let gate = service.env.gateEnabled()
        if gate { await service.prepareLocal() }
        try await service.ensureConfigured()
        let core = service.env.core
        let start = try await ShellXRemoteService.offMain { try core.beginGoogleSignIn(purpose: purpose) }
        waitingFlowID = start.flowID
        if googleCancelRequested {
            // Cancelled while begin ran: end the flow, never open the browser.
            _ = try? await ShellXRemoteService.offMain { try core.cancelGoogleSignIn(flowID: start.flowID) }
            throw ShellXCoreError(code: "google_cancelled", message: "Google sign-in was cancelled")
        }
        guard openURL(start.authURL) else {
            _ = try? await ShellXRemoteService.offMain { try core.cancelGoogleSignIn(flowID: start.flowID) }
            throw ShellXCoreError(code: "browser_unavailable", message: "the browser could not be opened")
        }
        let result: GoogleSignInResult
        do {
            result = try await ShellXRemoteService.offMain { try core.finishGoogleSignIn(flowID: start.flowID) }
        } catch {
            if let e = error as? ShellXCoreError, ShellXRemoteService.isSignedOutCode(e.code) { handleServerSignOut() }
            throw error
        }
        if gate && purpose == .signIn { await service.beginSignedInSession(userID: result.userID) }
        let signedIn = Identity(userID: result.userID, email: result.email, signedInAt: Date(), authMethod: "google")
        await save(signedIn)
        RemoteLog.service.info("account signed in with Google")
        if purpose == .link { await refreshSignInMethods() }
        return signedIn
    }

    /// Ends the waiting Google flow, if any; the pending `signInWithGoogle` throws `google_cancelled`.
    public func cancelGoogleSignIn() async {
        guard googleStep != .idle else { return }
        googleCancelRequested = true   // a begin still in flight ends itself when it answers
        guard let flow = waitingFlowID else { return }
        let core = service.env.core
        _ = try? await ShellXRemoteService.offMain { try core.cancelGoogleSignIn(flowID: flow) }
    }

    // MARK: - Email code

    /// Asks the relay to mail a sign-in code. Changes no session and writes nothing.
    ///
    /// - Parameters:
    ///   - email: The address as typed (the core trims it).
    ///   - locale: The UI language, for the mail's language.
    /// - Returns: The challenge to verify the code against, with the relay's address.
    /// - Throws: The core's code (`invalid_email`, `disposable_email`, `rate_limited`, `email_send_failed`, …).
    public func requestEmailCode(email: String, locale: String) async throws -> EmailCodeChallenge {
        try await service.ensureConfigured()
        let core = service.env.core
        return try await ShellXRemoteService.offMain { try core.beginEmailSignIn(email: email, locale: locale) }
    }

    /// Verifies the code and signs in like a Google `.signIn`: with the gate on it starts the remote session;
    /// saves `Identity(authMethod: "email")`.
    ///
    /// - Parameters:
    ///   - challengeID: The id from ``requestEmailCode(email:locale:)``.
    ///   - code: The digits as typed.
    /// - Returns: The saved identity.
    /// - Throws: The core's code (nothing is saved then), or `google_in_progress` while a Google flow waits, so
    ///   two session writes never race. While it runs, ``signInWithGoogle(purpose:)`` refuses with
    ///   `email_sign_in_in_progress`.
    @discardableResult
    public func signInWithEmailCode(challengeID: String, code: String) async throws -> Identity {
        guard googleStep == .idle else {
            throw ShellXCoreError(code: "google_in_progress", message: "a Google sign-in is waiting")
        }
        emailVerifications += 1
        defer { emailVerifications -= 1 }
        let gate = service.env.gateEnabled()
        if gate { await service.prepareLocal() }
        try await service.ensureConfigured()
        let core = service.env.core
        let result = try await ShellXRemoteService.offMain {
            try core.finishEmailSignIn(challengeID: challengeID, code: code)
        }
        if gate { await service.beginSignedInSession(userID: result.userID) }
        let signedIn = Identity(userID: result.userID, email: result.email, signedInAt: Date(), authMethod: "email")
        await save(signedIn)
        RemoteLog.service.info("account signed in with an email code")
        return signedIn
    }

    /// True once per `defaults` while this account still signs in with a password: the one-time offer to switch.
    public func takeGoogleSwitchOffer(defaults: UserDefaults) -> Bool {
        guard identity?.usesPassword == true, !defaults.bool(forKey: Self.googleSwitchOfferedKey) else { return false }
        defaults.set(true, forKey: Self.googleSwitchOfferedKey)
        return true
    }

    // MARK: - Sign-in methods

    /// Reloads the sign-in methods. A failure keeps the last list and sets `signInMethodsErrorCode`.
    public func refreshSignInMethods() async {
        do {
            try await service.ensureConfigured()
            let core = service.env.core
            signInMethods = try await ShellXRemoteService.offMain { try core.signInMethods() }
            signInMethodsErrorCode = nil
        } catch {
            signInMethodsErrorCode = RemoteLog.code(error)
        }
    }

    /// Removes an Apple ID (the relay refuses the last Google one), then reloads the list.
    public func removeSignInMethod(id: String) async {
        removingSignInMethodIDs.insert(id)
        defer { removingSignInMethodIDs.remove(id) }
        do {
            try await service.ensureConfigured()
            let core = service.env.core
            try await ShellXRemoteService.offMain { try core.removeSignInMethod(id: id) }
        } catch {
            signInMethodsErrorCode = RemoteLog.code(error)
            return
        }
        await refreshSignInMethods()
    }

    // MARK: - Session checks

    /// Launch check against `auth.session` (local, no network): copies the core's email and auth method into the
    /// shown identity (saved when they differ); `not_logged_in` while an identity is shown runs the server
    /// sign-out handler; any other error changes nothing.
    public func reconcileWithSession() async {
        guard let current = identity else { return }
        do {
            try await service.ensureConfigured()
            let session = try await service.call("auth.session", as: SessionReply.self)
            let updated = Identity(userID: current.userID, email: session.email ?? current.email,
                                   signedInAt: current.signedInAt, authMethod: session.auth_method)
            if updated != current { await save(updated) }
        } catch let e as ShellXCoreError where e.code == "not_logged_in" {
            handleServerSignOut()
        } catch {
            RemoteLog.service.error("session check failed: \(RemoteLog.code(error), privacy: .public)")
        }
    }

    /// The relay no longer accepts this session: forget the identity so the app asks for sign-in.
    private func handleServerSignOut() {
        guard identity != nil else { return }
        let file = self.file
        try? FileManager.default.removeItem(at: file)
        identity = nil
        clearMethods()
        onSignedOutByServer?()
    }

    private func clearMethods() {
        signInMethods = []
        signInMethodsErrorCode = nil
        removingSignInMethodIDs = []
    }

    /// Best-effort server logout; the account is forgotten locally even when the server is unreachable.
    public func signOut() async {
        isWorking = true
        defer { isWorking = false }
        if service.env.gateEnabled() {
            await service.signOut()
        } else {
            do {
                try await service.ensureConfigured()
                _ = try await service.call("auth.logout", as: EmptyReply.self)
            } catch {
                RemoteLog.service.error("logout failed: \(RemoteLog.code(error), privacy: .public)")
            }
        }
        let file = self.file
        _ = try? await ShellXRemoteService.offMain { try FileManager.default.removeItem(at: file) }
        identity = nil
        clearMethods()
    }
}
