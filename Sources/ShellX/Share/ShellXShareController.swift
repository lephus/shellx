import AppKit
import Combine
import Foundation
import os
import ShellXBrand
import ShellXRemoteCore

/// ShellX: the one switch for share links (L7). On when `ShellXFeatures.shareLinks` is flipped, or in
/// DEBUG builds launched with `SHELLX_SHARE_LINKS=1`, **and** the remote-machines gate is on. Off, no
/// entrypoint shows and nothing calls the core.
///
/// Ruling R1b: a share needs a signed-in account, and the account (core configuration, sign-in sheet,
/// `isSignedIn`) still lives in `ShellXRemoteService`, which only runs with `ShellXRemoteGate` on. Until
/// the account moves out of that service, share links also require `ShellXRemoteGate`, so the
/// entrypoints are hidden rather than showing a sign-in button that cannot work.
enum ShellXShareGate {
    static let environmentKey = "SHELLX_SHARE_LINKS"

    @MainActor static var isEnabled: Bool {
        #if DEBUG
        if let overrideForTesting { return overrideForTesting }
        #endif
        return isEnabled(flag: ShellXFeatures.shareLinks, remoteMachines: ShellXRemoteGate.isEnabled,
                         environment: ProcessInfo.processInfo.environment)
    }

    static func isEnabled(flag: Bool, remoteMachines: Bool, environment: [String: String]) -> Bool {
        guard remoteMachines else { return false }
        if flag { return true }
        #if DEBUG
        return environment[environmentKey] == "1"
        #else
        return false
        #endif
    }

    #if DEBUG
    /// Tests only: forces the gate either way; nil reads the flags and environment.
    @MainActor static var overrideForTesting: Bool?
    #endif
}

/// A share this app is hosting.
struct ActiveShare: Identifiable, Equatable {
    /// Display form `xxxx-xxxx`.
    let id: String
    /// `https://shellx.pro/s/<id>#<secret>`; the fragment never leaves this Mac except in the link itself.
    let url: URL
    let permission: SharePermission
    let lifetime: ShareLifetime
    let workspaceID: UUID
    /// The phone-handoff QR (R5): one viewer, claimed within `claimUntil`.
    let oneTime: Bool
    /// The API's `expires_at` (for until_quit the 24 h cap, R5); the host stops at it.
    let expiresAt: Date
    let claimUntil: Date?
    var viewers: [ShareViewer]

    /// 15 m / 1 h links outlive a quit and resume at the next launch (§7.3); until_quit and QR shares don't.
    var resumesAfterRelaunch: Bool { !oneTime && lifetime != .untilQuit }
}

/// Why a share could not be made. `errorDescription` is localized (Vietnamese and English and the
/// app's other locales).
enum ShellXShareError: Error, Equatable, LocalizedError {
    case notSignedIn
    case workspaceUnavailable
    case shareLimit
    case network
    /// The API answered with a share id other than the proposed one, so viewers could not open the link;
    /// the share was revoked at once.
    case secureLinkUnavailable
    /// The link was stopped here, but the API did not confirm the revoke.
    case revokeFailed
    case failed(code: String)

    static func from(_ error: any Error) -> ShellXShareError {
        if let share = error as? ShellXShareError { return share }
        guard let core = error as? ShellXCoreError else { return .failed(code: "unknown") }
        switch core.code {
        case "not_logged_in", "unauthorized", "invalid_token": return .notSignedIn
        case "share_limit": return .shareLimit
        case "network", "timeout": return .network
        default: return .failed(code: core.code)
        }
    }

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return String(localized: "share.error.notSignedIn", defaultValue: "Sign in to ShellX to share.")
        case .workspaceUnavailable:
            return String(localized: "share.error.workspaceUnavailable", defaultValue: "This workspace is no longer open.")
        case .shareLimit:
            return String(localized: "share.error.limit", defaultValue: "Too many open links. Revoke one and try again.")
        case .network:
            return String(localized: "share.error.network", defaultValue: "Can't reach ShellX. Check your connection and try again.")
        case .revokeFailed:
            return String(localized: "share.error.revokeFailed",
                          defaultValue: "Viewers were disconnected, but ShellX couldn't confirm the link was revoked.")
        case .secureLinkUnavailable, .failed:
            return String(localized: "share.error.failed", defaultValue: "Couldn't create the link. Try again.")
        }
    }
}

/// What the controller needs of a `ShareHost` (B4); tests may substitute one.
protocol ShellXShareHosting: AnyObject, Sendable {
    func start() async
    func stop(reason: ShareByeReason) async
    /// Quit: sends the bye without waiting on the main actor (it is blocked in `applicationWillTerminate`).
    func stopForTermination(reason: ShareByeReason) async
    var viewerStream: AsyncStream<[ShareViewer]> { get }
}

extension ShareHost: ShellXShareHosting {}

/// Everything `ShellXShareController` reaches outside itself.
struct ShellXShareEnvironment {
    struct HostSpec {
        let shareID: String
        let slot: String
        let secret: ShareSecret
        let permission: SharePermission
        let expiresAt: Date?
        let source: any ShareSource
    }

    var core: ShellXCoreClient
    var sockets: any ShareSocketFactory
    /// The account's sign-in state, delivered on the main thread (sends its current value on subscribe).
    var signedIn: AnyPublisher<Bool, Never>
    /// True once the launch's session restore finished (or was skipped), on the main thread. Resume
    /// waits for it so a workspace still being restored is not taken for gone.
    var sessionRestored: AnyPublisher<Bool, Never>
    /// The signed-in account (user id): stored links are kept per account.
    var accountID: @MainActor () -> String?
    var presentSignIn: @MainActor () -> Void
    var source: @MainActor (UUID) -> (any ShareSource)?
    /// Where 15 m / 1 h links wait for the next launch (the Keychain in the app).
    var store: any ShellXShareStore
    /// A fresh 8-character share id the client proposes (ruling 6; R4 derives `access` from it).
    var newShareID: @Sendable () -> String = { ShellXShareLink.randomID() }
    var clock: @Sendable () -> Date = { Date() }
    /// Waits for a share's `expiresAt`.
    var sleeper: any ShareSleeper = ShareSystemSleeper()
    /// nil: a real `ShareHost` over `core` tickets and `sockets`.
    var makeHost: (@MainActor (HostSpec) -> any ShellXShareHosting)?
}

/// Share link formatting (Global Constraints: `https://shellx.pro/s/<id>#<secret>`); ids are `ShareID`.
enum ShellXShareLink {
    static let base = "https://shellx.pro/s/"

    static func randomID() -> String { ShareID.random() }

    /// `k7f29qd1` → `k7f2-9qd1`.
    static func displayID(_ apiID: String) -> String { ShareID.display(self.apiID(apiID)) }

    static func apiID(_ id: String) -> String { id.replacingOccurrences(of: "-", with: "").lowercased() }

    static func url(id: String, secret: ShareSecret) -> URL {
        URL(string: base + displayID(id) + "#" + secret.base64url)!
    }
}

/// ShellX: hosts this Mac's share links (spec §7.2, §7.3). Every entrypoint (titlebar, both workspace
/// context menus) goes through `ShellXShareActions` into this one controller. Core calls block on the
/// FFI and run on a global queue, never on the main actor.
@MainActor
final class ShellXShareController: ObservableObject {
    private static var instance: ShellXShareController?

    static var shared: ShellXShareController {
        if let instance { return instance }
        let made = ShellXShareController(environment: .forApp())
        instance = made
        return made
    }

    /// Launch: with the gate on, makes the controller so 15 m / 1 h links resume once signed in.
    static func resumeIfEnabled() {
        guard ShellXShareGate.isEnabled else { return }
        _ = shared
    }

    /// Quit: stops and revokes only if a controller was ever made (gate off makes no core call).
    static func stopAllForTerminationIfStarted() {
        instance?.stopAllForTermination()
    }

    nonisolated static let log = Logger(subsystem: "pro.shellx.desktop", category: "share")
    nonisolated static let terminationBudget: TimeInterval = 1.5

    @Published private(set) var active: [ActiveShare] = []
    @Published private(set) var isSignedIn = false

    private struct Entry {
        let host: any ShellXShareHosting
        let persisted: PersistedShare?
        var tasks: [Task<Void, Never>] = []
    }

    private let env: ShellXShareEnvironment
    private var entries: [String: Entry] = [:]
    private var observers: [AnyCancellable] = []
    private var resumed = false
    private var sessionRestored = false
    /// The account whose links `entries` hold (set at resume).
    private var account: String?
    /// API ids whose revoke is in flight: quit revokes them too.
    private var pendingRevokes: Set<String> = []

    init(environment: ShellXShareEnvironment) {
        env = environment
        observers.append(environment.sessionRestored.sink { [weak self] restored in
            MainActor.assumeIsolated { self?.sessionRestoredChanged(restored) }
        })
        observers.append(environment.signedIn.sink { [weak self] signedIn in
            MainActor.assumeIsolated { self?.signedInChanged(signedIn) }
        })
    }

    func presentSignIn() { env.presentSignIn() }

    func shares(for workspaceID: UUID) -> [ActiveShare] {
        active.filter { $0.workspaceID == workspaceID }
    }

    private func signedInChanged(_ signedIn: Bool) {
        let wasSignedIn = isSignedIn
        if isSignedIn != signedIn { isSignedIn = signedIn }
        if signedIn {
            resumePersisted()
        } else if wasSignedIn {
            signedOut()
        }
    }

    private func sessionRestoredChanged(_ restored: Bool) {
        guard restored, !sessionRestored else { return }
        sessionRestored = true
        resumePersisted()
    }

    /// Another account may sign in next: stop every host (`bye(host_quit)`) and forget this account's
    /// list. Its stored links stay under its own account for its next sign-in.
    private func signedOut() {
        let (hosts, _) = takeAllForQuit()
        for host in hosts { Task { await host.stop(reason: .hostQuit) } }
        resumed = false
        account = nil
    }

    // MARK: Create

    /// A browser link (§7.3). Defaults are "Chỉ xem" and 1 hour.
    func share(workspaceID: UUID, permission: SharePermission = .view,
               lifetime: ShareLifetime = .oneHour) async throws -> URL {
        try await start(workspaceID: workspaceID, permission: permission, lifetime: lifetime, oneTime: false).url
    }

    /// The phone QR (§7.2, R5): "Được gõ", one viewer, claimable for 2 minutes, streamed until quit.
    /// Each call makes a new one-time share; the popover replaces an unclaimed one on expiry.
    func phoneHandoff(workspaceID: UUID) async throws -> URL {
        try await startPhoneHandoff(workspaceID: workspaceID).url
    }

    /// Same as `phoneHandoff`, returning the whole share (the popover needs `claimUntil`).
    func startPhoneHandoff(workspaceID: UUID) async throws -> ActiveShare {
        try await start(workspaceID: workspaceID, permission: .type, lifetime: .untilQuit, oneTime: true)
    }

    private func start(workspaceID: UUID, permission: SharePermission, lifetime: ShareLifetime,
                       oneTime: Bool) async throws -> ActiveShare {
        guard isSignedIn else { throw ShellXShareError.notSignedIn }
        guard let source = env.source(workspaceID) else { throw ShellXShareError.workspaceUnavailable }
        let core = env.core, newID = env.newShareID
        let minted: Minted
        do {
            minted = try await Self.offMain {
                try Self.mint(core: core, newID: newID, permission: permission, lifetime: lifetime, oneTime: oneTime)
            }
        } catch {
            Self.log.error("share create failed: \(ShellXShareLogCode.of(error), privacy: .public)")
            throw ShellXShareError.from(error)
        }
        let share = ActiveShare(
            id: ShellXShareLink.displayID(minted.created.id),
            url: ShellXShareLink.url(id: minted.created.id, secret: minted.secret),
            permission: permission, lifetime: lifetime, workspaceID: workspaceID, oneTime: oneTime,
            expiresAt: Date(timeIntervalSince1970: minted.created.expiresAtUnix),
            claimUntil: minted.created.claimUntilUnix.map(Date.init(timeIntervalSince1970:)),
            viewers: [])
        let persisted = share.resumesAfterRelaunch
            ? PersistedShare(id: ShellXShareLink.apiID(minted.created.id), slot: minted.created.slot,
                             secret: minted.secret.base64url, permission: permission, lifetime: lifetime,
                             expiresAt: share.expiresAt, workspaceID: workspaceID)
            : nil
        attach(share, slot: minted.created.slot, secret: minted.secret, source: source, persisted: persisted)
        return share
    }

    /// Starts a host for `share` and keeps it until revoke, expiry or quit.
    private func attach(_ share: ActiveShare, slot: String, secret: ShareSecret, source: any ShareSource,
                        persisted: PersistedShare?) {
        let spec = ShellXShareEnvironment.HostSpec(
            shareID: ShellXShareLink.apiID(share.id), slot: slot, secret: secret,
            permission: share.permission, expiresAt: share.expiresAt, source: source)
        let host = env.makeHost?(spec) ?? ShareHost(
            shareID: spec.shareID, slot: spec.slot, secret: spec.secret, permission: spec.permission,
            expiresAt: spec.expiresAt, source: spec.source, tickets: ShellXCoreShareTickets(core: env.core),
            sockets: env.sockets, clock: env.clock)
        let id = share.id
        var entry = Entry(host: host, persisted: persisted)
        let stream = host.viewerStream
        // The stream finishes when the host stops on its own (expiry): the link leaves the list.
        entry.tasks.append(Task { @MainActor [weak self] in
            for await viewers in stream {
                guard let self, let index = self.active.firstIndex(where: { $0.id == id }) else { return }
                self.active[index].viewers = viewers
            }
            guard !Task.isCancelled else { return }
            self?.ended(id, reason: nil)
        })
        let sleeper = env.sleeper, expiresAt = share.expiresAt
        entry.tasks.append(Task { @MainActor [weak self] in
            do { try await sleeper.sleep(until: expiresAt) } catch { return }
            guard !Task.isCancelled else { return }
            self?.ended(id, reason: .expired)
        })
        entries[id] = entry
        active.append(share)
        persist()
        Task { await host.start() }
    }

    private struct Minted: Sendable {
        let secret: ShareSecret
        let created: ShellXCreatedShare
    }

    /// Blocking. Controller ruling 6: the client proposes the share id, so `access` (R4, salted with the
    /// id) is derived before the call; `createShareRetryingID` keeps one secret and re-derives access for a
    /// fresh id on `share_id_taken`. The secret stays here: only the derived access token reaches the core.
    nonisolated private static func mint(core: ShellXCoreClient, newID: @Sendable () -> String,
                                         permission: SharePermission, lifetime: ShareLifetime,
                                         oneTime: Bool) throws -> Minted {
        var proposed = ""
        let (created, secret) = try core.createShareRetryingID(
            permission: permission, lifetime: lifetime, oneTime: oneTime,
            makeID: { proposed = ShellXShareLink.apiID(newID()); return proposed })
        // The viewer derives access from the id in the URL: any other id is a link nobody can open.
        guard ShellXShareLink.apiID(created.id) == proposed else {
            try? core.revokeShare(id: created.id)
            throw ShellXShareError.secureLinkUnavailable
        }
        return Minted(secret: secret, created: created)
    }

    // MARK: Resume (§7.3: a link still valid works again after the app reopens)

    /// Once signed in, re-hosts every persisted 15 m / 1 h link that has not expired and whose workspace
    /// still exists. The rest are forgotten; an unexpired one whose workspace is gone is revoked.
    private func resumePersisted() {
        guard !resumed, isSignedIn, sessionRestored else { return }
        resumed = true
        account = env.accountID()
        guard let account else {
            Self.log.error("share resume skipped: no account id")
            return
        }
        let now = env.clock()
        var orphaned: [String] = []
        for saved in env.store.load(account: account) {
            let id = ShellXShareLink.displayID(saved.id)
            guard saved.expiresAt > now, entries[id] == nil, let secret = ShareSecret(base64url: saved.secret)
            else { continue }
            guard let source = env.source(saved.workspaceID) else { orphaned.append(saved.id); continue }
            let share = ActiveShare(
                id: id, url: ShellXShareLink.url(id: saved.id, secret: secret), permission: saved.permission,
                lifetime: saved.lifetime, workspaceID: saved.workspaceID, oneTime: false,
                expiresAt: saved.expiresAt, claimUntil: nil, viewers: [])
            attach(share, slot: saved.slot, secret: secret, source: source, persisted: saved)
        }
        persist()
        if !orphaned.isEmpty {
            let core = env.core
            Task { _ = await Self.revokeOnCore(core: core, ids: orphaned) }
        }
    }

    private func persist() {
        guard let account = account ?? (isSignedIn ? env.accountID() : nil) else { return }
        self.account = account
        env.store.save(entries.values.compactMap(\.persisted).sorted { $0.id < $1.id }, account: account)
    }

    // MARK: Stop

    /// "Thu hồi link": every viewer gets `bye(revoked)` and the API forgets the link. False when the API
    /// did not confirm (the link is stopped here either way).
    @discardableResult
    func revoke(_ id: String) async -> Bool {
        guard let entry = take(id) else { return true }
        let apiID = ShellXShareLink.apiID(id)
        pendingRevokes.insert(apiID)
        defer { pendingRevokes.remove(apiID) }
        await entry.host.stop(reason: .revoked)
        // Quit may have revoked it meanwhile (it takes `pendingRevokes`); revoking twice is harmless.
        return await Self.revokeOnCore(core: env.core, ids: [apiID])
    }

    /// The host ended (its stream finished) or `expiresAt` passed.
    private func ended(_ id: String, reason: ShareByeReason?) {
        guard let entry = take(id) else { return }
        if let reason { Task { await entry.host.stop(reason: reason) } }
    }

    /// Quit (U14): `bye(host_quit)` to everyone; revokes until-quit and one-time shares. 15 m / 1 h links
    /// stay valid on the API and in the store, and resume at the next launch.
    func stopAll() async {
        let (hosts, revokeIDs) = takeAllForQuit()
        let core = env.core
        await withTaskGroup(of: Void.self) { group in
            for host in hosts { group.addTask { await host.stop(reason: .hostQuit) } }
            group.addTask { _ = await Self.revokeOnCore(core: core, ids: revokeIDs) }
        }
    }

    /// `applicationWillTerminate`. The main thread is blocked here (and may already be inside a main-actor
    /// task, so nothing new on the main actor would run): the hosts send `bye(host_quit)` through
    /// `stopForTermination` and the API revokes run on a background queue, waited on for at most
    /// `terminationBudget`.
    func stopAllForTermination() {
        let (hosts, revokeIDs) = takeAllForQuit()
        guard !hosts.isEmpty || !revokeIDs.isEmpty else { return }
        let core = env.core
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await withTaskGroup(of: Void.self) { group in
                for host in hosts { group.addTask { await host.stopForTermination(reason: .hostQuit) } }
                group.addTask {
                    for id in revokeIDs {
                        do { try core.revokeShare(id: id) } catch {
                            Self.log.error("share revoke failed: \(ShellXShareLogCode.of(error), privacy: .public)")
                        }
                    }
                }
            }
            done.signal()
        }
        if done.wait(timeout: .now() + Self.terminationBudget) == .timedOut {
            Self.log.error("share stop exceeded the termination budget")
        }
    }

    /// Empties the list for quit; the store keeps the links that resume.
    private func takeAllForQuit() -> (hosts: [any ShellXShareHosting], revokeIDs: [String]) {
        let shares = active
        let revokeIDs = shares.filter { !$0.resumesAfterRelaunch }.map { ShellXShareLink.apiID($0.id) }
            + pendingRevokes.sorted()
        var hosts: [any ShellXShareHosting] = []
        for share in shares {
            guard let entry = entries.removeValue(forKey: share.id) else { continue }
            entry.tasks.forEach { $0.cancel() }
            hosts.append(entry.host)
        }
        active = []
        return (hosts, revokeIDs)
    }

    /// Removes one share from the list and the store.
    private func take(_ id: String) -> Entry? {
        guard let entry = entries.removeValue(forKey: id) else { return nil }
        entry.tasks.forEach { $0.cancel() }
        active.removeAll { $0.id == id }
        persist()
        return entry
    }

    /// True when every revoke succeeded.
    nonisolated private static func revokeOnCore(core: ShellXCoreClient, ids: [String]) async -> Bool {
        guard !ids.isEmpty else { return true }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var ok = true
                for id in ids {
                    do { try core.revokeShare(id: id) } catch {
                        ok = false
                        log.error("share revoke failed: \(ShellXShareLogCode.of(error), privacy: .public)")
                    }
                }
                cont.resume(returning: ok)
            }
        }
    }

    nonisolated private static func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { cont.resume(with: Result { try work() }) }
        }
    }
}

/// A secret-free code for logs.
enum ShellXShareLogCode {
    static func of(_ error: any Error) -> String {
        switch error {
        case let core as ShellXCoreError: return core.code
        case let share as ShellXShareError: return "\(share)"
        default: return String(describing: type(of: error))
        }
    }
}

extension ShellXShareEnvironment {
    @MainActor
    static func forApp() -> ShellXShareEnvironment {
        ShellXShareEnvironment(
            core: ShellXCoreClient(ShellXCoreFFI.shared),
            sockets: URLSessionShareSocketFactory(),
            signedIn: ShellXRemoteService.shared.$isSignedIn.removeDuplicates().eraseToAnyPublisher(),
            sessionRestored: ShellXSessionRestoreSignal.completed.eraseToAnyPublisher(),
            accountID: { ShellXRemoteService.shared.accountOwnerID },
            presentSignIn: { ShellXRemoteUIActions.presentSignIn() },
            source: { workspaceID in
                guard let workspace = ShellXShareActions.workspace(id: workspaceID) else { return nil }
                return WorkspaceShareSource(workspace: workspace)
            },
            store: KeychainShellXShareStore())
    }
}

/// ShellX: tells the share controller when the launch's session restore has finished (or was skipped).
/// `AppDelegate` calls `update()` whenever its restore flags change; the check runs on the next turn,
/// because a restore pass sets `didAttemptStartupSessionRestore` just before `isApplyingSessionRestore`.
@MainActor
enum ShellXSessionRestoreSignal {
    static let completed = CurrentValueSubject<Bool, Never>(false)

    static func update() {
        guard !completed.value else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard !completed.value, AppDelegate.shared?.didCompleteInitialSessionRestore == true else { return }
                completed.send(true)
            }
        }
    }
}
