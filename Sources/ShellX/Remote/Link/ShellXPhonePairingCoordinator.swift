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
/// * **Allow:** one approval at a time, and only while this Mac still serves the link (account, machine,
///   link slot) of the offer the phone answered. The phone is trusted here first, then `phones.approve`
///   grants it, then the trust is written again with a fresh time so a grants check that read the relay in
///   between cannot leave it dropped. A failed approval takes the trust back. An approval spends the QR:
///   the other requests for it are refused and a new QR shows.
/// * **Remove:** this Mac drops the phone first (the running host also ends its sessions; with no host
///   running, the last link's key store), then `phones.revoke`. A relay failure shows an error; the phone
///   stays untrusted here (fail closed).
/// * **Errors** clear on the next success of the same kind (polling, the phone list, Allow, Remove).
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
    /// True while not ready because no account is signed in: the sheet then says where to sign in.
    @Published private(set) var needsSignIn = false
    /// Pairing ids and grant ids with a decision or removal in flight.
    @Published private(set) var busy: Set<String> = []
    /// The pairing id being allowed. Only one at a time, so one QR never pairs two phones.
    @Published private(set) var approvingID: String?

    /// Requests refused because their proof did not match the current offer.
    private(set) var proofMismatches = 0

    private let host: any PhonePairingHosting
    private let relay: any PhonePairingCalling
    private let pollInterval: Duration
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private let fallbackName: String
    private let isSignedIn: @MainActor () -> Bool

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
    /// The link each shown candidate's offer was made for; Allow trusts only where that link is served.
    private var answeredHost: [String: PhonePairingHost] = [:]
    /// The link host last seen running. With no host running now, Remove untrusts through its key store.
    private var lastHost: PhonePairingHost?
    private enum ErrorKind { case poll, phones, approve, revoke }
    /// What produced `errorText`; the next success of the same kind clears it.
    private var errorKind: ErrorKind?

    /// - Parameters:
    ///   - host: The link host (``ShellXLinkHostController`` in the app).
    ///   - relay: The `phones.*` calls (shellx-core in the app).
    ///   - pollInterval: How often `phones.pending` is read while open.
    ///   - now: The clock offers age by.
    ///   - sleep: Waits between rounds; tests drive it by hand.
    ///   - fallbackName: The machine name the QR carries when this Mac's own name has nothing usable.
    ///   - isSignedIn: Whether a ShellX account is signed in on this Mac.
    init(host: any PhonePairingHosting,
         relay: any PhonePairingCalling,
         pollInterval: Duration = .seconds(ShellXRemoteService.pollInterval),
         now: @escaping @Sendable () -> Date = { Date() },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         fallbackName: String = String(localized: "terminalSharing.device.mac", defaultValue: "Mac"),
         isSignedIn: @escaping @MainActor () -> Bool = { true }) {
        self.host = host
        self.relay = relay
        self.pollInterval = pollInterval
        self.now = now
        self.sleep = sleep
        self.fallbackName = fallbackName
        self.isSignedIn = isSignedIn
    }

    // MARK: - Open and close

    /// Starts a pairing session: makes an offer and reads requests every `pollInterval` until `close()`.
    func open() {
        guard !isOpen else { return }
        isOpen = true
        generation += 1
        errorText = nil
        errorKind = nil
        isReady = host.pairingHost != nil
        needsSignIn = !isReady && !isSignedIn()
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
            await becomeNotReady()
            return
        }
        if let lastHost, !current.servesSameLink(as: lastHost) {
            // Another account or machine: the list on screen belonged to the old link.
            phones = []
            phonesListed = false
        }
        lastHost = current
        if !isReady { isReady = true }
        if needsSignIn { needsSignIn = false }
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

    private func becomeNotReady() async {
        if isReady { isReady = false }
        let signedOut = !isSignedIn()
        if needsSignIn != signedOut { needsSignIn = signedOut }
        let waiting = retireOffer()
        candidates = []
        await refuse(waiting)
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
            show(error, as: .poll)
            return
        }
        guard isOpen, generation == session else { return }
        let made = PairingOffer.make(machineID: current.machineID, linkSlot: current.linkSlot, hostKey: hostKey,
                                     machineName: Self.offerName(current.machineName, fallback: fallbackName))
        // The phone parses the QR strictly; never show one it would refuse.
        guard (try? PairingOffer(uri: made.uri)) == made else {
            Self.log.error("pairing offer not made: the machine id or link slot does not fit the QR")
            show(ShellXCoreError(code: "offer_unusable", message: "the pairing offer does not fit the QR format"),
                 as: .poll)
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
        let waiting = candidates.map(\.id).filter { $0 != approvingID }
        let kept = candidates.filter { $0.id == approvingID }
        if kept != candidates { candidates = kept }
        handled.formUnion(waiting)
        for id in waiting { answeredHost[id] = nil }
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
            show(error, as: .poll)
            return
        }
        // A closed sheet, a new offer or a newer read makes this answer stale.
        guard isOpen, generation == session, self.offer == offer, let answered = offerHost, read > appliedRead
        else { return }
        appliedRead = read
        clearError(.poll)
        var next: [Candidate] = []
        var mismatched: [String] = []
        // The request being allowed answered an earlier check; judging it against a newer offer would
        // refuse it while its approval is in flight.
        for request in requests where !handled.contains(request.id) && request.id != approvingID {
            if offer.verify(proof: request.proof, clientKey: request.clientKey) {
                next.append(Candidate(id: request.id, deviceName: request.deviceName, platform: request.platform,
                                      clientKey: request.clientKey))
                if answeredHost[request.id] == nil { answeredHost[request.id] = answered }
            } else {
                mismatched.append(request.id)
            }
        }
        // One being allowed stays on screen until its approval finishes, even once the relay stops listing it.
        if let approvingID, let candidate = candidates.first(where: { $0.id == approvingID }) {
            next.append(candidate)
        }
        let shown = Set(next.map(\.id))
        answeredHost = answeredHost.filter { shown.contains($0.key) }
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

    /// Allows a candidate: trusts its key on this Mac, has the relay grant it, then writes the trust again
    /// with a fresh time. A failed grant takes the trust back (a phone that was already paired keeps its
    /// earlier trust). Success spends the QR. One approval runs at a time.
    ///
    /// - Parameter id: A candidate's pairing id. One not shown yet is looked for in a fresh round first.
    /// - Throws: ``ShellXCoreError``: `approval_in_progress` while another approval runs, `not_a_candidate`
    ///   when no request with that id answered the QR on screen, `link_not_running` / `link_changed` when
    ///   this Mac no longer serves the link that QR offered (the sheet then shows the not-ready state), or
    ///   the trust or relay failure.
    func approve(_ id: String) async throws {
        try refuseWhileApproving()
        if !candidates.contains(where: { $0.id == id }) { await pollNow() }
        // The round awaited: another approval may have started meanwhile.
        try refuseWhileApproving()
        guard isOpen, let candidate = candidates.first(where: { $0.id == id }), let answered = answeredHost[id] else {
            throw ShellXCoreError(code: "not_a_candidate",
                                  message: "no pairing request with that id answered the QR on screen")
        }
        // Trust goes only where the offer the phone answered is served: same account, machine and slot.
        guard let current = host.pairingHost, current.servesSameLink(as: answered) else {
            let error = host.pairingHost == nil
                ? ShellXCoreError(code: "link_not_running", message: "this Mac is not serving ShellX Link")
                : ShellXCoreError(code: "link_changed", message: "this Mac's ShellX Link changed since the QR was shown")
            Self.log.notice("pairing not allowed: \(error.code, privacy: .public)")
            await becomeNotReady()
            show(error, as: .approve)
            throw error
        }
        approvingID = id
        busy.insert(id)
        do {
            try await allow(candidate, answered: answered, keys: current.keys)
        } catch {
            approvingID = nil
            busy.remove(id)
            throw error
        }
        // Handled before the approval ends, so no read can judge it against a newer offer.
        handled.insert(id)
        candidates.removeAll { $0.id == id }
        answeredHost[id] = nil
        approvingID = nil
        busy.remove(id)
        Self.log.info("paired a phone")
        // One QR, one phone: the QR that paired this one is spent.
        let waiting = retireOffer()
        await refuse(waiting)
        await pollNow()
        await refreshPhones()
    }

    private func refuseWhileApproving() throws {
        guard approvingID == nil else {
            throw ShellXCoreError(code: "approval_in_progress", message: "another phone is being allowed")
        }
    }

    /// Trust, grant, trust again; rolls the first write back when the grant fails.
    private func allow(_ candidate: Candidate, answered: PhonePairingHost, keys: ShellXLinkKeyStore) async throws {
        let relay = relay, id = candidate.id
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
            show(error, as: .approve)
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
            show(error, as: .approve)
            throw error
        }
        clearError(.approve)
        // A grants check whose snapshot fell between the first write and the grant drops the phone (its
        // time is older than the snapshot). Writing it again now puts it back and keeps it past that check.
        let confirmed = TrustedPhone(key: phone.key, deviceID: id, name: phone.name, pairedAt: now())
        let target = host.pairingHost.flatMap { $0.servesSameLink(as: answered) ? $0.keys : nil } ?? keys
        do {
            try await ShellXLinkHostController.offMain { try target.trust(confirmed) }
        } catch {
            Self.log.error("paired phone not saved again: \(ShellXLinkHostController.keyErrorKind(error), privacy: .public)")
            show(error, as: .approve)
        }
    }

    /// Refuses a candidate. A relay failure is left to the request's expiry.
    func deny(_ id: String) async {
        guard id != approvingID else { return }
        handled.insert(id)
        candidates.removeAll { $0.id == id }
        answeredHost[id] = nil
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
            clearError(.phones)
        } catch {
            show(error, as: .phones)
        }
    }

    /// Removes a phone. This Mac stops trusting it first: the running host untrusts it and ends its
    /// sessions; with no host running, the key store of the last link seen untrusts it. Then the relay
    /// drops the grant. A grant the relay no longer has counts as removed.
    ///
    /// - Throws: ``ShellXCoreError`` `link_not_running`, before any relay call, when no key store of this
    ///   Mac is reachable; otherwise the relay's failure, after showing it. The phone stays untrusted here.
    func revoke(_ phone: PairedPhone) async throws {
        guard !busy.contains(phone.grantID) else { return }
        let running = host.pairingHost
        guard let local = running ?? lastHost else {
            let error = ShellXCoreError(code: "link_not_running",
                                        message: "this Mac has no ShellX Link key store to remove the phone from")
            show(error, as: .revoke)
            throw error
        }
        busy.insert(phone.grantID)
        defer { busy.remove(phone.grantID) }
        if running != nil {
            await host.revoke(clientKey: phone.clientKey)
        } else {
            let keys = local.keys, key = phone.clientKey
            do {
                try await ShellXLinkHostController.offMain { try keys.untrust(key: key) }
            } catch {
                // The relay revoke below and the next grants check still take it away.
                Self.log.error("phone removal not saved here: \(ShellXLinkHostController.keyErrorKind(error), privacy: .public)")
            }
        }
        let relay = relay
        do {
            try await ShellXLinkHostController.offMain { try relay.revokePhone(grantID: phone.grantID) }
        } catch let error as ShellXCoreError where error.code == "not_found" {
            // Already gone at the relay.
        } catch {
            let code = (error as? ShellXCoreError)?.code ?? "error"
            Self.log.notice("phone removal not sent to the relay: \(code, privacy: .public)")
            show(error, as: .revoke)
            throw error
        }
        clearError(.revoke)
        phones.removeAll { $0.grantID == phone.grantID }
        await refreshPhones()
    }

    // MARK: - Errors

    private func show(_ error: any Error, as kind: ErrorKind) {
        errorText = Self.message(for: error)
        errorKind = kind
    }

    /// Clears the shown error when it came from `kind`.
    private func clearError(_ kind: ErrorKind) {
        guard errorKind == kind else { return }
        errorText = nil
        errorKind = nil
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
    /// Signed in means Settings › Account shows an account, or the remote service runs a session.
    static func forApp() -> ShellXPhonePairingCoordinator? {
        guard let host = ShellXRemoteService.shared.linkHost as? ShellXLinkHostController else { return nil }
        return ShellXPhonePairingCoordinator(host: host, relay: host.core, isSignedIn: {
            ShellXRemoteService.shared.isSignedIn || ShellXAccountFlow.shared.currentIdentity != nil
        })
    }
}
