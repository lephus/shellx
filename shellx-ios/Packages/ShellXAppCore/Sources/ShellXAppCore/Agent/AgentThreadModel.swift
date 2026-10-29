import Foundation
import Observation
import ShellXLinkCore
import ShellXLinkSession

/// One agent session's screen: its chat (the phone's copy at once, then the Mac's newest page,
/// older pages on demand, live entries while the screen is open), its pending items, sending and
/// Stop / Force stop.
///
/// The copy is written to the store at most `saveDelay` after its last change, and at once by
/// `close()` (the screen goes away) or `save()` (the app leaves the foreground). Writes use the
/// store writer `open()` takes, which claims the thread: nothing is written after a sign-out wipe,
/// nor after a later screen of the same session claimed it. Sending to an offline Mac answers at
/// once and queues nothing (spec section 7.5).
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
    /// `open()` read the phone's copy.
    private var cacheRead = false
    /// A newest page came since `open()`.
    private var latestLoaded = false
    /// The last newest page failed with an error from the Mac.
    private var latestFailed = false
    /// The last older page failed.
    private var olderFailed = false
    @ObservationIgnored private let upload = UploadProgress()

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
    /// The screen went away (`close()`) and is not shown again yet: late answers change the copy in
    /// memory only, nothing is saved or asked for.
    @ObservationIgnored private var closed = false
    /// Counts the Mac's transcript resets (`chat.reset`): a history answer asked for under an older
    /// count belongs to the old transcript and is dropped.
    @ObservationIgnored private var transcript = 0
    /// A reset came before `open()` took the writer: the stored copy is the old transcript's.
    @ObservationIgnored private var storedCopyIsStale = false
    /// The hub's count of this session's transcript resets (`MachineHub.transcriptResets(of:)`) that
    /// this model has dealt with: set when it starts following, raised by each reset it reads. A
    /// higher count when it follows again is a reset it missed while covered or closed.
    @ObservationIgnored private var resetsSeen: Int

    /// `sleep` waits out `saveDelay`; tests pass one they release by hand.
    public init(
        ref: SessionRef, hub: MachineHub, store: ConversationStore,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.ref = ref
        self.hub = hub
        self.store = store
        self.sleep = sleep
        // Resets before the screen existed: `ChatCopySweeper` already dropped their stored copy.
        resetsSeen = hub.transcriptResets(of: ref)
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
        return hub.pendingItems.filter { $0.isIn(machineID: ref.machineID, workspaceId: workspaceId) }
    }

    /// Stop applies: the Mac is online, the session works or waits for the user, and the Mac did
    /// not say the session is gone.
    public var canStop: Bool {
        guard !answeredNotFound, let session, session.online else { return false }
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

    /// What an empty chat says.
    public enum EmptyState: Equatable, Sendable {
        /// The phone's copy or the Mac's first page is on its way (or the Mac is still connecting).
        case loading
        /// The Mac's first page came, and it was empty. Live entries fill it as the agent writes.
        case noMessages
        /// The Mac is offline and the phone has no copy.
        case offline
        /// The first page did not come (the Mac answered an error): retry.
        case failed
        /// The Mac no longer has this session.
        case gone
    }

    /// What the top of the chat shows about older entries.
    public enum Older: Equatable, Sendable {
        /// Nothing: no older entries, or none can be asked for now (the Mac is offline).
        case none
        /// Scrolling to the top asks for them.
        case loadable
        /// The last try failed: a row to try again (never a spinner that asks by itself).
        case failed
        /// The phone keeps no more; they are on the Mac.
        case onlyOnMac
    }

    /// Nil when the chat has entries.
    public var emptyState: EmptyState? {
        guard thread.entries.isEmpty else { return nil }
        if sessionGone { return .gone }
        if latestLoaded { return .noMessages }
        if !cacheRead || loading { return .loading }
        if offline {
            switch machine?.state {
            case .connecting?, .reconnecting?: return .loading
            default: return .offline
            }
        }
        return latestFailed ? .failed : .loading
    }

    public var older: Older {
        guard !thread.entries.isEmpty, thread.hasMore, !sessionGone else { return .none }
        if olderOnlyOnMac { return .onlyOnMac }
        if offline { return .none }
        return olderFailed ? .failed : .loadable
    }

    /// Asks the Mac for its newest page again (after `EmptyState.failed`).
    public func retry() async {
        await loadLatest()
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
    /// `canLoadOlder`. A failure shows as `Older.failed`; calling again retries.
    public func loadOlder() async {
        guard !loadingOlder, !offline, canLoadOlder, let oldest = thread.entries.first?.seq else { return }
        loadingOlder = true
        olderFailed = false
        defer { loadingOlder = false }
        let asked = transcript
        do {
            let page = try await hub.chatHistory(ref, beforeSeq: oldest, limit: Self.pageSize)
            // Asked before a transcript reset, or the copy changed meanwhile (a newest page replaced
            // it): this page may not join it.
            guard asked == transcript, thread.entries.first?.seq == oldest else { return }
            change { $0.applyOlderPage(page.entries, hasMore: page.hasMore) }
        } catch is CancellationError {
            return
        } catch {
            guard asked == transcript else { return }
            if !noteNotFound(error) { olderFailed = true }
        }
    }

    /// Opens the screen and follows the hub until cancelled (or the hub stops): this session's live
    /// entries, and the newest page again each time its Mac's link comes back (entries pushed while
    /// it was down were missed). Subscribes before asking for history, so nothing falls between.
    /// Run again after a cancel (the screen was covered, then shown again), it reads the newest page
    /// again, for what came while nobody followed; when the transcript was reset meanwhile, the copy
    /// is dropped first, so the new transcript replaces it instead of merging into it (PROTOCOL.md
    /// section 4, ruling P3-R7). Cancelled before that, it asks for nothing.
    public func run() async {
        closed = false
        // Every way of opening an agent runs this: it no longer counts as just finished.
        hub.markSeen(ref)
        // Subscribing and reading the hub's reset count happen in one main-actor step: every reset
        // is either counted here or delivered to `chat`.
        let chat = hub.chatUpdates()
        let states = hub.stateUpdates()
        let resets = hub.transcriptResets(of: ref)
        if resets != resetsSeen {
            resetsSeen = resets
            voidCopy()
        }
        let again = hasRun
        hasRun = true
        observers += 1
        defer { observers -= 1 }
        async let live: Void = follow(chat)
        async let link: Void = follow(states)
        await open()
        if again, !Task.isCancelled, !closed {
            // Saves skipped while the screen was away are written now.
            if changed { scheduleSave() }
            await loadLatest()
        }
        _ = await (live, link)
    }

    // MARK: - Send and stop

    /// How far the attachments of the message being sent got (bytes sent over bytes to send); nil
    /// while none go up.
    public var uploadProgress: Double? { upload.fraction }

    /// Sends `text` with `attachments` to this session: refused on the phone when there is nothing
    /// to send, the text is too long, or the attachments are too many or one is too big; `.offline`
    /// at once when the Mac is not online. The attachments go up first, then the message names them
    /// (`MachineHub.chatSend(_:text:attachments:progress:)`); `.notSent` when they surely did not
    /// reach the session, `.attachmentsUnsupported` when the Mac no longer takes them. `viaVoice` is
    /// how the user said it (Task 9); the Mac gets the same text either way.
    public func send(_ text: String, attachments: [OutgoingAttachment] = [], viaVoice: Bool) async -> AgentSendResult {
        let validation = ComposerValidation.message(text, attachments: attachments)
        guard case let .ok(message) = validation else { return .refused(validation) }
        guard !offline else { return .offline }
        do {
            let outcome: ChatSendOutcome
            if attachments.isEmpty {
                outcome = try await hub.chatSend(ref, text: message)
            } else {
                let hub = self.hub
                let ref = self.ref
                outcome = try await upload.track { progress in
                    try await hub.chatSend(ref, text: message, attachments: attachments, progress: progress)
                }
            }
            if outcome == .notFound { answeredNotFound = true }
            return .sent(outcome)
        } catch LinkCallError.offline, LinkCallError.needsPairing {
            return .offline
        } catch AttachmentSendError.refused(code: "unsupported") {
            return .attachmentsUnsupported
        } catch is AttachmentSendError {
            return .notSent
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

    /// The screen goes away: writes the copy now if it changed. Until `run()` shows it again,
    /// answers still on their way change the copy in memory only: nothing is saved. If the same
    /// session's screen was opened again meanwhile, its writer won and this write is dropped.
    public func close() async {
        closed = true
        await flush()
    }

    /// Writes the copy now if it changed (the app leaves the foreground).
    public func save() async {
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
        // This screen's writer claims the thread: a screen for the same session opened later wins.
        writer = await store.writer(claiming: .thread(ref))
        if storedCopyIsStale {
            // A reset came before there was a writer: the stored copy is the old transcript's.
            storedCopyIsStale = false
            removeStoredCopy()
        } else {
            let asked = transcript
            // A reset while reading: the copy read is the old transcript's (its removal is queued).
            if let cached = await store.load(.thread(ref), as: ChatThread.self), asked == transcript {
                // Entries pushed live before the copy was read are newer than it.
                var merged = cached
                merged.upsert(thread.entries)
                thread = merged
            }
        }
        cacheRead = true
        // Changes made before there was a writer were not saved yet.
        if changed { scheduleSave() }
        // Closed while reading the copy: the screen is gone, ask for nothing.
        guard !closed else { return }
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
        let asked = transcript
        do {
            let page = try await hub.chatHistory(ref, beforeSeq: nil, limit: Self.pageSize)
            // The answer to a call sent before a transcript reset is the old transcript's: drop it
            // (PROTOCOL.md section 4, `chat.reset`).
            guard asked == transcript else { return }
            latestLoaded = true
            latestFailed = false
            change { $0.applyLatestPage(page.entries, hasMore: page.hasMore) }
        } catch is CancellationError {
            return
        } catch LinkCallError.offline, LinkCallError.needsPairing {
            // The Mac went offline meanwhile (the page loads when it is back), or must be paired again.
            return
        } catch {
            guard asked == transcript else { return }
            if !noteNotFound(error) { latestFailed = true }
        }
    }

    private func follow(_ updates: AsyncStream<ChatUpdate>) async {
        for await update in updates where update.ref == ref {
            switch update {
            case let .upsert(_, entries):
                change { $0.upsert(entries) }
            case .reset:
                resetsSeen += 1
                await transcriptReset()
            }
        }
    }

    /// The Mac replaced the session's transcript: drops the copy (`voidCopy()`), then pages again
    /// from the newest; entries pushed after the reset upsert as usual.
    private func transcriptReset() async {
        voidCopy()
        // Before `open()` (or while it reads the copy), its own newest page comes after the reset.
        guard cacheRead, !closed else { return }
        await loadLatest()
    }

    /// Every entry held for the session, its `seq` values and any history answer still on its way
    /// belong to a transcript the Mac replaced: drops the copy in memory and on disk.
    private func voidCopy() {
        transcript += 1
        thread = ChatThread()
        latestLoaded = false
        latestFailed = false
        olderFailed = false
        // The Mac reset this session's transcript: it has the session.
        answeredNotFound = false
        // At once, not after `saveDelay`: a relaunch must not show the old transcript.
        removeStoredCopy()
    }

    /// Drops the stored copy through this screen's writer, after any write already under way; a
    /// save still waiting is cancelled.
    private func removeStoredCopy() {
        pendingSave?.cancel()
        pendingSave = nil
        changed = false
        guard let writer else {
            storedCopyIsStale = true
            return
        }
        let ref = self.ref
        let previous = writing
        writing = Task {
            await previous?.value
            await writer.remove(.thread(ref))
        }
    }

    private func follow(_ updates: AsyncStream<(machineID: String, state: MachineLinkState)>) async {
        // `.online` comes once per new link, after its first sync.
        for await update in updates where update.machineID == ref.machineID && update.state == .online {
            // Before `open()` the first page is its job; a closed screen asks for nothing.
            guard opening != nil, !closed else { continue }
            await loadLatest()
        }
    }

    /// Records a `not_found` answer (the session is gone); returns whether it was one.
    @discardableResult
    private func noteNotFound(_ error: any Error) -> Bool {
        guard case LinkClientError.remote(code: "not_found", message: _) = error else { return false }
        answeredNotFound = true
        return true
    }

    /// Applies `body` to the copy; saves it when it changed (unless the screen is closed).
    private func change(_ body: (inout ChatThread) -> Void) {
        let before = thread
        body(&thread)
        guard thread != before else { return }
        changed = true
        scheduleSave()
    }

    private func scheduleSave() {
        guard !closed else { return }
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
