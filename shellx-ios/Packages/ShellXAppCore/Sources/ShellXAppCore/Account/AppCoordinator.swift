import Foundation
import Observation
import ShellXLinkAccount
import os

/// Owns the account state of the app: which screen to show and how to get in and out, and the
/// `MachineHub` of the signed-in account (made on sign-in, stopped and dropped on sign-out or 401).
///
/// Nothing here logs a token, a password or a key; log lines carry error types only.
@MainActor @Observable
public final class AppCoordinator {
    public private(set) var phase: AppPhase = .launching
    /// The paired Macs and their links; nil unless signed in.
    public private(set) var hub: MachineHub?
    /// How the stored session signed in; nil unless signed in.
    public private(set) var authMethod: AccountAuthMethod?
    /// Non-nil exactly while `phase == .linkingApple`.
    public private(set) var appleLink: AppleLinkModel?
    /// Why the last Apple link ended; cleared when the next sign-in starts.
    public private(set) var signInNotice: SignInNotice?

    @ObservationIgnored private let vault: AccountVault
    @ObservationIgnored private let relay: any RelayAccountCalling
    @ObservationIgnored private let identity: any IdentityProviding
    @ObservationIgnored private let deviceName: String
    @ObservationIgnored private let wipers: [any LocalDataWiping]
    /// Holds a non-secret "local wipe pending" flag across launches.
    @ObservationIgnored private let pendingWipeDefaults: UserDefaults
    private static let pendingWipeKey = "shellx.localWipePending"
    @ObservationIgnored private let makeHub: @MainActor () -> MachineHub
    /// The language of the code mail: "vi" or "en".
    @ObservationIgnored private let emailLocale: String
    /// Times the Resend lock of the email sign-in.
    @ObservationIgnored private let clock: any Clock<Duration>
    /// True while a switch to Google or an account deletion is on the relay: a 401 then answers the token the relay is
    /// replacing or deleting, so `handleUnauthorized` only remembers it.
    @ObservationIgnored private var accountChangeInProgress = false
    @ObservationIgnored private var unauthorizedDuringChange = false
    @ObservationIgnored private let log = Logger(subsystem: "com.shellx.app", category: "account")

    public init(
        vault: AccountVault, relay: any RelayAccountCalling, identity: any IdentityProviding = UnavailableIdentityProvider(),
        deviceName: String, wipers: [any LocalDataWiping],
        pendingWipeDefaults: UserDefaults = .standard,
        emailLocale: String = EmailCodeLocale.current, clock: any Clock<Duration> = ContinuousClock(),
        makeHub: @escaping @MainActor () -> MachineHub
    ) {
        self.emailLocale = emailLocale
        self.clock = clock
        self.pendingWipeDefaults = pendingWipeDefaults
        self.vault = vault
        self.relay = relay
        self.identity = identity
        self.deviceName = deviceName
        self.wipers = wipers
        self.makeHub = makeHub
    }

    /// Reads the stored session. A Keychain that is locked (iOS may start the app before the first
    /// unlock) keeps the phase at `.launching`; `protectedDataBecameAvailable()` tries again.
    public func launch() async {
        _ = await retryPendingWipe()
        do {
            if let session = try await vault.session() {
                authMethod = session.authMethod
                phase = .signedIn(email: session.email)
                await startHub()
            } else {
                phase = .signedOut(expired: false)
            }
        } catch SecretStoreError.unavailable {
            log.notice("launch_keychain_unavailable")
        } catch {
            log.error("launch_session_unreadable")
            phase = .signedOut(expired: false)
        }
    }

    /// Call when protected data becomes available (the app's `didBecomeActive` / protected-data notification).
    public func protectedDataBecameAvailable() async {
        guard phase == .launching else { return }
        await launch()
    }

    public func signIn(email: String, password: String) async throws(SignInError) {
        signInNotice = nil
        // A sign-out whose local wipe failed blocks every sign-in until the wipe succeeds.
        guard await retryPendingWipe() else { throw .localWipePending }
        let key = try await phoneKey()
        let signIn: AccountSignIn
        do {
            let session = try await relay.login(
                email: email, password: password, deviceName: deviceName, clientKey: key)
            signIn = AccountSignIn(session: session, email: email)
        } catch {
            throw SignInError(error)
        }
        try await completeSignIn(signIn, method: .password)
    }

    /// Continue with Google: the relay's nonce, Google's ID token for it, then the relay's sign-in.
    public func signInWithGoogle() async throws(SignInError) {
        signInNotice = nil
        guard await retryPendingWipe() else { throw .localWipePending }
        let key = try await phoneKey()
        let signIn: AccountSignIn
        do {
            let nonce = try await relay.nonce()
            let idToken = try await identity.googleIDToken(nonce: nonce)
            signIn = try await relay.signInWithGoogle(
                idToken: idToken, nonce: nonce, deviceName: deviceName, clientKey: key)
        } catch {
            throw SignInError(error)
        }
        try await completeSignIn(signIn, method: .google)
    }

    /// Sign in with Apple. An Apple ID without an account moves to `.linkingApple` ("Connect to Your Mac").
    public func signInWithApple() async throws(SignInError) {
        signInNotice = nil
        guard await retryPendingWipe() else { throw .localWipePending }
        let key = try await phoneKey()
        let result: AppleSignInResult
        do {
            let nonce = try await relay.nonce()
            let credential = try await identity.appleCredential(requestNonce: AuthCrypto.sha256Hex(nonce))
            result = try await relay.signInWithApple(
                identityToken: credential.identityToken, authorizationCode: credential.authorizationCode,
                nonce: nonce, deviceName: deviceName, clientKey: key)
        } catch {
            throw SignInError(error)
        }
        switch result {
        case let .signedIn(signIn):
            try await completeSignIn(signIn, method: .apple)
        case let .linkRequired(linkToken, _):
            appleLink = AppleLinkModel(
                linkToken: linkToken, relay: relay, vault: vault,
                finish: { [weak self] outcome in await self?.finishAppleLink(outcome) })
            phase = .linkingApple
        }
    }

    /// Asks the relay to mail a code to `email`. Stores nothing; the phase stays.
    public func requestEmailCode(email: String) async throws(SignInError) -> EmailChallenge {
        signInNotice = nil
        guard await retryPendingWipe() else { throw .localWipePending }
        do {
            return try await relay.requestEmailCode(email: email, locale: emailLocale)
        } catch {
            throw Self.emailCallError(error)
        }
    }

    /// The mailed code for `challengeID`: a right one signs in like Google, with `auth_method` email.
    public func signInWithEmailCode(challengeID: String, code: String) async throws(SignInError) {
        signInNotice = nil
        guard await retryPendingWipe() else { throw .localWipePending }
        let key = try await phoneKey()
        let signIn: AccountSignIn
        do {
            signIn = try await relay.signInWithEmailCode(
                challengeID: challengeID, code: code, deviceName: deviceName, clientKey: key)
        } catch {
            throw Self.emailCallError(error)
        }
        try await completeSignIn(signIn, method: .email)
    }

    /// What an email call of the relay threw. A relay from before email sign-in has no such route (404 `not_found`):
    /// that reads as "not available", but only here, so Google and Apple keep their words for a 404.
    private static func emailCallError(_ error: any Error) -> SignInError {
        if case RelayAPIError.http(404, "not_found") = error { return .providerUnavailable }
        return SignInError(error)
    }

    private func phoneKey() async throws(SignInError) -> Data {
        do {
            return try await vault.phoneKey().publicKey
        } catch {
            log.error("sign_in_keychain_failed")
            throw .server(code: "keychain")
        }
    }

    private func completeSignIn(_ signIn: AccountSignIn, method: AccountAuthMethod) async throws(SignInError) {
        let account = signIn.session
        // Another account's Macs and history must not survive into this one. Every wiper runs first;
        // the owner changes only when all succeeded, so a retry wipes again.
        let previousOwner: String?
        do { previousOwner = try await vault.machinesOwner() } catch {
            log.error("sign_in_store_failed")
            throw .server(code: "keychain")
        }
        let otherAccount = previousOwner != nil && previousOwner != account.userID
        if otherAccount {
            guard await runWipers() else { throw .localWipePending }
        }
        do {
            if otherAccount { try await vault.setMachines([], owner: account.userID) }
            try await vault.setSession(
                StoredSession(
                    userID: account.userID, deviceID: account.deviceID, token: account.token, email: signIn.email,
                    authMethod: method))
        } catch {
            log.error("sign_in_store_failed")
            throw .server(code: "keychain")
        }
        authMethod = method
        phase = .signedIn(email: signIn.email)
        await startHub()
    }

    /// The Mac allowed (or refused, or the link ended): finish "Connect to Your Mac".
    private func finishAppleLink(_ outcome: AppleLinkModel.Outcome) async {
        switch outcome {
        case let .linked(approval):
            do {
                try await storeLinkedSession(approval)
            } catch {
                log.error("apple_link_store_failed")
                appleLink = nil
                signInNotice = .appleLinkFailed
                phase = .signedOut(expired: false)
                return
            }
            appleLink = nil
            authMethod = .apple
            phase = .signedIn(email: approval.signIn.email)
            await startHub()
        case .cancelled:
            appleLink = nil
            phase = .signedOut(expired: false)
        case .denied:
            appleLink = nil
            signInNotice = .appleLinkDenied
            phase = .signedOut(expired: false)
        case .expired:
            appleLink = nil
            signInNotice = .appleLinkExpired
            phase = .signedOut(expired: false)
        }
    }

    private func storeLinkedSession(_ approval: AppleLinkApproval) async throws {
        let account = approval.signIn.session
        let previousOwner = try await vault.machinesOwner()
        let sameOwner = previousOwner == account.userID
        if previousOwner != nil && !sameOwner {
            guard await runWipers() else { throw SignInError.localWipePending }
        }
        var machines: [PairedMachine] = []
        if sameOwner { machines = try await vault.machines() }
        if let index = machines.firstIndex(where: { $0.machineID == approval.machine.machineID }) {
            machines[index] = approval.machine
        } else {
            machines.append(approval.machine)
        }
        try await vault.setMachines(machines, owner: account.userID)
        try await vault.setSession(
            StoredSession(
                userID: account.userID, deviceID: account.deviceID, token: account.token,
                email: approval.signIn.email, authMethod: .apple))
    }

    /// Removes this iPhone from its Macs and the relay (best effort), then forgets everything local.
    /// The "local wipe pending" marker is written before anything local is wiped and cleared only
    /// once every wiper succeeded: if the app dies in between, the vault no longer names an owner, so
    /// only the marker makes the next launch or sign-in wipe the history.
    public func signOut() async {
        await stopHub()
        let session = try? await vault.session()
        if let token = session?.token {
            do {
                for grant in try await relay.machines(token: token) {
                    do { try await relay.unpair(grantID: grant.grantID, token: token) } catch {
                        log.notice("sign_out_unpair_failed")
                    }
                }
            } catch {
                log.notice("sign_out_list_failed")
            }
            do { try await relay.logout(token: token) } catch {
                log.notice("sign_out_logout_failed")
            }
        }
        await forgetLocalData()
        authMethod = nil
        phase = .signedOut(expired: false)
    }

    /// The local part of signing out: the marker first, then the vault and every wiper. A failed wipe keeps the marker
    /// and is retried before anyone signs in.
    private func forgetLocalData() async {
        pendingWipeDefaults.set(true, forKey: Self.pendingWipeKey)
        do { try await vault.wipe() } catch {
            log.error("sign_out_wipe_failed")
        }
        if await runWipers() {
            pendingWipeDefaults.removeObject(forKey: Self.pendingWipeKey)
        }
    }

    /// S1 §6.3b: a password session becomes a Google one on this iPhone, keeping the account, its Macs and history.
    public func switchToGoogle() async throws(SignInError) {
        guard let stored = try? await vault.session(), stored.authMethod == .password else { return }
        let nonce: String
        let idToken: String
        do {
            nonce = try await relay.nonce()
            idToken = try await identity.googleIDToken(nonce: nonce)
        } catch {
            throw SignInError(error)
        }
        beginAccountChange()
        let signIn: AccountSignIn
        do {
            signIn = try await relay.linkGoogle(idToken: idToken, nonce: nonce, token: stored.token)
        } catch {
            throw await endFailedAccountChange(error)
        }
        do {
            try await vault.setSession(
                StoredSession(
                    userID: signIn.session.userID, deviceID: signIn.session.deviceID, token: signIn.session.token,
                    email: signIn.email, authMethod: .google))
        } catch {
            log.error("switch_store_failed")
            accountChangeInProgress = false
            throw .server(code: "keychain")
        }
        // A fresh hub: requests of the old one may carry the token the relay just replaced.
        await stopHub()
        authMethod = .google
        phase = .signedIn(email: signIn.email)
        await startHub()
        accountChangeInProgress = false
        unauthorizedDuringChange = false
    }

    /// S1 §6.8: sign in again with the account's provider, delete the account on the relay, then forget everything
    /// local exactly as `signOut()` does (without unpairing or logging out: the account is gone). An email session
    /// has no provider to sign in with again: it deletes with a mailed code, `deleteAccount(challengeID:code:)`.
    public func deleteAccount() async throws(SignInError) {
        guard let stored = try? await vault.session() else { throw .server(code: "signed_out") }
        if stored.authMethod == .password { throw .switchToGoogleFirst }
        if stored.authMethod == .email { throw .server(code: "code_required") }
        let nonce: String
        let idToken: String
        do {
            nonce = try await relay.nonce()
            switch stored.authMethod {
            case .apple:
                idToken = try await identity.appleCredential(requestNonce: AuthCrypto.sha256Hex(nonce)).identityToken
            default:
                idToken = try await identity.googleIDToken(nonce: nonce)
            }
        } catch {
            throw SignInError(error)
        }
        beginAccountChange()
        do {
            try await relay.deleteAccount(idToken: idToken, nonce: nonce, token: stored.token)
        } catch {
            throw await endFailedAccountChange(error)
        }
        await finishAccountDeletion()
    }

    /// Delete Account for an email session, first half: mails a code to the account's address.
    public func requestDeleteAccountCode() async throws(SignInError) -> EmailChallenge {
        guard let stored = try? await vault.session() else { throw .server(code: "signed_out") }
        guard stored.authMethod == .email else { throw .server(code: "not_email_session") }
        do {
            return try await relay.requestEmailCode(email: stored.email, locale: emailLocale)
        } catch {
            throw Self.emailCallError(error)
        }
    }

    /// Second half: deletes on the relay, then forgets everything local exactly as `deleteAccount()` does.
    public func deleteAccount(challengeID: String, code: String) async throws(SignInError) {
        guard let stored = try? await vault.session() else { throw .server(code: "signed_out") }
        beginAccountChange()
        do {
            try await relay.deleteAccount(challengeID: challengeID, code: code, token: stored.token)
        } catch {
            throw await endFailedAccountChange(error)
        }
        await finishAccountDeletion()
    }

    /// The relay deleted the account: forget everything local, as `signOut()` does.
    private func finishAccountDeletion() async {
        await stopHub()
        await forgetLocalData()
        authMethod = nil
        phase = .signedOut(expired: false)
        accountChangeInProgress = false
        unauthorizedDuringChange = false
    }

    private func beginAccountChange() {
        accountChangeInProgress = true
        unauthorizedDuringChange = false
    }

    /// A switch or deletion failed on the relay: the session and the hub stay, unless the stored token itself was
    /// refused (or a 401 raced the call), which signs out as expired.
    private func endFailedAccountChange(_ error: any Error) async -> SignInError {
        accountChangeInProgress = false
        let sawUnauthorized = unauthorizedDuringChange
        unauthorizedDuringChange = false
        if case RelayAPIError.http(401, "unauthorized") = error {
            await handleUnauthorized()
            return .server(code: "unauthorized")
        }
        if sawUnauthorized { await handleUnauthorized() }
        return SignInError(error)
    }

    /// The relay refused the stored token: drop the session only. The phone key and the Macs stay,
    /// so signing in again as the same account needs no new pairing.
    public func handleUnauthorized() async {
        if accountChangeInProgress {
            unauthorizedDuringChange = true
            return
        }
        await stopHub()
        do { try await vault.clearSession() } catch {
            log.error("unauthorized_clear_failed")
        }
        authMethod = nil
        phase = .signedOut(expired: true)
    }

    /// Runs every wiper, continuing past failures; true when all succeeded.
    private func runWipers() async -> Bool {
        var allSucceeded = true
        for wiper in wipers {
            do { try await wiper.wipe() } catch {
                log.error("local_wipe_failed")
                allSucceeded = false
            }
        }
        return allSucceeded
    }

    /// When a sign-out left its local wipe undone, wipes again; the marker is cleared only when
    /// every wiper succeeds. True when nothing is pending.
    private func retryPendingWipe() async -> Bool {
        guard pendingWipeDefaults.bool(forKey: Self.pendingWipeKey) else { return true }
        guard await runWipers() else { return false }
        pendingWipeDefaults.removeObject(forKey: Self.pendingWipeKey)
        return true
    }

    private func startHub() async {
        guard hub == nil else { return }
        let hub = makeHub()
        self.hub = hub
        await hub.start()
    }

    private func stopHub() async {
        guard let hub else { return }
        await hub.stopAll()
        if self.hub === hub { self.hub = nil }
    }
}

private struct AccountSessionValue: Sendable {
    var userID: String
    var deviceID: String
    var token: String
}
