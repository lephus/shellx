import Foundation
import Observation
import ShellXLinkCore
import ShellXLinkSession

/// One agent session's screen: its chat (the phone's copy at once, then the Mac's newest page,
/// older pages on demand, live entries while the screen is open), its pending items, sending and
/// Stop / Force stop.
///
/// The copy is written to the store at most `saveDelay` after its last change, and at once by
/// `close()` (the screen goes away). Writes use the store writer taken by `open()`, so nothing is
/// written after a sign-out wipe. Sending to an offline Mac answers at once and queues nothing
/// (spec section 7.5).
@MainActor @Observable
public final class AgentThreadModel {
    /// Entries asked for per `chat.history` call (the protocol's most).
    public static let pageSize = 50
    public static let saveDelay: Duration = .milliseconds(500)

    public let ref: SessionRef
    public private(set) var thread = ChatThread()
    /// The newest page is on its way.
    public private(set) var loading = false
    /// An older page is on its way.
    public private(set) var loadingOlder = false
    /// The Mac answered that it does not have this session (history, send or stop).
    private var answeredNotFound = false

    @ObservationIgnored private let hub: MachineHub
    @ObservationIgnored private let store: ConversationStore
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var writer: ConversationStore.Writer?
    @ObservationIgnored private var opening: Task<Void, Never>?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var writing: Task<Void, Never>?
    @ObservationIgnored private var changed = false
    @ObservationIgnored private var latestInFlight = 0
    @ObservationIgnored private var observers = 0
    /// `run()` ran before (and was cancelled when the screen was covered).
    @ObservationIgnored private var hasRun = false

    /// `sleep` waits out `saveDelay`; tests pass one they release by hand.
    public init(
        ref: SessionRef, hub: MachineHub, store: ConversationStore,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.ref = ref
        self.hub = hub
        self.store = store
        self.sleep = sleep
    }

    // MARK: - What the screen reads

    private var machine: MachineModel? { hub.machines.first { $0.id == ref.machineID } }

    /// The session's Mac has no live, synced link: calls answer at once without sending.
    public var offline: Bool { machine?.state != .online }

    /// The session as its Mac lists it (its last known state while the Mac is offline), or nil when
    /// the Mac does not list it.
    public var session: MachineSession? {
        guard let machine, let session = machine.sessions.session(ref.sessionId) else { return nil }
        return MachineSession(
            machineID: machine.id, machineName: machine.name, online: machine.state == .online, session: session)
    }

    /// The Mac's name, for "<Mac> is offline"; empty when the Mac is no longer paired.
    public var machineName: String { machine?.name ?? "" }

    /// The Mac no longer has this session: it said so, or its synced list leaves it out.
    public var sessionGone: Bool {
        if answeredNotFound { return true }
        guard let machine, machine.state == .online, machine.sessionsSupported else { return false }
        return machine.sessions.session(ref.sessionId) == nil
    }

    /// The pending requests of this session's workspace on its Mac, oldest first.
    public var pendingHere: [MachinePendingItem] {
        guard let workspaceId = session?.session.workspaceId else { return [] }
        return hub.pendingItems.filter { $0.machineID == ref.machineID && $0.item.workspaceId == workspaceId }
    }

    /// Stop applies: the Mac is online and the session works or waits for the user.
    public var canStop: Bool {
        guard let session, session.online else { return false }
        switch session.session.state {
        case .working, .needsInput: return true
        case .idle, .ended, .other: return false
        }
    }

    /// The Mac has older entries, but another page would push the newest out of the phone's
    /// `ChatThread.maxEntries`: they are only on the Mac.
    public var olderOnlyOnMac: Bool {
        thread.hasMore && thread.entries.count + Self.pageSize > ChatThread.maxEntries
    }

    /// Scrolling to the top can ask the Mac for older entries: it has some, the phone has room for
    /// them, and the session is still on the Mac (`not_found` ends paging).
    public var canLoadOlder: Bool {
        thread.hasMore && !olderOnlyOnMac && !sessionGone
    }

    /// True while `run()` follows the hub (tests).
    var isObserving: Bool { observers > 0 }

    // MARK: - History

    /// Shows the phone's copy, then asks the Mac for its newest page (none while it is offline: the
    /// page loads when it comes back, if `run()` is following). An empty page is a session with no
    /// messages yet (its live entries fill it); `not_found` is a session gone from the Mac. Takes
    /// the store writer for this screen. Runs once; later calls wait for it.
    public func open() async {
        if let opening { return await opening.value }
        let task = Task { await self.load() }
        opening = task
        await task.value
    }

    /// Asks for the page before the oldest entry here (`before_seq` = its `seq`) when
    /// `canLoadOlder`.
    public func loadOlder() async {
        guard !loadingOlder, !offline, canLoadOlder, let oldest = thread.entries.first?.seq else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let page = try await hub.chatHistory(ref, beforeSeq: oldest, limit: Self.pageSize)
            // The copy changed meanwhile (a newest page replaced it): this page may not join it.
            guard thread.entries.first?.seq == oldest else { return }
            change { $0.applyOlderPage(page.entries, hasMore: page.hasMore) }
        } catch {
            noteNotFound(error)
        }
    }

    /// Opens the screen and follows the hub until cancelled (or the hub stops): this session's live
    /// entries, and the newest page again each time its Mac's link comes back (entries pushed while
    /// it was down were missed). Subscribes before asking for history, so nothing falls between.
    /// Run again after a cancel (the screen was covered, then shown again), it reads the newest page
    /// again, for what came while nobody followed.
    public func run() async {
        let chat = hub.chatUpdates()
        let states = hub.stateUpdates()
        let again = hasRun
        hasRun = true
        observers += 1
        defer { observers -= 1 }
        async let live: Void = follow(chat)
        async let link: Void = follow(states)
        await open()
        if again { await loadLatest() }
        _ = await (live, link)
    }

    // MARK: - Send and stop

    /// Sends `text` to this session: refused on the phone when empty or too long; `.offline` at once
    /// when the Mac is not online. `viaVoice` is how the user said it (Task 9); the Mac gets the same
    /// text either way.
    public func send(_ text: String, viaVoice: Bool) async -> AgentSendResult {
        let validation = ComposerValidation(text)
        guard case let .ok(message) = validation else { return .refused(validation) }
        guard !offline else { return .offline }
        do {
            let outcome = try await hub.chatSend(ref, text: message)
            if outcome == .notFound { answeredNotFound = true }
            return .sent(outcome)
        } catch LinkCallError.offline {
            return .offline
        } catch {
            return .noAnswer
        }
    }

    /// Interrupts the session's current turn; `hard` is Force stop. Nil when nothing was sent (the
    /// Mac is offline) or no answer came.
    public func stop(hard: Bool) async -> ChatInterruptOutcome? {
        guard !offline else { return nil }
        do {
            let outcome = try await hub.chatInterrupt(ref, hard: hard)
            if outcome == .notFound { answeredNotFound = true }
            return outcome
        } catch {
            return nil
        }
    }

    /// The screen goes away: writes the copy now if it changed.
    public func close() async {
        await flush()
    }

    // MARK: - Private

    private func flush() async {
        pendingSave?.cancel()
        pendingSave = nil
        // One write at a time, in order, each with the copy as it is when it starts.
        let previous = writing
        let next = Task {
            await previous?.value
            await self.write()
        }
        writing = next
        await next.value
    }

    private func load() async {
        writer = await store.writer()
        if let cached = await store.load(.thread(ref), as: ChatThread.self) {
            // Entries pushed live before the copy was read are newer than it.
            var merged = cached
            merged.upsert(thread.entries)
            thread = merged
        }
        // Changes made before there was a writer were not saved yet.
        if changed { scheduleSave() }
        await loadLatest()
    }

    private func loadLatest() async {
        guard !offline else { return }
        latestInFlight += 1
        loading = true
        defer {
            latestInFlight -= 1
            loading = latestInFlight > 0
        }
        do {
            let page = try await hub.chatHistory(ref, beforeSeq: nil, limit: Self.pageSize)
            change { $0.applyLatestPage(page.entries, hasMore: page.hasMore) }
        } catch {
            noteNotFound(error)
        }
    }

    private func follow(_ updates: AsyncStream<(SessionRef, [ChatEntry])>) async {
        for await (ref, entries) in updates where ref == self.ref {
            change { $0.upsert(entries) }
        }
    }

    private func follow(_ updates: AsyncStream<(machineID: String, state: MachineLinkState)>) async {
        // `.online` comes once per new link, after its first sync.
        for await update in updates where update.machineID == ref.machineID && update.state == .online {
            // Before `open()` the first page is its job.
            guard opening != nil else { continue }
            await loadLatest()
        }
    }

    private func noteNotFound(_ error: any Error) {
        if case LinkClientError.remote(code: "not_found", message: _) = error { answeredNotFound = true }
    }

    /// Applies `body` to the copy; saves it when it changed.
    private func change(_ body: (inout ChatThread) -> Void) {
        let before = thread
        body(&thread)
        guard thread != before else { return }
        changed = true
        scheduleSave()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let sleep = self.sleep
        pendingSave = Task {
            do { try await sleep(Self.saveDelay) } catch { return }
            guard !Task.isCancelled else { return }
            await self.flush()
        }
    }

    private func write() async {
        guard changed, let writer else { return }
        changed = false
        await writer.save(thread, to: .thread(ref))
    }
}
