import CmuxSettings
import Foundation
import os
import ShellXLinkCore
import ShellXLinkRelay
import ShellXLinkSession
import ShellXRemoteCore

/// ShellX: this Mac's ShellX Link host (P1 spike). It keeps the machine's link slot registered on the
/// relay (`tickets.mint {permission: "register", lane: "link"}`, a fresh ticket per registration) and serves
/// every incoming circuit with a `LinkHost` over the agent Feed, the agent sessions and their chat, the
/// Mac's workspaces and terminals (viewing, typing, a new tab), and closing an agent's tab.
///
/// `ShellXRemoteService` starts it once `machines.register` returned a `link_slot`, which happens only while
/// `ShellXRemoteGate.servesPhones` is on, and stops it when the host session ends. Logs carry slots, codes and
/// counts, never a ticket or a key.
///
/// A configuration profile that disables remote control or incoming device access
/// (``MobileRemoteControlPolicy/isDisabled``) keeps it from serving: it does not start, a running host stops
/// when the profile arrives (`ManagedDevicePolicy.didChangeNotification`), and the session still signed in is
/// served again once the profile is removed.
@MainActor
final class ShellXLinkHostController: RemoteLinkHosting, PhonePairingHosting {
    /// What the service asked to serve.
    private struct Assignment {
        let machineID: String
        let linkSlot: String
        let accountID: String
    }

    private struct Running {
        let machineID: String
        let linkSlot: String
        let accountID: String
        let keys: ShellXLinkKeyStore
        let liveHost: LiveLinkHost
        let task: Task<Void, Never>
    }

    nonisolated static let log = Logger(subsystem: "pro.shellx.desktop", category: "link-host")

    /// What the link host serves phones from: the agent Feed and every optional ShellX Link source.
    struct Sources: Sendable {
        var feed: any AgentFeedSource
        var sessions: (any AgentSessionSource)?
        var chat: (any AgentChatSource)?
        var workspaces: (any WorkspaceSource)?
        var workspaceControl: (any WorkspaceControl)?
        var agentControl: (any AgentControl)?
        var terminalControl: (any TerminalControl)?
        var terminalViews: (any TerminalViewSource)?
        var terminalCreator: (any TerminalCreator)?
    }

    /// The `LinkHost` of one registration attempt over `sources` (the only place sources enter a host).
    nonisolated static func makeLinkHost(key: NoiseStaticKey, trustedClients: @escaping @Sendable () -> Set<Data>,
                                         sources: Sources, hostVersion: String, machineName: String) -> LinkHost {
        LinkHost(key: key, trustedClients: trustedClients, feed: sources.feed,
                 sessions: sources.sessions, chat: sources.chat, workspaces: sources.workspaces,
                 workspaceControl: sources.workspaceControl, agentControl: sources.agentControl,
                 terminalControl: sources.terminalControl, terminalViews: sources.terminalViews,
                 terminalCreator: sources.terminalCreator, hostVersion: hostVersion, machineName: machineName)
    }

    /// shellx-core: link-lane tickets here, and the `phones.*` calls of phone pairing.
    let core: ShellXCoreClient
    private let storage: any ShellXLinkSecretStorage
    private let sources: Sources
    private let hostVersion: String
    private let machineName: String
    private let isBlockedByPolicy: @MainActor () -> Bool
    /// Pushes "an agent needs you" to the paired iPhones while the host runs.
    private let phonePush: ShellXPhonePushForwarder?
    /// The session the service started, until it stops it. Kept while a managed policy holds the host stopped,
    /// so lifting the policy serves the same session again.
    private var assignment: Assignment?
    private var running: Running?
    private var policyObservation: ManagedPolicyObservation?

    /// - Parameters:
    ///   - core: shellx-core, for link-lane tickets.
    ///   - storage: Where the host key and the trusted phones are kept (the Keychain in the app).
    ///   - feed: What phones see and answer (the app passes ``ShellXLinkFeedSource``).
    ///   - sessions: The agent session list (the app passes ``ShellXLinkSessionSource``).
    ///   - chat: Transcripts and chat commands (the app passes ``ShellXLinkChatSource``).
    ///   - workspaces: The workspace list (the app passes ``ShellXLinkWorkspaceSource``).
    ///   - workspaceControl: Making, renaming and closing workspaces (the app passes the same
    ///     ``ShellXLinkWorkspaceSource``).
    ///   - agentControl: Closing an agent's terminal tab (the app passes the same ``ShellXLinkWorkspaceSource``).
    ///   - terminalControl: Closing a terminal tab the phone's user picked (the app passes the same
    ///     ``ShellXLinkWorkspaceSource``).
    ///   - terminalViews: A phone's view of a Mac terminal (the app passes ``ShellXLinkTerminalViewSource``).
    ///   - terminalCreator: Opening a terminal tab in a listed workspace (the app passes the same
    ///     ``ShellXLinkWorkspaceSource``).
    ///   - hostVersion: The app version sent in `welcome`.
    ///   - machineName: This Mac's name sent in `welcome`.
    ///   - isBlockedByPolicy: Whether a configuration profile forbids serving phones (`DisableRemoteControl`
    ///     or `DisableIncomingDeviceAccess`).
    ///   - notificationCenter: Where `ManagedDevicePolicy.didChangeNotification` is posted.
    ///   - phonePush: Tells the paired iPhones about waiting requests while the host runs (the app passes
    ///     ``ShellXPhonePushForwarder/live(feed:core:)``).
    init(core: ShellXCoreClient, storage: any ShellXLinkSecretStorage, feed: any AgentFeedSource,
         sessions: (any AgentSessionSource)? = nil, chat: (any AgentChatSource)? = nil,
         workspaces: (any WorkspaceSource)? = nil, workspaceControl: (any WorkspaceControl)? = nil,
         agentControl: (any AgentControl)? = nil, terminalControl: (any TerminalControl)? = nil,
         terminalViews: (any TerminalViewSource)? = nil, terminalCreator: (any TerminalCreator)? = nil,
         hostVersion: String,
         machineName: String, isBlockedByPolicy: @escaping @MainActor () -> Bool = { MobileRemoteControlPolicy.isDisabled },
         notificationCenter: NotificationCenter = .default, phonePush: ShellXPhonePushForwarder? = nil) {
        self.core = core
        self.phonePush = phonePush
        self.storage = storage
        self.sources = Sources(
            feed: feed, sessions: sessions, chat: chat, workspaces: workspaces, workspaceControl: workspaceControl,
            agentControl: agentControl, terminalControl: terminalControl, terminalViews: terminalViews,
            terminalCreator: terminalCreator)
        self.hostVersion = hostVersion
        self.machineName = machineName
        self.isBlockedByPolicy = isBlockedByPolicy
        policyObservation = ManagedPolicyObservation(center: notificationCenter) { [weak self] in
            self?.managedPolicyChanged()
        }
    }

    func start(machineID: String, linkSlot: String, accountID: String) {
        stop()
        // The service already runs only while it serves phones; the link host never outlives that rule.
        guard ShellXRemoteGate.servesPhones else { return }
        let assignment = Assignment(machineID: machineID, linkSlot: linkSlot, accountID: accountID)
        self.assignment = assignment
        guard !isBlockedByPolicy() else {
            Self.log.notice("link host not started: remote control is turned off by a managed policy")
            return
        }
        launch(assignment)
    }

    func stop() {
        assignment = nil
        halt()
    }

    /// A managed policy changed: a profile that now forbids serving phones stops the running host, and once
    /// it is removed the session still assigned is served again.
    func managedPolicyChanged() {
        if isBlockedByPolicy() {
            guard running != nil else { return }
            halt()
            Self.log.notice("link host stopped: remote control is turned off by a managed policy")
        } else if running == nil, let assignment {
            Self.log.info("managed policy allows remote control again")
            launch(assignment)
        }
    }

    private func launch(_ assignment: Assignment) {
        let core = core, sources = sources
        let hostVersion = hostVersion, machineName = machineName, linkSlot = assignment.linkSlot
        let keys = ShellXLinkKeyStore(storage: storage, accountID: assignment.accountID)
        let liveHost = LiveLinkHost()
        let task = Task.detached {
            await Self.serve(linkSlot: linkSlot, core: core, keys: keys, liveHost: liveHost, sources: sources,
                             hostVersion: hostVersion, machineName: machineName)
        }
        running = Running(machineID: assignment.machineID, linkSlot: linkSlot, accountID: assignment.accountID,
                          keys: keys, liveHost: liveHost, task: task)
        phonePush?.start()
        Self.log.info("link host starting on slot \(linkSlot, privacy: .public)")
    }

    private func halt() {
        guard let running else { return }
        running.task.cancel()
        self.running = nil
        phonePush?.stop()
        Self.log.info("link host stopped")
    }

    /// What a pairing QR offers and where an allowed phone is trusted, while the link host runs.
    var pairingHost: PhonePairingHost? {
        running.map {
            PhonePairingHost(machineID: $0.machineID, linkSlot: $0.linkSlot, accountID: $0.accountID,
                             machineName: machineName, keys: $0.keys)
        }
    }

    /// Removes the phone from the trusted list, then ends its live sessions. A new session with that key is
    /// refused from the moment the list changes. Does nothing while no link host runs.
    ///
    /// - Parameter clientKey: The phone's 32-byte static public key.
    func revoke(clientKey: Data) async {
        guard let running else { return }
        let keys = running.keys
        do {
            try await Self.offMain { try keys.untrust(key: clientKey) }
        } catch {
            Self.log.error("link revoke could not save the trusted list: \(Self.keyErrorKind(error), privacy: .public)")
            // Still cut the live sessions: the phone is being removed either way.
        }
        await running.liveHost.current()?.disconnect(clientKey: clientKey)
    }

    // MARK: - Serving

    /// How long the host waits before it reads the keys again after the person turned down the login
    /// keychain's prompt: each read of a locked login keychain asks again.
    nonisolated static let declinedPromptRetry: Duration = .seconds(600)

    /// Loads the host key and the trusted list. A transient Keychain error (locked or not yet available) is
    /// retried on the reconnect backoff, or after ``declinedPromptRetry`` when the person cancelled the login
    /// keychain's prompt or its password failed; anything else, such as corrupt data, is logged as
    /// `link_keys_corrupt` and thrown at once: the host fails closed and never replaces the key or the list.
    ///
    /// - Parameter sleep: Waits between attempts; tests pass a recorder.
    nonisolated static func loadKeys(_ keys: ShellXLinkKeyStore,
                                     sleep: (Duration) async throws -> Void) async throws -> NoiseStaticKey {
        var attempt = 0
        while true {
            do {
                return try await offMain { () -> NoiseStaticKey in
                    try keys.load()
                    return try keys.hostKey()
                }
            } catch ShellXLinkSecretError.transient(let status) {
                log.notice("link keys not available yet (\(status)); retrying")
                try await sleep(KeychainLinkSecretStorage.isDeclinedPrompt(status)
                    ? declinedPromptRetry : .seconds(ReconnectBackoff.delay(attempt: attempt)))
                attempt += 1
            } catch ShellXLinkSecretError.unavailable(let status) {
                log.error("link host stopped: keychain_unavailable (\(status))")
                throw ShellXLinkSecretError.unavailable(status)
            } catch {
                log.error("link host stopped: link_keys_corrupt (\(keyErrorKind(error), privacy: .public))")
                throw error
            }
        }
    }

    /// How often the trusted phones are checked against the relay's grants.
    nonisolated static let reconcileInterval: Duration = .seconds(600)

    /// Drops trusted phones the relay no longer grants, and ends their live sessions. Only a successful
    /// `phones.grants` call counts: a failed call leaves the list alone. The relay can only remove trust.
    nonisolated static func reconcile(core: ShellXCoreClient, keys: ShellXLinkKeyStore, liveHost: LiveLinkHost) async {
        do {
            let removed = try await offMain { () -> Set<Data> in
                // Taken before the call: a phone paired while it is in flight must survive this round.
                let askedAt = Date()
                let granted = Set(try core.pairedPhones().map(\.clientKey))
                return try keys.retainOnly(keys: granted, pairedSince: askedAt)
            }
            guard !removed.isEmpty else { return }
            log.info("link host dropped \(removed.count) phone(s) the relay no longer grants")
            let host = await liveHost.current()
            for key in removed { await host?.disconnect(clientKey: key) }
        } catch {
            let code = (error as? ShellXCoreError)?.code ?? keyErrorKind(error)
            log.notice("link grants check skipped: \(code, privacy: .public)")
        }
    }

    /// Registers and serves until cancelled; a failed registration is retried on the reconnect backoff.
    /// A ticket for another slot (an old relay) ends it: retrying cannot fix that. So does an unreadable host
    /// key or trusted list: the host fails closed and never replaces the key.
    private nonisolated static func serve(linkSlot: String, core: ShellXCoreClient, keys: ShellXLinkKeyStore,
                                          liveHost: LiveLinkHost, sources: Sources,
                                          hostVersion: String, machineName: String) async {
        let hostKey: NoiseStaticKey
        do {
            hostKey = try await loadKeys(keys, sleep: { try await Task.sleep(for: $0) })
        } catch {
            return
        }
        let reconciler = Task {
            while !Task.isCancelled {
                await reconcile(core: core, keys: keys, liveHost: liveHost)
                do { try await Task.sleep(for: reconcileInterval) } catch { return }
            }
        }
        defer { reconciler.cancel() }
        var attempt = 0
        while !Task.isCancelled {
            let progress = RegistrationProgress()
            do {
                let first = try await offMain { try core.mintLinkTicket(.register, expectedSlot: linkSlot) }
                let prefetched = PrefetchedTicket(RelayTicket(ticket: first.ticket, expiresAtUnix: first.expiresAtUnix))
                let registration = RelayHostRegistration(relayURL: first.relayURL, slot: linkSlot, onEvent: { event in
                    // Codes only: never a ticket or a key.
                    switch event {
                    case .registered:
                        progress.markRegistered()
                        log.info("link host registered slot \(linkSlot, privacy: .public)")
                    case .renewed:
                        progress.markRegistered()
                        log.info("link host renewed registration for slot \(linkSlot, privacy: .public)")
                    case .failed(let code): log.error("link host registration attempt failed: \(code, privacy: .public)")
                    case .gaveUp(let code): log.error("link host registration gave up: \(code, privacy: .public)")
                    }
                }) {
                    if let ticket = await prefetched.take() { return ticket }
                    let next = try await offMain { try core.mintLinkTicket(.register, expectedSlot: linkSlot) }
                    return RelayTicket(ticket: next.ticket, expiresAtUnix: next.expiresAtUnix)
                }
                let host = makeLinkHost(key: hostKey, trustedClients: { keys.trustedClients() }, sources: sources,
                                        hostVersion: hostVersion, machineName: machineName)
                await liveHost.set(host)
                log.info("link host registering slot \(linkSlot, privacy: .public)")
                try await registration.run { circuit in await host.serve(circuit) }
            } catch {
                guard !Task.isCancelled else { return }
                // `run` only ends by throwing. A registration that succeeded before it gave up means the
                // relay was reachable, so the next attempt starts from the shortest backoff.
                if progress.registered { attempt = 0 }
                let code = (error as? ShellXCoreError)?.code ?? String(describing: type(of: error))
                if code == "link_slot_mismatch" {
                    log.error("link host stopped: the relay minted a ticket for another slot")
                    return
                }
                log.error("link host registration failed: \(code, privacy: .public)")
            }
            // A genuine backoff delay, cancelled with the task (never a poll).
            let delay = ReconnectBackoff.delay(attempt: attempt)
            attempt += 1
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
        }
    }

    /// A secret-free kind for a host key or trusted list failure (never file bytes).
    nonisolated static func keyErrorKind(_ error: any Error) -> String {
        switch error {
        case let secret as ShellXLinkSecretError:
            switch secret {
            case .transient(let status): return "keychain_transient_\(status)"
            case .unavailable: return "keychain_unavailable"
            case .failed(let status): return "keychain_\(status)"
            }
        case is DecodingError: return "trusted_list_unreadable"
        case is NoiseError: return "host_key_invalid"
        default: return String(describing: type(of: error))
        }
    }

    /// Runs a blocking core or file call on a global queue: never on the main thread, never on the
    /// cooperative pool (`ShellXCoreFFI.call` blocks on HTTP).
    nonisolated static func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(with: Result { try work() }) }
        }
    }
}

/// Runs `handler` on the main actor for every `ManagedDevicePolicy.didChangeNotification`, until released.
/// `ManagedPolicyEnforcementObserver` posts it on the main thread whenever a profile's policy flips.
private final class ManagedPolicyObservation {
    private let center: NotificationCenter
    private let token: any NSObjectProtocol

    init(center: NotificationCenter, handler: @escaping @MainActor @Sendable () -> Void) {
        self.center = center
        token = center.addObserver(forName: ManagedDevicePolicy.didChangeNotification, object: nil,
                                   queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    deinit { center.removeObserver(token) }
}

/// The `LinkHost` of the current registration attempt, for `revoke` and the grants check.
actor LiveLinkHost {
    private var host: LinkHost?
    func set(_ host: LinkHost) { self.host = host }
    func current() -> LinkHost? { host }
}

/// Whether one `RelayHostRegistration.run` got a registration through (set from its events).
private final class RegistrationProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var registered: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }

    func markRegistered() {
        lock.lock()
        defer { lock.unlock() }
        flag = true
    }
}

/// The register ticket minted to learn the relay URL, handed to the first registration attempt only.
private actor PrefetchedTicket {
    private var ticket: RelayTicket?

    init(_ ticket: RelayTicket) { self.ticket = ticket }

    func take() -> RelayTicket? {
        defer { ticket = nil }
        return ticket
    }
}
