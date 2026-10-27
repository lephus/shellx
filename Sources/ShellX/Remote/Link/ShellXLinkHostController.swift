import Foundation
import os
import ShellXLinkCore
import ShellXLinkRelay
import ShellXLinkSession
import ShellXRemoteCore

/// ShellX: this Mac's ShellX Link host (P1 spike). It keeps the machine's link slot registered on the
/// relay (`tickets.mint {permission: "register", lane: "link"}`, a fresh ticket per registration) and serves
/// every incoming circuit with a `LinkHost` over the agent Feed.
///
/// `ShellXRemoteService` starts it once `machines.register` returned a `link_slot`, which happens only while
/// `ShellXRemoteGate` is on, and stops it when the host session ends. Logs carry slots, codes and counts,
/// never a ticket or a key.
@MainActor
final class ShellXLinkHostController: RemoteLinkHosting, PhonePairingHosting {
    private struct Running {
        let machineID: String
        let linkSlot: String
        let accountID: String
        let keys: ShellXLinkKeyStore
        let liveHost: LiveLinkHost
        let task: Task<Void, Never>
    }

    nonisolated static let log = Logger(subsystem: "pro.shellx.desktop", category: "link-host")

    /// shellx-core: link-lane tickets here, and the `phones.*` calls of phone pairing.
    let core: ShellXCoreClient
    private let storage: any ShellXLinkSecretStorage
    private let feed: any AgentFeedSource
    private let hostVersion: String
    private let machineName: String
    private var running: Running?

    /// - Parameters:
    ///   - core: shellx-core, for link-lane tickets.
    ///   - storage: Where the host key and the trusted phones are kept (the Keychain in the app).
    ///   - feed: What phones see and answer (the app passes ``ShellXLinkFeedSource``).
    ///   - hostVersion: The app version sent in `welcome`.
    ///   - machineName: This Mac's name sent in `welcome`.
    init(core: ShellXCoreClient, storage: any ShellXLinkSecretStorage, feed: any AgentFeedSource, hostVersion: String,
         machineName: String) {
        self.core = core
        self.storage = storage
        self.feed = feed
        self.hostVersion = hostVersion
        self.machineName = machineName
    }

    func start(machineID: String, linkSlot: String, accountID: String) {
        stop()
        // The service already runs only with the gate on; the link host never outlives that rule.
        guard ShellXRemoteGate.isEnabled else { return }
        let core = core, feed = feed, hostVersion = hostVersion, machineName = machineName
        let keys = ShellXLinkKeyStore(storage: storage, accountID: accountID)
        let liveHost = LiveLinkHost()
        let task = Task.detached {
            await Self.serve(linkSlot: linkSlot, core: core, keys: keys, liveHost: liveHost, feed: feed,
                             hostVersion: hostVersion, machineName: machineName)
        }
        running = Running(machineID: machineID, linkSlot: linkSlot, accountID: accountID, keys: keys,
                          liveHost: liveHost, task: task)
        Self.log.info("link host starting on slot \(linkSlot, privacy: .public)")
    }

    func stop() {
        guard let running else { return }
        running.task.cancel()
        self.running = nil
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

    /// Loads the host key and the trusted list. A transient Keychain error (locked or not yet available) is
    /// retried on the reconnect backoff; anything else, such as corrupt data, is logged as `link_keys_corrupt`
    /// and thrown at once: the host fails closed and never replaces the key or the list.
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
                try await sleep(.seconds(ReconnectBackoff.delay(attempt: attempt)))
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
                                          liveHost: LiveLinkHost, feed: any AgentFeedSource, hostVersion: String,
                                          machineName: String) async {
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
                let host = LinkHost(key: hostKey, trustedClients: { keys.trustedClients() }, feed: feed,
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
