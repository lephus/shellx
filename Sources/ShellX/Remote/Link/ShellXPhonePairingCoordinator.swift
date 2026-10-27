import Combine
import Foundation
import os
import ShellXLinkCore
import ShellXRemoteCore

/// ShellX: the relay calls behind phone pairing (`phones.*`), so tests can stand in for shellx-core.
/// Every call blocks on the core FFI: call off the main thread.
protocol PhonePairingCalling: Sendable {
    func pendingPhonePairings() throws -> [PhonePairingRequest]
    func approvePhonePairing(_ id: String) throws
    func denyPhonePairing(_ id: String) throws
    func pairedPhones() throws -> [PairedPhone]
    func revokePhone(grantID: String) throws
}

extension ShellXCoreClient: PhonePairingCalling {}

/// This Mac's running link host as pairing needs it: what goes into the QR, and where an allowed phone is
/// trusted.
struct PhonePairingHost: Sendable {
    let machineID: String
    let linkSlot: String
    let accountID: String
    /// This Mac's name as the host reports it; ``ShellXPhonePairingCoordinator/offerName(_:fallback:)``
    /// makes it fit the QR.
    let machineName: String
    /// The running host's key store: a phone trusted here can open a session at once.
    let keys: ShellXLinkKeyStore

    /// Whether `other` serves the same link: same machine, slot and account.
    func servesSameLink(as other: PhonePairingHost) -> Bool {
        machineID == other.machineID && linkSlot == other.linkSlot && accountID == other.accountID
    }
}

/// The link host seen from pairing. The app's ``ShellXLinkHostController`` conforms.
@MainActor
protocol PhonePairingHosting: AnyObject {
    /// nil while no link host runs: the gate is off, the relay gave no link slot, or nobody is signed in.
    var pairingHost: PhonePairingHost? { get }
    /// Stops trusting `clientKey` and ends its live sessions at once.
    func revoke(clientKey: Data) async
}

/// ShellX: pairs iPhones with this Mac from the "Pair iPhone…" sheet.
///
/// A phone becomes trusted only when all three hold: it is on the same account (the relay lists only
/// those), its proof matches the QR this sheet shows now, and the person clicks Allow here. The relay can
/// only take trust away.
///
/// * **Open:** `open()` makes an offer and reads `phones.pending` every ``ShellXRemoteService/pollInterval``
///   while the sheet is open. An offer older than ``PairingOffer/lifetime`` is replaced. `close()` stops
///   the polling and drops the offer.
/// * **Proofs:** only a request whose proof matches the current offer becomes a ``Candidate``. Every other
///   one is refused without showing anything, and only counted in the log (`pairing_proof_mismatch`).
/// * **Allow:** the phone is trusted here first, then `phones.approve` grants it. A failed approval takes
///   the trust back. An approval spends the QR: the other requests for it are refused and a new QR shows.
/// * **Remove:** the host drops the phone and ends its sessions first, then `phones.revoke`. A relay
///   failure shows an error; the phone stays untrusted here (fail closed).
///
/// Core and key store calls run off the main thread. Logs carry counts and codes only: never the offer,
/// its code, a key or a proof.
@MainActor
final class ShellXPhonePairingCoordinator: ObservableObject {
    /// A request whose proof matches the QR on screen, waiting for Allow or Deny.
    struct Candidate: Identifiable, Equatable, Sendable {
        /// The relay's pairing id.
        let id: String
        let deviceName: String
        let platform: String
        /// The phone's 32-byte static public key.
        let clientKey: Data
    }

    nonisolated static let log = Logger(subsystem: "pro.shellx.desktop", category: "link-pairing")

    /// The offer the QR shows; nil while closed, not ready, or between two offers.
    @Published private(set) var offer: PairingOffer?
    /// Requests that answered the current offer, oldest first as the relay lists them.
    @Published private(set) var candidates: [Candidate] = []
    /// Phones that hold a grant on this Mac, oldest pairing first.
    @Published private(set) var phones: [PairedPhone] = []
    /// True once `phones` came from a successful `phones.grants`: an empty list then means no phones,
    /// not a failed read.
    @Published private(set) var phonesListed = false
    /// The last failure, ready to show.
    @Published private(set) var errorText: String?
    /// False while this Mac's link host does not run: no QR can be made.
    @Published private(set) var isReady = false
    /// Pairing ids and grant ids with a decision or removal in flight.
    @Published private(set) var busy: Set<String> = []

    /// Requests refused because their proof did not match the current offer.
    private(set) var proofMismatches = 0

    private let host: any PhonePairingHosting
    private let relay: any PhonePairingCalling
    private let pollInterval: Duration
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private let fallbackName: String

    private var isOpen = false
    /// Bumped by `open()` and `close()`: work begun in another session drops its result.
    private var generation = 0
    private var poller: Task<Void, Never>?
    /// The offer being made, shared by every round that needs one, so one QR is never replaced by a twin.
    private var offerTask: Task<Void, Never>?
    private var offerHost: PhonePairingHost?
    private var offerMadeAt: Date?
    /// Orders `phones.pending` answers: an older read never overwrites a newer one.
    private var pendingReads = 0
    private var appliedRead = 0
    /// Approved or refused here: a lagging relay that still lists them never shows or refuses them again.
    private var handled: Set<String> = []
    private var approving: Set<String> = []
    private var errorCameFromPoll = false

    /// - Parameters:
    ///   - host: The link host (``ShellXLinkHostController`` in the app).
    ///   - relay: The `phones.*` calls (shellx-core in the app).
    ///   - pollInterval: How often `phones.pending` is read while open.
    ///   - now: The clock offers age by.
    ///   - sleep: Waits between rounds; tests drive it by hand.
    ///   - fallbackName: The machine name the QR carries when this Mac's own name has nothing usable.
    init(host: any PhonePairingHosting,
         relay: any PhonePairingCalling,
         pollInterval: Duration = .seconds(ShellXRemoteService.pollInterval),
         now: @escaping @Sendable () -> Date = { Date() },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         fallbackName: String = String(localized: "terminalSharing.device.mac", defaultValue: "Mac")) {
        self.host = host
        self.relay = relay
        self.pollInterval = pollInterval
        self.now = now
        self.sleep = sleep
        self.fallbackName = fallbackName
    }

    // MARK: - Open and close

    /// Starts a pairing session: makes an offer and reads requests every `pollInterval` until `close()`.
    func open() {
        guard !isOpen else { return }
        isOpen = true
        generation += 1
        errorText = nil
        errorCameFromPoll = false
        isReady = host.pairingHost != nil
        let interval = pollInterval, sleep = sleep
        poller = Task { [weak self] in
            while !Task.isCancelled {
                guard await self?.pollNow() != nil else { return }
                do { try await sleep(interval) } catch { return }
            }
        }
    }

    /// Stops polling and drops the offer. Requests still waiting are refused: without their offer they can
    /// never be allowed, and the phone learns it at once instead of when the request expires.
    func close() {
        guard isOpen else { return }
        isOpen = false
        generation += 1
        poller?.cancel()
        poller = nil
        let waiting = retireOffer()
        candidates = []
        guard !waiting.isEmpty else { return }
        Task { await self.refuse(waiting) }
    }

    // MARK: - Rounds

    /// One round: makes or renews the offer when needed, then reads `phones.pending` against it. The
    /// poll timer runs it; the DEBUG socket methods and `approve` run it on demand.
    func pollNow() async {
        guard isOpen else { return }
        let session = generation
        guard let current = host.pairingHost else {
            becomeNotReady()
            return
        }
        if !isReady { isReady = true }
        if needsOffer(for: current) { await makeOfferOnce(for: current) }
        guard isOpen, generation == session, let offer else { return }
        await readPending(against: offer, session: session)
        if !phonesListed, isOpen, generation == session { await refreshPhones() }
    }

    /// The offer the QR shows, made now if there is none (`shellx.link.debug_pairing_offer`).
    ///
    /// - Throws: ``ShellXCoreError``: `pairing_not_open` when the sheet is closed, `link_not_running`
    ///   while this Mac serves no link.
    func currentOffer() async throws -> PairingOffer {
        guard isOpen else {
            throw ShellXCoreError(code: "pairing_not_open", message: "the phone pairing sheet is not open")
        }
        if let offer, let current = host.pairingHost, !needsOffer(for: current) { return offer }
        await pollNow()
        guard let offer else {
            throw ShellXCoreError(code: "link_not_running", message: "this Mac is not serving ShellX Link")
        }
        return offer
    }

    private func needsOffer(for current: PhonePairingHost) -> Bool {
        guard offer != nil, let offerHost, let offerMadeAt else { return true }
        guard current.servesSameLink(as: offerHost) else { return true }
        let age = now().timeIntervalSince(offerMadeAt)
        return age >= PairingOffer.lifetime || age < 0
    }

    private func becomeNotReady() {
        if isReady { isReady = false }
        let waiting = retireOffer()
        candidates = []
        guard !waiting.isEmpty else { return }
        Task { await self.refuse(waiting) }
    }

    private func makeOfferOnce(for current: PhonePairingHost) async {
        if let offerTask {
            await offerTask.value
            return
        }
        let task = Task { await self.makeOffer(for: current) }
        offerTask = task
        await task.value
        offerTask = nil
    }

    private func makeOffer(for current: PhonePairingHost) async {
        let session = generation
        let keys = current.keys
        let hostKey: Data
        do {
            hostKey = try await ShellXLinkHostController.offMain { try keys.hostKey().publicKey }
        } catch {
            guard isOpen, generation == session else { return }
            Self.log.error("pairing offer not made: \(ShellXLinkHostController.keyErrorKind(error), privacy: .public)")
            show(error, fromPoll: true)
            return
        }
        guard isOpen, generation == session else { return }
        let made = PairingOffer.make(machineID: current.machineID, linkSlot: current.linkSlot, hostKey: hostKey,
                                     machineName: Self.offerName(current.machineName, fallback: fallbackName))
        // The phone parses the QR strictly; never show one it would refuse.
        guard (try? PairingOffer(uri: made.uri)) == made else {
            Self.log.error("pairing offer not made: the machine id or link slot does not fit the QR")
            show(ShellXCoreError(code: "offer_unusable", message: "the pairing offer does not fit the QR format"),
                 fromPoll: true)
            return
        }
        // A new QR spends the old one: requests that answered it are refused.
        let waiting = retireOffer()
        offer = made
        offerHost = current
        offerMadeAt = now()
        await refuse(waiting)
    }

    /// Drops the offer and the candidates it produced, except one being allowed right now.
    ///
    /// - Returns: The pairing ids to refuse.
    private func retireOffer() -> [String] {
        offer = nil
        offerHost = nil
        offerMadeAt = nil
        let waiting = candidates.map(\.id).filter { !approving.contains($0) }
        let kept = candidates.filter { approving.contains($0.id) }
        if kept != candidates { candidates = kept }
        handled.formUnion(waiting)
        return waiting
    }

    private func readPending(against offer: PairingOffer, session: Int) async {
        pendingReads += 1
        let read = pendingReads
        let relay = relay
        let requests: [PhonePairingRequest]
        do {
            requests = try await ShellXLinkHostController.offMain { try relay.pendingPhonePairings() }
        } catch {
            guard isOpen, generation == session else { return }
            show(error, fromPoll: true)
            return
        }
        // A closed sheet, a new offer or a newer read makes this answer stale.
        guard isOpen, generation == session, self.offer == offer, read > appliedRead else { return }
        appliedRead = read
        clearPollError()
        var next: [Candidate] = []
        var mismatched: [String] = []
        for request in requests where !handled.contains(request.id) {
            if offer.verify(proof: request.proof, clientKey: request.clientKey) {
                next.append(Candidate(id: request.id, deviceName: request.deviceName, platform: request.platform,
                                      clientKey: request.clientKey))
            } else {
                mismatched.append(request.id)
            }
        }
        // One being allowed stays on screen until its approval finishes, even once the relay stops listing it.
        for candidate in candidates where approving.contains(candidate.id) && !next.contains(candidate) {
            next.append(candidate)
        }
        if next != candidates { candidates = next }
        guard !mismatched.isEmpty else { return }
        handled.formUnion(mismatched)
        proofMismatches += mismatched.count
        Self.log.notice("pairing_proof_mismatch: refused \(mismatched.count, privacy: .public) request(s)")
        await refuse(mismatched)
    }

    /// Refuses requests at the relay without telling anyone here; a failure is left to the request's expiry.
    private func refuse(_ ids: [String]) async {
        let relay = relay
        for id in ids {
            do {
                try await ShellXLinkHostController.offMain { try relay.denyPhonePairing(id) }
            } catch {
                let code = (error as? ShellXCoreError)?.code ?? "error"
                Self.log.notice("pairing request not refused: \(code, privacy: .public)")
            }
        }
    }

    // MARK: - Decisions

    /// Allows a candidate: trusts its key on this Mac, then has the relay grant it. A failed grant takes
    /// the trust back (a phone that was already paired keeps its earlier trust). Success spends the QR.
    ///
    /// - Parameter id: A candidate's pairing id. One not shown yet is looked for in a fresh round first.
    /// - Throws: ``ShellXCoreError`` `not_a_candidate` when no request with that id matches the current
    ///   offer, `link_not_running` while no link host runs, or the trust or relay failure.
    func approve(_ id: String) async throws {
        if !candidates.contains(where: { $0.id == id }) { await pollNow() }
        guard isOpen, let candidate = candidates.first(where: { $0.id == id }), !approving.contains(id) else {
            throw ShellXCoreError(code: "not_a_candidate",
                                  message: "no pairing request with that id answered the QR on screen")
        }
        guard let current = host.pairingHost else {
            throw ShellXCoreError(code: "link_not_running", message: "this Mac is not serving ShellX Link")
        }
        approving.insert(id)
        busy.insert(id)
        defer {
            approving.remove(id)
            busy.remove(id)
        }
        let keys = current.keys, relay = relay
        // The request carries no device id; the pairing id names the entry until the next pairing.
        let phone = TrustedPhone(key: candidate.clientKey, deviceID: id, name: candidate.deviceName, pairedAt: now())
        let previous: TrustedPhone?
        do {
            previous = try await ShellXLinkHostController.offMain { () -> TrustedPhone? in
                let previous = keys.trustedPhones().first { $0.key == phone.key }
                try keys.trust(phone)
                return previous
            }
        } catch {
            Self.log.error("pairing not allowed: \(ShellXLinkHostController.keyErrorKind(error), privacy: .public)")
            show(error)
            throw error
        }
        do {
            try await ShellXLinkHostController.offMain { try relay.approvePhonePairing(id) }
        } catch {
            do {
                try await ShellXLinkHostController.offMain {
                    if let previous { try keys.trust(previous) } else { try keys.untrust(key: phone.key) }
                }
            } catch {
                // `untrust` drops the key from memory before saving: the host refuses it either way.
                Self.log.error("pairing rollback not saved: \(ShellXLinkHostController.keyErrorKind(error), privacy: .public)")
            }
            let code = (error as? ShellXCoreError)?.code ?? "error"
            Self.log.notice("pairing approval failed: \(code, privacy: .public)")
            show(error)
            throw error
        }
        handled.insert(id)
        candidates.removeAll { $0.id == id }
        Self.log.info("paired a phone")
        // One QR, one phone: the QR that paired this one is spent.
        let waiting = retireOffer()
        await refuse(waiting)
        await pollNow()
        await refreshPhones()
    }

    /// Refuses a candidate. A relay failure is left to the request's expiry.
    func deny(_ id: String) async {
        guard !approving.contains(id) else { return }
        handled.insert(id)
        candidates.removeAll { $0.id == id }
        await refuse([id])
    }

    // MARK: - Paired phones

    /// Reads the phones that hold a grant. A failure keeps the last list and shows the error: one bad row
    /// fails the whole read, which must not look like "no phones".
    func refreshPhones() async {
        let relay = relay
        do {
            let list = try await ShellXLinkHostController.offMain { try relay.pairedPhones() }
            phones = list.sorted { $0.createdAt < $1.createdAt }
            phonesListed = true
        } catch {
            show(error)
        }
    }

    /// Removes a phone: this Mac stops trusting it and ends its sessions first, then the relay drops the
    /// grant. A grant the relay no longer has counts as removed.
    ///
    /// - Throws: The relay's failure, after showing it. The phone stays untrusted here.
    func revoke(_ phone: PairedPhone) async throws {
        guard !busy.contains(phone.grantID) else { return }
        busy.insert(phone.grantID)
        defer { busy.remove(phone.grantID) }
        await host.revoke(clientKey: phone.clientKey)
        let relay = relay
        do {
            try await ShellXLinkHostController.offMain { try relay.revokePhone(grantID: phone.grantID) }
        } catch let error as ShellXCoreError where error.code == "not_found" {
            // Already gone at the relay.
        } catch {
            let code = (error as? ShellXCoreError)?.code ?? "error"
            Self.log.notice("phone removal not sent to the relay: \(code, privacy: .public)")
            show(error)
            throw error
        }
        phones.removeAll { $0.grantID == phone.grantID }
        await refreshPhones()
    }

    // MARK: - Errors

    private func show(_ error: any Error, fromPoll: Bool = false) {
        errorText = Self.message(for: error)
        errorCameFromPoll = fromPoll
    }

    private func clearPollError() {
        guard errorCameFromPoll else { return }
        errorText = nil
        errorCameFromPoll = false
    }

    /// A short line for the sheet: "Can't reach relay.shellx.pro" offline, otherwise the code.
    nonisolated static func message(for error: any Error) -> String {
        let code = (error as? ShellXCoreError)?.code ?? ShellXLinkHostController.keyErrorKind(error)
        if code == "network" {
            return String(localized: "remote.signin.error.network", defaultValue: "Can't reach relay.shellx.pro")
        }
        return String(format: String(localized: "remote.phonePairing.error", defaultValue: "Something went wrong (%@)"),
                      code)
    }

    // MARK: - Names

    /// `name` as the phone's QR parser accepts it: control characters and bidi overrides and isolates
    /// (U+202A-U+202E, U+2066-U+2069) removed, trimmed, cut to 100 Unicode scalars on a character
    /// boundary; `fallback` when nothing is left.
    nonisolated static func offerName(_ name: String, fallback: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: name.unicodeScalars.filter { !isForbiddenInName($0) })
        let cleaned = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        var cut = ""
        var count = 0
        for character in cleaned {
            let size = character.unicodeScalars.count
            guard count + size <= maxNameScalars else { break }
            cut.append(character)
            count += size
        }
        let result = cut.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? fallback : result
    }

    /// A phone's name as this Mac shows it: the same cleaning, so a name cannot pose as other text.
    nonisolated static func displayName(_ name: String) -> String {
        offerName(name, fallback: String(localized: "terminalSharing.device.iphone", defaultValue: "iPhone"))
    }

    private nonisolated static let maxNameScalars = 100

    private nonisolated static func isForbiddenInName(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .control
            || (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
    }
}

extension ShellXPhonePairingCoordinator {
    /// The app's coordinator over this Mac's link host and shellx-core; nil when the app has no link host.
    static func forApp() -> ShellXPhonePairingCoordinator? {
        guard let host = ShellXRemoteService.shared.linkHost as? ShellXLinkHostController else { return nil }
        return ShellXPhonePairingCoordinator(host: host, relay: host.core)
    }
}
