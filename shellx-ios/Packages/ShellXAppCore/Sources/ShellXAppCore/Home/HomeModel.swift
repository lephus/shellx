import Foundation
import Observation
import ShellXLinkCore

/// The home conversation, "ShellX" (plan decision D7): what the user said or typed, and ShellX's
/// canned notes about it, kept on the phone; which running session the composer sends to; and the
/// live sessions' status rows.
///
/// `submit(_:viaVoice:)` sends to one running session and notes the outcome. `run()` watches the hub
/// and notes each session that finishes a turn, with the first line of its final reply: it waits
/// `finishSettle`, reads the history, and keeps the note up to date for `finishFollow` (the Mac may
/// report idle before its transcript has the reply). Every change is written to the store at most
/// `saveDelay` after the last one, and at once by `flush()` (the app calls it when it goes to the
/// background). Writes use the store writer of the account that loaded the model, so nothing is
/// written after a sign-out wipe.
@MainActor @Observable
public final class HomeModel {
    /// The most entries kept; the oldest go first.
    public static let maxEntries = 2000
    public static let saveDelay: Duration = .milliseconds(500)
    /// How long a finished session waits before its note is written.
    public static let finishSettle: Duration = .milliseconds(1500)
    /// How long a finish note follows its session: a newer agent reply in that time, while the
    /// session stays idle, replaces the note's summary.
    public static let finishFollow: Duration = .seconds(10)
    /// The longest summary in an `agentFinished` note, in characters.
    static let summaryLength = 140

    public private(set) var entries: [HomeEntry] = []
    /// The session the user picked in the composer; nil leaves it to `effectiveTarget`.
    public var target: SessionRef?
    /// True once `load()` read the stored timeline.
    public private(set) var isLoaded = false
    /// The session the last message went to.
    private var lastUsed: SessionRef?

    /// An agent reply: its first line, and where it stands in the transcript.
    private struct AgentLine {
        var seq: Int
        var rev: Int
        var line: String?
    }

    /// A finish note still following its session, and the reply it quotes (`Int.min` for none).
    private struct FinishFollow {
        var entryID: String
        var seq: Int
        var rev: Int
        var timer: Task<Void, Never>
    }

    @ObservationIgnored private let hub: MachineHub
    @ObservationIgnored private let store: ConversationStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let finishSettleDelay: Duration
    @ObservationIgnored private var writer: ConversationStore.Writer?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var writing: Task<Void, Never>?
    @ObservationIgnored private var homeChanged = false
    @ObservationIgnored private var sessionsChanged = false
    @ObservationIgnored private var detector = SessionFinishDetector()
    /// The newest agent reply seen live per session, not yet used by a finish note.
    @ObservationIgnored private var lastAgentLines: [SessionRef: AgentLine] = [:]
    /// Finishes waiting out the settle delay or reading the history.
    @ObservationIgnored private var finishing: [SessionRef: Task<Void, Never>] = [:]
    @ObservationIgnored private var follows: [SessionRef: FinishFollow] = [:]
    @ObservationIgnored private var observers = 0

    /// `sleep` waits out `saveDelay`, `finishSettle` and `finishFollow`; tests pass one they release
    /// by hand. `finishSettle` zero writes a finish note without waiting.
    public init(
        hub: MachineHub, store: ConversationStore, now: @escaping () -> Date,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        finishSettle: Duration = HomeModel.finishSettle
    ) {
        self.hub = hub
        self.store = store
        self.now = now
        self.sleep = sleep
        finishSettleDelay = finishSettle
    }

    // MARK: - What the screen reads

    /// Where the next message goes: the session the user picked while it is still listed (its Mac
    /// may be offline: sending then notes that), otherwise `preferredTarget`.
    public var effectiveTarget: SessionRef? {
        let live = hub.liveSessions
        if let target, let picked = live.first(where: { $0.ref == target }) { return picked.ref }
        return live.preferredTarget(lastUsed: lastUsed, defaultMachineID: hub.defaultMachineID)
    }

    /// The live sessions as status rows, needs-you first.
    public var statusRows: [AgentStatusRow] {
        AgentStatusRow.rows(hub.liveSessions, now: now())
    }

    /// True while `run()` watches the hub, after its first look at every online Mac.
    var isObserving: Bool { observers > 0 }

    /// The first line of the last agent reply seen live for `ref` and not used by a note (tests).
    func lastAgentLine(for ref: SessionRef) -> String? {
        lastAgentLines[ref]?.line
    }

    /// Whether a finish note still follows `ref` (tests).
    func isFollowingFinish(of ref: SessionRef) -> Bool {
        follows[ref] != nil
    }

    // MARK: - Lifecycle

    /// Reads the stored timeline, the session last messaged and the last seen session states, and
    /// takes the store writer for this account. Runs once; later calls wait for it.
    public func load() async {
        if let loading { return await loading.value }
        let task = Task { await self.readStore() }
        loading = task
        await task.value
    }

    /// Watches the hub until cancelled (or the hub stops): notes each session that finishes a turn,
    /// and remembers each session's last agent reply for that note.
    public func run() async {
        await load()
        let sessionUpdates = hub.sessionUpdates()
        let chatUpdates = hub.chatUpdates()
        // Forget unpaired Macs, but not when the hub has none: its list may simply be unreadable.
        if hub.isLoaded, !hub.machines.isEmpty {
            changeDetector { $0.retain(machineIDs: Set(hub.machines.map(\.id))) }
        }
        // Lists that arrived before this subscription. Only a synced (online) Mac's list counts: a
        // Mac still connecting has an empty one, which would hide what finished meanwhile.
        for machine in hub.machines where machine.state == .online {
            sessionsArrived(machineID: machine.id, sessions: machine.sessions.sessions)
        }
        observers += 1
        defer {
            observers -= 1
            if observers == 0 { stopAllFinishes() }
        }
        async let chat: Void = watch(chatUpdates)
        async let sessions: Void = watch(sessionUpdates)
        _ = await (chat, sessions)
    }

    private func watch(_ updates: AsyncStream<ChatUpdate>) async {
        for await update in updates {
            switch update {
            case let .upsert(ref, entries):
                remember(entries, of: ref)
            case let .reset(ref):
                // The old transcript's lines and seq values are void: no note quotes them, and a
                // note still following the session stops (its seq marks no longer compare).
                lastAgentLines[ref] = nil
                stopFollowing(ref)
            }
        }
    }

    private func watch(_ updates: AsyncStream<(machineID: String, sessions: [AgentSession])>) async {
        for await update in updates {
            sessionsArrived(machineID: update.machineID, sessions: update.sessions)
        }
    }

    // MARK: - Sending

    /// Sends `text` to `effectiveTarget` and notes what happened (D7, spec section 7.5):
    /// - empty: nothing; too long: nothing is sent or noted, the result says so;
    /// - otherwise the message is added, then one note: no target (the default Mac offline, or no
    ///   running session), the target's Mac offline (nothing sent or queued), or the Mac's answer.
    /// The target becomes the session last messaged.
    public func submit(_ text: String, viaVoice: Bool) async -> ComposerValidation {
        let validation = ComposerValidation(text)
        guard case let .ok(message) = validation else { return validation }
        let target = effectiveTarget
        append(.userSaid(text: message, target: target, viaVoice: viaVoice))
        guard let target else {
            append(.note(noTargetNote()))
            return validation
        }
        lastUsed = target
        guard let machine = hub.machines.first(where: { $0.id == target.machineID }) else {
            append(.note(.sendFailed(target, .notFound)))
            return validation
        }
        guard machine.state == .online else {
            append(.note(.machineOffline(machineName: machine.name)))
            return validation
        }
        let note: HomeNote
        do {
            note = HomeNote(sendOutcome: try await hub.chatSend(target, text: message), to: target)
        } catch {
            note = HomeNote(sendError: error, to: target)
        }
        append(.note(note))
        return validation
    }

    /// Writes every pending change now.
    public func flush() async {
        pendingSave?.cancel()
        pendingSave = nil
        // One write at a time, in order, each with the state as it is when it starts.
        let previous = writing
        let next = Task {
            await previous?.value
            await self.write()
        }
        writing = next
        await next.value
    }

    // MARK: - Private

    private func readStore() async {
        writer = await store.writer()
        if let saved = await store.load(.home, as: HomeDocument.self) {
            entries = Self.capped(saved.entries + entries)
            if lastUsed == nil { lastUsed = saved.lastUsed }
        }
        if let saved = await store.load(.lastSessions, as: SessionFinishDetector.self) {
            detector = saved
        }
        isLoaded = true
        // Changes made before there was a writer were not saved yet.
        if homeChanged || sessionsChanged { scheduleSave() }
    }

    private func noTargetNote() -> HomeNote {
        if let id = hub.defaultMachineID, let machine = hub.machines.first(where: { $0.id == id }),
            machine.state != .online
        {
            return .machineOffline(machineName: machine.name)
        }
        return .noLiveSession
    }

    /// Adds an entry; returns its id.
    @discardableResult
    private func append(_ content: HomeEntry.Content) -> String {
        let id = UUID().uuidString
        entries.append(HomeEntry(id: id, at: now(), content: content))
        entries = Self.capped(entries)
        homeChanged = true
        scheduleSave()
        return id
    }

    private func sessionsArrived(machineID: String, sessions: [AgentSession]) {
        var finished: [SessionRef] = []
        changeDetector { finished = $0.observe(machineID: machineID, sessions: sessions) }
        let listed = Set(sessions.map(\.sessionId))
        let idle = Set(sessions.filter { $0.state == .idle }.map(\.sessionId))
        lastAgentLines = lastAgentLines.filter { $0.key.machineID != machineID || listed.contains($0.key.sessionId) }
        // A note follows its session only while the session stays idle.
        for ref in follows.keys where ref.machineID == machineID && !idle.contains(ref.sessionId) {
            stopFollowing(ref)
        }
        for ref in finished { startFinish(ref) }
    }

    // MARK: - Finished sessions

    /// Notes a finished session after `finishSettle`: the Mac may report idle before its transcript
    /// has the final reply (the state comes from hooks, the reply from the transcript).
    private func startFinish(_ ref: SessionRef) {
        stopFollowing(ref)
        finishing[ref]?.cancel()
        let settle = finishSettleDelay
        let sleep = self.sleep
        finishing[ref] = Task {
            if settle > .zero {
                do { try await sleep(settle) } catch { return }
            }
            guard !Task.isCancelled else { return }
            await self.noteFinish(ref)
        }
    }

    /// The note quotes the newest agent prose, by `(seq, rev)`, of the session's last ten history
    /// entries and of what was seen live; the live reply alone when the history cannot be read. Then
    /// the note follows the session for `finishFollow`.
    private func noteFinish(_ ref: SessionRef) async {
        var newest: AgentLine?
        if let page = try? await hub.chatHistory(ref, beforeSeq: nil, limit: 10) {
            newest = Self.newestAgentLine(page.entries)
        }
        guard !Task.isCancelled else { return }
        // A reply seen live serves this finish only.
        if let live = lastAgentLines.removeValue(forKey: ref), newest.map({ Self.isNewer(live, than: $0) }) ?? true {
            newest = live
        }
        let id = append(.note(.agentFinished(ref, summary: newest?.line)))
        follow(ref, note: id, quoting: newest)
    }

    /// For `finishFollow`, a newer agent reply of `ref` while it stays idle replaces the note's
    /// summary in place.
    private func follow(_ ref: SessionRef, note entryID: String, quoting line: AgentLine?) {
        stopFollowing(ref)
        let sleep = self.sleep
        let timer = Task {
            do { try await sleep(Self.finishFollow) } catch { return }
            guard !Task.isCancelled, self.follows[ref]?.entryID == entryID else { return }
            self.follows[ref] = nil
        }
        follows[ref] = FinishFollow(entryID: entryID, seq: line?.seq ?? .min, rev: line?.rev ?? .min, timer: timer)
    }

    private func stopFollowing(_ ref: SessionRef) {
        follows.removeValue(forKey: ref)?.timer.cancel()
    }

    /// Replaces a followed note's summary with `line`, a newer reply.
    private func update(_ follow: FinishFollow, of ref: SessionRef, with line: AgentLine) {
        guard let index = entries.lastIndex(where: { $0.id == follow.entryID }) else {
            stopFollowing(ref)
            return
        }
        entries[index].content = .note(.agentFinished(ref, summary: line.line))
        follows[ref]?.seq = line.seq
        follows[ref]?.rev = line.rev
        homeChanged = true
        scheduleSave()
    }

    private func isIdle(_ ref: SessionRef) -> Bool {
        hub.machines.first { $0.id == ref.machineID }?.sessions.session(ref.sessionId)?.state == .idle
    }

    private func stopAllFinishes() {
        for task in finishing.values { task.cancel() }
        finishing = [:]
        for ref in Array(follows.keys) { stopFollowing(ref) }
    }

    /// Applies `change` to the detector; saves it when it changed.
    private func changeDetector(_ change: (inout SessionFinishDetector) -> Void) {
        let before = detector
        change(&detector)
        guard detector != before else { return }
        sessionsChanged = true
        scheduleSave()
    }

    /// Keeps the newest agent reply seen live for `ref`; while a finish note follows `ref`, a newer
    /// reply goes into that note instead.
    private func remember(_ entries: [ChatEntry], of ref: SessionRef) {
        guard let newest = Self.newestAgentLine(entries) else { return }
        if let follow = follows[ref] {
            if Self.isNewer(newest, than: (follow.seq, follow.rev)), isIdle(ref) { update(follow, of: ref, with: newest) }
            return
        }
        if let current = lastAgentLines[ref], !Self.isNewer(newest, than: current) { return }
        lastAgentLines[ref] = newest
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
        guard let writer else { return }
        if homeChanged {
            homeChanged = false
            await writer.save(HomeDocument(entries: entries, lastUsed: lastUsed), to: .home)
        }
        if sessionsChanged {
            sessionsChanged = false
            await writer.save(detector, to: .lastSessions)
        }
    }

    private static func capped(_ entries: [HomeEntry]) -> [HomeEntry] {
        entries.count > maxEntries ? Array(entries.suffix(maxEntries)) : entries
    }

    private static func isNewer(_ line: AgentLine, than other: AgentLine) -> Bool {
        isNewer(line, than: (other.seq, other.rev))
    }

    private static func isNewer(_ line: AgentLine, than other: (seq: Int, rev: Int)) -> Bool {
        (line.seq, line.rev) > (other.seq, other.rev)
    }

    /// The newest agent prose among `entries`, as its first line.
    private static func newestAgentLine(_ entries: [ChatEntry]) -> AgentLine? {
        entries
            .filter { $0.role == .agent && $0.kind == .prose }
            .max { ($0.seq, $0.rev) < ($1.seq, $1.rev) }
            .map { AgentLine(seq: $0.seq, rev: $0.rev, line: firstLine($0.text)) }
    }

    /// The first non-blank line of `text`, trimmed, cut to `summaryLength` characters (with "…").
    static func firstLine(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline)
            .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line else { return nil }
        guard line.count > summaryLength else { return line }
        return String(line.prefix(summaryLength - 1)) + "…"
    }
}
