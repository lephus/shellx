import AppKit
import Combine
import Foundation
import os
import ShellXBrand
import ShellXRemoteCore

/// ShellX: the one switch for share links (L7). On when `ShellXFeatures.shareLinks` is flipped, or in
/// DEBUG builds launched with `SHELLX_SHARE_LINKS=1`. Off, no entrypoint shows and nothing calls the
/// core. Independent of `ShellXRemoteGate` (ruling R1).
enum ShellXShareGate {
    static let environmentKey = "SHELLX_SHARE_LINKS"

    @MainActor static var isEnabled: Bool {
        #if DEBUG
        if let overrideForTesting { return overrideForTesting }
        #endif
        return isEnabled(flag: ShellXFeatures.shareLinks, environment: ProcessInfo.processInfo.environment)
    }

    static func isEnabled(flag: Bool, environment: [String: String]) -> Bool {
        if flag { return true }
        #if DEBUG
        return environment[environmentKey] == "1"
        #else
        return false
        #endif
    }

    #if DEBUG
    /// Tests only: forces the gate either way; nil reads the flag and environment.
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
    let expiresAt: Date?
    let claimUntil: Date?
    var viewers: [ShareViewer]
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
        case .secureLinkUnavailable, .failed:
            return String(localized: "share.error.failed", defaultValue: "Couldn't create the link. Try again.")
        }
    }
}

/// What the controller needs of a `ShareHost` (B4); tests may substitute one.
protocol ShellXShareHosting: AnyObject, Sendable {
    func start() async
    func stop(reason: ShareByeReason) async
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
    var isSignedIn: @MainActor () -> Bool
    var presentSignIn: @MainActor () -> Void
    var source: @MainActor (UUID) -> (any ShareSource)?
    /// A fresh 8-character share id the client proposes (ruling 6; R4 derives `access` from it).
    var newShareID: @Sendable () -> String = { ShellXShareLink.randomID() }
    var clock: @Sendable () -> Date = { Date() }
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

    /// Quit: stops and revokes only if a controller was ever made (gate off makes no core call).
    static func stopAllForTerminationIfStarted() {
        instance?.stopAllForTermination()
    }

    nonisolated static let log = Logger(subsystem: "pro.shellx.desktop", category: "share")
    nonisolated static let terminationBudget: TimeInterval = 1.5

    @Published private(set) var active: [ActiveShare] = []

    private let env: ShellXShareEnvironment
    private var hosts: [String: any ShellXShareHosting] = [:]
    private var viewerTasks: [String: Task<Void, Never>] = [:]

    init(environment: ShellXShareEnvironment) {
        env = environment
    }

    var isSignedIn: Bool { env.isSignedIn() }

    func presentSignIn() { env.presentSignIn() }

    func shares(for workspaceID: UUID) -> [ActiveShare] {
        active.filter { $0.workspaceID == workspaceID }
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
        try await start(workspaceID: workspaceID, permission: .type, lifetime: .untilQuit, oneTime: true).url
    }

    /// Same as `phoneHandoff`, returning the whole share (the popover needs `claimUntil`).
    func startPhoneHandoff(workspaceID: UUID) async throws -> ActiveShare {
        try await start(workspaceID: workspaceID, permission: .type, lifetime: .untilQuit, oneTime: true)
    }

    private func start(workspaceID: UUID, permission: SharePermission, lifetime: ShareLifetime,
                       oneTime: Bool) async throws -> ActiveShare {
        guard env.isSignedIn() else { throw ShellXShareError.notSignedIn }
        guard let source = env.source(workspaceID) else { throw ShellXShareError.workspaceUnavailable }
        let core = env.core, newID = env.newShareID
        let minted: Minted
        do {
            minted = try await Self.offMain {
                try Self.mint(core: core, newID: newID, permission: permission, lifetime: lifetime, oneTime: oneTime)
            }
        } catch {
            Self.log.error("share create failed: \(RemoteLogCode.of(error), privacy: .public)")
            throw ShellXShareError.from(error)
        }
        let expiresAt = lifetime == .untilQuit ? nil : Date(timeIntervalSince1970: minted.created.expiresAtUnix)
        let share = ActiveShare(
            id: ShellXShareLink.displayID(minted.created.id),
            url: ShellXShareLink.url(id: minted.created.id, secret: minted.secret),
            permission: permission, lifetime: lifetime, workspaceID: workspaceID, oneTime: oneTime,
            expiresAt: expiresAt,
            claimUntil: minted.created.claimUntilUnix.map(Date.init(timeIntervalSince1970:)),
            viewers: [])
        let spec = ShellXShareEnvironment.HostSpec(
            shareID: minted.created.id, slot: minted.created.slot, secret: minted.secret,
            permission: permission, expiresAt: expiresAt, source: source)
        let host = env.makeHost?(spec) ?? ShareHost(
            shareID: spec.shareID, slot: spec.slot, secret: spec.secret, permission: spec.permission,
            expiresAt: spec.expiresAt, source: spec.source, tickets: ShellXCoreShareTickets(core: core),
            sockets: env.sockets, clock: env.clock)
        hosts[share.id] = host
        active.append(share)
        watchViewers(of: host, shareID: share.id)
        Task { await host.start() }
        return share
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

    private func watchViewers(of host: any ShellXShareHosting, shareID: String) {
        let stream = host.viewerStream
        viewerTasks[shareID] = Task { @MainActor [weak self] in
            for await viewers in stream {
                guard let self, let index = self.active.firstIndex(where: { $0.id == shareID }) else { return }
                self.active[index].viewers = viewers
            }
        }
    }

    // MARK: Stop

    /// "Thu hồi link": every viewer gets `bye(revoked)` and the API forgets the link.
    func revoke(_ id: String) async {
        guard let share = take(id) else { return }
        await share.host?.stop(reason: .revoked)
        await Self.revokeOnCore(core: env.core, ids: [share.share.id])
    }

    /// Quit (U14): `bye(host_quit)` to everyone; revokes until-quit and one-time shares. 15 m / 1 h links
    /// stay valid on the API until they expire.
    func stopAll() async {
        let taken = active.map(\.id).compactMap(take)
        let revokeIDs = taken.filter { $0.share.lifetime == .untilQuit || $0.share.oneTime }.map(\.share.id)
        let core = env.core
        await withTaskGroup(of: Void.self) { group in
            for entry in taken { if let host = entry.host { group.addTask { await host.stop(reason: .hostQuit) } } }
            group.addTask { await Self.revokeOnCore(core: core, ids: revokeIDs) }
        }
    }

    /// `applicationWillTerminate`: `stopAll`, bounded by `terminationBudget`. The revokes run off the
    /// main thread; the hosts need the main actor, so the main run loop turns while waiting.
    func stopAllForTermination() {
        guard !active.isEmpty else { return }
        let done = OSAllocatedUnfairLock(initialState: false)
        Task { @MainActor in
            await self.stopAll()
            done.withLock { $0 = true }
        }
        let deadline = Date().addingTimeInterval(Self.terminationBudget)
        while !done.withLock({ $0 }), Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        if !done.withLock({ $0 }) { Self.log.error("share stop exceeded the termination budget") }
    }

    private func take(_ id: String) -> (share: ActiveShare, host: (any ShellXShareHosting)?)? {
        guard let index = active.firstIndex(where: { $0.id == id }) else { return nil }
        let share = active.remove(at: index)
        viewerTasks.removeValue(forKey: id)?.cancel()
        return (share, hosts.removeValue(forKey: id))
    }

    nonisolated private static func revokeOnCore(core: ShellXCoreClient, ids: [String]) async {
        guard !ids.isEmpty else { return }
        await offMainVoid {
            for id in ids {
                do { try core.revokeShare(id: id) } catch {
                    Self.log.error("share revoke failed: \(RemoteLogCode.of(error), privacy: .public)")
                }
            }
        }
    }

    nonisolated private static func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { cont.resume(with: Result { try work() }) }
        }
    }

    nonisolated private static func offMainVoid(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { work(); cont.resume() }
        }
    }
}

/// A secret-free code for logs.
enum RemoteLogCode {
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
            isSignedIn: { ShellXRemoteService.shared.isSignedIn },
            presentSignIn: { ShellXRemoteUIActions.presentSignIn() },
            source: { workspaceID in
                guard let workspace = ShellXShareActions.workspace(id: workspaceID) else { return nil }
                return WorkspaceShareSource(workspace: workspace)
            })
    }
}
