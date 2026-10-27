import Foundation
import Observation
import ShellXLinkCore

/// The home conversation, "ShellX" (plan decision D7): what the user said or typed, and ShellX's
/// canned notes about it, kept on the phone; which running session the composer sends to; and the
/// live sessions' status rows.
///
/// `submit(_:viaVoice:)` sends to one running session and notes the outcome. `run()` watches the hub
/// and notes each session that finishes a turn, with the first line of its last reply. Every change
/// is written to the store at most `saveDelay` after the last one, and at once by `flush()` (the app
/// calls it when it goes to the background). Writes use the store writer of the account that loaded
/// the model, so nothing is written after a sign-out wipe.
@MainActor @Observable
public final class HomeModel {
    /// The most entries kept; the oldest go first.
    public static let maxEntries = 2000
    public static let saveDelay: Duration = .milliseconds(500)
    /// The longest summary in an `agentFinished` note, in characters.
    static let summaryLength = 140

    public private(set) var entries: [HomeEntry] = []
    /// The session the user picked in the composer; nil leaves it to `effectiveTarget`.
    public var target: SessionRef?
    /// True once `load()` read the stored timeline.
    public private(set) var isLoaded = false
    /// The session the last message went to.
    private var lastUsed: SessionRef?

    /// The last agent reply seen live for one session.
    private struct AgentLine {
        var seq: Int
        var rev: Int
        var line: String?
    }

    @ObservationIgnored private let hub: MachineHub
    @ObservationIgnored private let store: ConversationStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var writer: ConversationStore.Writer?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var writing: Task<Void, Never>?
    @ObservationIgnored private var homeChanged = false
    @ObservationIgnored private var sessionsChanged = false
    @ObservationIgnored private var detector = SessionFinishDetector()
    @ObservationIgnored private var lastAgentLines: [SessionRef: AgentLine] = [:]
    @ObservationIgnored private var observers = 0

    /// `sleep` waits out `saveDelay`; tests pass one they release by hand.
    public init(
        hub: MachineHub, store: ConversationStore, now: @escaping () -> Date,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.hub = hub
        self.store = store
        self.now = now
        self.sleep = sleep
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

    /// The first line of the last agent reply seen live for `ref` (tests).
    func lastAgentLine(for ref: SessionRef) -> String? {
        lastAgentLines[ref]?.line
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
        if hub.isLoaded {
            changeDetector { $0.retain(machineIDs: Set(hub.machines.map(\.id))) }
        }
        // Lists that arrived before this subscription. Only a synced (online) Mac's list counts: a
        // Mac still connecting has an empty one, which would hide what finished meanwhile.
        for machine in hub.machines where machine.state == .online {
            await sessionsArrived(machineID: machine.id, sessions: machine.sessions.sessions)
        }
        observers += 1
        defer { observers -= 1 }
        async let chat: Void = follow(chatUpdates)
        async let sessions: Void = follow(sessionUpdates)
        _ = await (chat, sessions)
    }

    private func follow(_ updates: AsyncStream<(SessionRef, [ChatEntry])>) async {
        for await (ref, entries) in updates { remember(entries, of: ref) }
    }

    private func follow(_ updates: AsyncStream<(machineID: String, sessions: [AgentSession])>) async {
        for await update in updates {
            await sessionsArrived(machineID: update.machineID, sessions: update.sessions)
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
    }

    private func noTargetNote() -> HomeNote {
        if let id = hub.defaultMachineID, let machine = hub.machines.first(where: { $0.id == id }),
            machine.state != .online
        {
            return .machineOffline(machineName: machine.name)
        }
        return .noLiveSession
    }

    private func append(_ content: HomeEntry.Content) {
        entries.append(HomeEntry(id: UUID().uuidString, at: now(), content: content))
        entries = Self.capped(entries)
        homeChanged = true
        scheduleSave()
    }

    private func sessionsArrived(machineID: String, sessions: [AgentSession]) async {
        var finished: [SessionRef] = []
        changeDetector { finished = $0.observe(machineID: machineID, sessions: sessions) }
        let listed = Set(sessions.map(\.sessionId))
        lastAgentLines = lastAgentLines.filter { $0.key.machineID != machineID || listed.contains($0.key.sessionId) }
        for ref in finished {
            let summary = await summary(for: ref)
            // A reply serves one finish: the next turn's note never quotes this one.
            lastAgentLines[ref] = nil
            append(.note(.agentFinished(ref, summary: summary)))
        }
    }

    /// Applies `change` to the detector; saves it when it changed.
    private func changeDetector(_ change: (inout SessionFinishDetector) -> Void) {
        let before = detector
        change(&detector)
        guard detector != before else { return }
        sessionsChanged = true
        scheduleSave()
    }

    /// The first line of the session's last agent reply: seen live, otherwise from its last ten
    /// history entries; nil when there is none or the history cannot be read.
    private func summary(for ref: SessionRef) async -> String? {
        if let seen = lastAgentLines[ref] { return seen.line }
        do {
            let page = try await hub.chatHistory(ref, beforeSeq: nil, limit: 10)
            return Self.newestAgentLine(page.entries)?.line
        } catch {
            return nil
        }
    }

    private func remember(_ entries: [ChatEntry], of ref: SessionRef) {
        guard let newest = Self.newestAgentLine(entries) else { return }
        if let current = lastAgentLines[ref], (current.seq, current.rev) >= (newest.seq, newest.rev) { return }
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
