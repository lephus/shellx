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
final class ShellXLinkHostController: RemoteLinkHosting {
    /// The phone-side invite `shellx.link.debug_invite` returns: everything a probe needs to connect.
    struct DebugInvite: Sendable {
        let relayURL: String
        let slot: String
        let ticket: String
        let expiresAtUnix: Int64
        let hostKeyB64: String
    }

    private struct Running {
        let machineID: String
        let linkSlot: String
        let task: Task<Void, Never>
    }

    nonisolated static let log = Logger(subsystem: "pro.shellx.desktop", category: "link-host")

    private let core: ShellXCoreClient
    private let keys: ShellXLinkKeyStore
    private let feed: any AgentFeedSource
    private let hostVersion: String
    private let machineName: String
    private var running: Running?

    /// - Parameters:
    ///   - core: shellx-core, for link-lane tickets.
    ///   - keys: The host key and the trusted phones.
    ///   - feed: What phones see and answer (the app passes ``ShellXLinkFeedSource``).
    ///   - hostVersion: The app version sent in `welcome`.
    ///   - machineName: This Mac's name sent in `welcome`.
    init(core: ShellXCoreClient, keys: ShellXLinkKeyStore, feed: any AgentFeedSource, hostVersion: String,
         machineName: String) {
        self.core = core
        self.keys = keys
        self.feed = feed
        self.hostVersion = hostVersion
        self.machineName = machineName
    }

    func start(machineID: String, linkSlot: String) {
        stop()
        // The service already runs only with the gate on; the link host never outlives that rule.
        guard ShellXRemoteGate.isEnabled else { return }
        let core = core, keys = keys, feed = feed, hostVersion = hostVersion, machineName = machineName
        let task = Task.detached {
            await Self.serve(linkSlot: linkSlot, core: core, keys: keys, feed: feed, hostVersion: hostVersion,
                             machineName: machineName)
        }
        running = Running(machineID: machineID, linkSlot: linkSlot, task: task)
        Self.log.info("link host starting on slot \(linkSlot, privacy: .public)")
    }

    func stop() {
        guard let running else { return }
        running.task.cancel()
        self.running = nil
        Self.log.info("link host stopped")
    }

    /// DEBUG spike pairing (`shellx.link.debug_invite`): trusts `clientKey`, then mints a link-lane connect
    /// ticket to this machine itself (D3).
    ///
    /// - Parameter clientKey: The phone's 32-byte static public key.
    /// - Throws: ``ShellXCoreError``: `link_not_running` while no link slot is served, `invalid_params`
    ///   for a key that is not 32 bytes, or the mint's error.
    func debugInvite(clientKey: Data) async throws -> DebugInvite {
        guard let running else {
            throw ShellXCoreError(code: "link_not_running", message: "this Mac is not serving ShellX Link")
        }
        guard clientKey.count == 32 else {
            throw ShellXCoreError(code: "invalid_params", message: "client_key_b64 must be a 32-byte key")
        }
        let keys = keys, core = core, machineID = running.machineID, linkSlot = running.linkSlot
        let hostKey = try await Self.offMain { () -> Data in
            let key = try keys.hostKey()
            try keys.trust(clientKey)
            return key.publicKey
        }
        let ticket = try await Self.offMain {
            try core.mintLinkTicket(.connect(targetMachineID: machineID), expectedSlot: linkSlot)
        }
        return DebugInvite(relayURL: ticket.relayURL.absoluteString, slot: linkSlot, ticket: ticket.ticket,
                           expiresAtUnix: ticket.expiresAtUnix, hostKeyB64: hostKey.base64EncodedString())
    }

    // MARK: - Serving

    /// Registers and serves until cancelled; a failed registration is retried on the reconnect backoff.
    /// A ticket for another slot (an old relay) ends it: retrying cannot fix that.
    private nonisolated static func serve(linkSlot: String, core: ShellXCoreClient, keys: ShellXLinkKeyStore,
                                          feed: any AgentFeedSource, hostVersion: String,
                                          machineName: String) async {
        var attempt = 0
        while !Task.isCancelled {
            do {
                let hostKey = try await offMain { () -> NoiseStaticKey in
                    try keys.load()
                    return try keys.hostKey()
                }
                let first = try await offMain { try core.mintLinkTicket(.register, expectedSlot: linkSlot) }
                let prefetched = PrefetchedTicket(RelayTicket(ticket: first.ticket, expiresAtUnix: first.expiresAtUnix))
                let registration = RelayHostRegistration(relayURL: first.relayURL, slot: linkSlot) {
                    if let ticket = await prefetched.take() { return ticket }
                    let next = try await offMain { try core.mintLinkTicket(.register, expectedSlot: linkSlot) }
                    return RelayTicket(ticket: next.ticket, expiresAtUnix: next.expiresAtUnix)
                }
                let host = LinkHost(key: hostKey, trustedClients: { keys.trustedClients() }, feed: feed,
                                    hostVersion: hostVersion, machineName: machineName)
                log.info("link host registering slot \(linkSlot, privacy: .public)")
                try await registration.run { circuit in await host.serve(circuit) }
                attempt = 0
            } catch {
                guard !Task.isCancelled else { return }
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

    /// Runs a blocking core or file call on a global queue: never on the main thread, never on the
    /// cooperative pool (`ShellXCoreFFI.call` blocks on HTTP).
    nonisolated static func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(with: Result { try work() }) }
        }
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
