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
    @ObservationIgnored private let log = Logger(subsystem: "com.shellx.app", category: "account")

    public init(
        vault: AccountVault, relay: any RelayAccountCalling, identity: any IdentityProviding = UnavailableIdentityProvider(),
        deviceName: String, wipers: [any LocalDataWiping],
        pendingWipeDefaults: UserDefaults = .standard,
        makeHub: @escaping @MainActor () -> MachineHub
    ) {
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
        pendingWipeDefaults.set(true, forKey: Self.pendingWipeKey)
        do { try await vault.wipe() } catch {
            log.error("sign_out_wipe_failed")
        }
        // Sign out regardless; a failed wipe keeps the marker and is retried before anyone signs in.
        if await runWipers() {
            pendingWipeDefaults.removeObject(forKey: Self.pendingWipeKey)
        }
        authMethod = nil
        phase = .signedOut(expired: false)
    }

    /// The relay refused the stored token: drop the session only. The phone key and the Macs stay,
    /// so signing in again as the same account needs no new pairing.
    public func handleUnauthorized() async {
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
