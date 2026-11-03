import CMUXAgentLaunch
import CmuxAgentChat
import CmuxMobileHost
import Foundation
import ShellXLinkCore
import ShellXLinkSession
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// ShellX Link's `AgentSessionSource` over the agent chat session registry: which sessions a phone lists, in
/// which state, and the numbered changes it is pushed.
@Suite("ShellX Link session source", .serialized, .timeLimit(.minutes(1)))
struct ShellXLinkSessionSourceTests {
    private static let workspace = (id: "11111111-2222-3333-4444-555555555555", title: "shellx")
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// A service over an empty, private hook store (no mobile client subscribed) and a source on it whose
    /// workspace lookup needs no live window. Without `terminals` or `openTerminals`, whether a terminal is
    /// open is not known, so none is taken for closed.
    @MainActor
    private static func makeSource(
        home: URL,
        terminals: OpenTerminals? = nil,
        openTerminals: ShellXLinkSessionSource.OpenTerminals? = nil,
        signal: ManualChangeSignal? = nil
    ) -> (AgentChatTranscriptService, ShellXLinkSessionSource) {
        let signal = signal ?? ManualChangeSignal()
        let service = AgentChatTranscriptService(
            registry: AgentChatSessionRegistry(hookStore: AgentChatHookSessionStore(homeDirectory: home)),
            resolver: AgentChatTranscriptResolver(homeDirectory: home, environment: [:]),
            hasEventSubscribers: { false },
            emitEventPayload: { _ in }
        )
        let source = ShellXLinkSessionSource(
            service: { service },
            workspaceLookup: { _ in workspace },
            openTerminals: openTerminals ?? { terminals?.open },
            changeSignal: signal.start
        )
        return (service, source)
    }

    /// The terminals open on the Mac, as the tests set them.
    @MainActor
    final class OpenTerminals {
        var open: Set<UUID>
        init(_ open: Set<UUID> = []) { self.open = open }
    }

    /// A change signal the tests fire by hand, like a tab closing.
    @MainActor
    final class ManualChangeSignal {
        private var onChange: (@MainActor () -> Void)?
        func start(_ onChange: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
            self.onChange = onChange
            return { [weak self] in self?.onChange = nil }
        }
        func fire() { onChange?() }
    }

    private static func makeHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shellx-link-sessions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// An existing (empty) transcript, so an ended Claude session stays listable.
    private static func transcript(in home: URL) throws -> String {
        let url = home.appendingPathComponent("\(UUID().uuidString).jsonl")
        try Data().write(to: url)
        return url.path
    }

    private static func event(
        _ sessionID: String, _ name: WorkstreamEvent.HookEventName, source: String = "claude",
        surface: String? = nil, transcriptPath: String? = nil, at offset: TimeInterval = 0
    ) -> WorkstreamEvent {
        WorkstreamEvent(
            sessionId: sessionID, hookEventName: name, source: source, surfaceId: surface,
            transcriptPath: transcriptPath, cwd: "/Users/example/project", receivedAt: start.addingTimeInterval(offset)
        )
    }

    /// A transcript holding `lines`, as Claude Code writes it.
    private static func transcript(in home: URL, lines: [String]) throws -> URL {
        let url = home.appendingPathComponent("\(UUID().uuidString).jsonl")
        try lines.map { $0 + "\n" }.joined().write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func append(_ line: String, to transcript: URL) throws {
        let handle = try FileHandle(forWritingTo: transcript)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line + "\n").utf8))
        try handle.close()
    }

    private static func transcriptLine(text: String, at offset: TimeInterval, extra: [String: Any] = [:]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var object: [String: Any] = [
            "type": "user", "isSidechain": false, "uuid": UUID().uuidString, "sessionId": "s",
            "message": ["role": "user", "content": [["type": "text", "text": text]]],
            "timestamp": formatter.string(from: start.addingTimeInterval(offset)),
        ]
        object.merge(extra) { _, new in new }
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    /// The line Claude Code writes when the user stops a turn (Esc), or rejects a tool prompt with Esc.
    private static func interruptLine(at offset: TimeInterval, forToolUse: Bool = false) -> String {
        let text = forToolUse ? "[Request interrupted by user for tool use]" : "[Request interrupted by user]"
        return transcriptLine(text: text, at: offset, extra: ["interruptedMessageId": "msg_01"])
    }

    private static func ms(_ offset: TimeInterval) -> Int64 {
        Int64((start.addingTimeInterval(offset).timeIntervalSince1970 * 1000).rounded())
    }

    @MainActor
    private static func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    @Test func testClaudeSessionsListedWithState() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let idle = UUID().uuidString, busy = UUID().uuidString, asks = UUID().uuidString
        let done = UUID().uuidString, codex = UUID().uuidString
        let donePath = try Self.transcript(in: home)
        let (service, source) = await MainActor.run { Self.makeSource(home: home) }
        await MainActor.run {
            service.noteHookEvent(Self.event(idle, .sessionStart))
            service.noteHookEvent(Self.event(busy, .sessionStart))
            service.noteHookEvent(Self.event(busy, .userPromptSubmit, at: 5))
            service.noteHookEvent(Self.event(asks, .sessionStart))
            service.noteHookEvent(Self.event(asks, .permissionRequest, at: 7))
            service.noteHookEvent(Self.event(done, .sessionStart, transcriptPath: donePath))
            service.noteHookEvent(Self.event(done, .sessionEnd, transcriptPath: donePath, at: 9))
            service.noteHookEvent(Self.event(codex, .sessionStart, source: "codex"))
        }

        let list = await source.sessions().sessions
        let byID = Dictionary(uniqueKeysWithValues: list.map { ($0.sessionId, $0) })

        // Claude Code only (v1).
        #expect(Set(byID.keys) == [idle, busy, asks, done])
        #expect(byID[idle]?.state == .idle)
        #expect(byID[idle]?.stateSinceMs == nil)
        #expect(byID[busy]?.state == .working)
        #expect(byID[busy]?.stateSinceMs == Self.ms(5))
        #expect(byID[asks]?.state == .needsInput)
        #expect(byID[asks]?.stateSinceMs == Self.ms(7))
        #expect(byID[done]?.state == .ended)
        #expect(list.allSatisfy { $0.agent == "claude" })
        #expect(list.allSatisfy { $0.workspaceId == Self.workspace.id && $0.workspaceTitle == Self.workspace.title })
        #expect(byID[busy]?.lastActivityMs == Self.ms(5))
    }

    /// A tab or workspace closed on the Mac ends its agent; the ended session then leaves the phone, not even
    /// listed as ended. A session still running after its tab closed stays: the phone never loses sight of a
    /// live agent. A session that names no terminal (an agent run outside ShellX) stays.
    @Test func testEndedSessionsOfAClosedTabAreNotListed() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let openTab = UUID(), closedTab = UUID()
        let inOpenTab = UUID().uuidString, inClosedTab = UUID().uuidString
        let endedInClosedTab = UUID().uuidString, outside = UUID().uuidString
        let endedPath = try Self.transcript(in: home)
        let (service, source) = await MainActor.run {
            Self.makeSource(home: home, terminals: OpenTerminals([openTab]))
        }
        await MainActor.run {
            service.noteHookEvent(Self.event(inOpenTab, .sessionStart, surface: openTab.uuidString))
            service.noteHookEvent(Self.event(inClosedTab, .sessionStart, surface: closedTab.uuidString))
            service.noteHookEvent(Self.event(
                endedInClosedTab, .sessionStart, surface: closedTab.uuidString, transcriptPath: endedPath))
            service.noteHookEvent(Self.event(
                endedInClosedTab, .sessionEnd, surface: closedTab.uuidString, transcriptPath: endedPath, at: 2))
            service.noteHookEvent(Self.event(outside, .sessionStart))
        }

        let listed = Set(await source.sessions().sessions.map(\.sessionId))

        #expect(listed == [inOpenTab, inClosedTab, outside])
    }

    /// Closing a tab while a phone listens: its session stays while the agent shuts down, and the phone is sent
    /// its removal once it ended.
    @Test func testClosedTabSessionIsRemovedOnceEnded() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let tab = UUID()
        let session = UUID().uuidString
        let path = try Self.transcript(in: home)
        let terminals = await MainActor.run { OpenTerminals([tab]) }
        let signal = await MainActor.run { ManualChangeSignal() }
        let (service, source) = await MainActor.run {
            Self.makeSource(home: home, terminals: terminals, signal: signal)
        }
        await MainActor.run {
            service.noteHookEvent(Self.event(session, .sessionStart, surface: tab.uuidString, transcriptPath: path))
        }
        let changes = SessionChanges()
        let consumer = Task { for await change in source.sessionChanges() { changes.record(change) } }
        defer { consumer.cancel() }
        // The subscription registers on the main actor; this call orders it before the tab closes.
        let base = await source.sessions()
        #expect(base.sessions.map(\.sessionId) == [session])

        await MainActor.run {
            terminals.open.remove(tab)
            signal.fire()
        }

        // The agent is still shutting down: nothing changes for the phone.
        let closing = await source.sessions()
        #expect(closing.revision == base.revision)
        #expect(closing.sessions.map(\.sessionId) == [session])
        #expect(changes.all.isEmpty)

        await MainActor.run {
            service.noteHookEvent(Self.event(
                session, .sessionEnd, surface: tab.uuidString, transcriptPath: path, at: 2))
        }

        #expect(await Self.waitUntil { !changes.all.isEmpty })
        let ended = try #require(changes.all.first)
        #expect(ended.revision == base.revision + 1)
        #expect(ended.removed == [session])
        #expect(ended.upserted.isEmpty)
        #expect(await source.sessions().sessions.isEmpty)
    }

    /// An agent that ended in a tab still open stays listed as ended; closing that tab later removes it.
    @Test func testClosingTheTabOfAnEndedSessionEmitsRemoved() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let tab = UUID()
        let session = UUID().uuidString
        let path = try Self.transcript(in: home)
        let terminals = await MainActor.run { OpenTerminals([tab]) }
        let signal = await MainActor.run { ManualChangeSignal() }
        let (service, source) = await MainActor.run {
            Self.makeSource(home: home, terminals: terminals, signal: signal)
        }
        await MainActor.run {
            service.noteHookEvent(Self.event(session, .sessionStart, surface: tab.uuidString, transcriptPath: path))
            service.noteHookEvent(Self.event(
                session, .sessionEnd, surface: tab.uuidString, transcriptPath: path, at: 2))
        }
        let changes = SessionChanges()
        let consumer = Task { for await change in source.sessionChanges() { changes.record(change) } }
        defer { consumer.cancel() }
        let base = await source.sessions()
        #expect(base.sessions.first { $0.sessionId == session }?.state == .ended)

        await MainActor.run {
            terminals.open.remove(tab)
            signal.fire()
        }

        #expect(await Self.waitUntil { !changes.all.isEmpty })
        let closed = try #require(changes.all.first)
        #expect(closed.revision == base.revision + 1)
        #expect(closed.removed == [session])
        #expect(closed.upserted.isEmpty)
    }

    /// A terminal in a Dock (a workspace's or a window's) is open like one in a workspace's split tree: an
    /// agent that ended there stays listed as ended. An ended session whose terminal is in neither leaves.
    @MainActor
    @Test func testEndedSessionInADockTerminalStaysListed() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let dock = workspace.requiredDockSplitForTesting
        let pane = try #require(dock.bonsplitController.allPaneIds.first)
        let dockTerminal = try #require(dock.newSurface(kind: .terminal, inPane: pane, focus: false))
        let tabTerminal = try #require(workspace.panels.keys.first)
        let closed = UUID()
        let inDock = UUID().uuidString, inTab = UUID().uuidString, inClosed = UUID().uuidString
        let (service, source) = Self.makeSource(home: home, openTerminals: {
            ShellXLinkSessionSource.openTerminals(
                restoreFinished: true, workspacesByWindow: [[workspace]], docks: [dock])
        })
        for (session, terminal) in [(inDock, dockTerminal), (inTab, tabTerminal), (inClosed, closed)] {
            let path = try Self.transcript(in: home)
            service.noteHookEvent(Self.event(session, .sessionStart, surface: terminal.uuidString, transcriptPath: path))
            service.noteHookEvent(Self.event(
                session, .sessionEnd, surface: terminal.uuidString, transcriptPath: path, at: 1))
        }

        let listed = Set(await source.sessions().sessions.map(\.sessionId))

        #expect(listed == [inDock, inTab])
    }

    /// While the app launches, its windows are not registered yet and the last session is still being
    /// restored: no terminal can be taken for closed then, so every ended session stays listed.
    @MainActor
    @Test func testEndedSessionsStayListedUntilWindowsAreRestored() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let restoring = UUID().uuidString, noWindows = UUID().uuidString
        var state: (restoreFinished: Bool, windows: [[Workspace]]) = (false, [[workspace]])
        let (service, source) = Self.makeSource(home: home, openTerminals: {
            ShellXLinkSessionSource.openTerminals(
                restoreFinished: state.restoreFinished, workspacesByWindow: state.windows, docks: [])
        })
        for session in [restoring, noWindows] {
            let path = try Self.transcript(in: home)
            let terminal = UUID().uuidString   // restored later, or never: not in any window yet
            service.noteHookEvent(Self.event(session, .sessionStart, surface: terminal, transcriptPath: path))
            service.noteHookEvent(Self.event(session, .sessionEnd, surface: terminal, transcriptPath: path, at: 1))
        }

        // The windows exist but the launch's restore has not finished.
        #expect(Set(await source.sessions().sessions.map(\.sessionId)) == [restoring, noWindows])

        // The restore finished, but no main window is registered yet.
        state = (true, [])
        #expect(Set(await source.sessions().sessions.map(\.sessionId)) == [restoring, noWindows])

        // A window holds neither terminal: both were closed.
        state = (true, [[workspace]])
        #expect(await source.sessions().sessions.isEmpty)
    }

    /// One refresh reads the open terminals once, however many ended sessions name a terminal: the read
    /// walks every window, workspace and Dock, and runs up to four times a second while a phone listens.
    @MainActor
    @Test func testOpenTerminalsAreReadOncePerRefresh() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let open = UUID()
        var reads = 0
        let (service, source) = Self.makeSource(home: home, openTerminals: {
            reads += 1
            return [open]
        })
        for index in 0..<6 {
            let session = UUID().uuidString
            let terminal = index.isMultiple(of: 2) ? open.uuidString : UUID().uuidString
            let path = try Self.transcript(in: home)
            service.noteHookEvent(Self.event(
                session, .sessionStart, surface: terminal, transcriptPath: path, at: Double(index)))
            service.noteHookEvent(Self.event(
                session, .sessionEnd, surface: terminal, transcriptPath: path, at: Double(index) + 0.5))
        }

        #expect(await source.sessions().sessions.count == 3)
        #expect(reads == 1)
        _ = await source.sessions()
        #expect(reads == 2)
    }

    @Test func testStateChangeEmitsUpsertWithNextRevision() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let session = UUID().uuidString
        let (service, source) = await MainActor.run { Self.makeSource(home: home) }
        await MainActor.run { service.noteHookEvent(Self.event(session, .sessionStart)) }
        var changes = source.sessionChanges().makeAsyncIterator()
        // The subscription registers on the main actor; this call orders it before the next hook.
        let base = await source.sessions().revision
        #expect(await MainActor.run { service.frameObserverCount } == 1)

        await MainActor.run { service.noteHookEvent(Self.event(session, .userPromptSubmit, at: 3)) }

        let working = try #require(await changes.next())
        #expect(working.revision == base + 1)
        #expect(working.removed.isEmpty)
        #expect(working.upserted.map(\.sessionId) == [session])
        #expect(working.upserted.first?.state == .working)
        #expect(working.upserted.first?.stateSinceMs == Self.ms(3))

        await MainActor.run { service.noteHookEvent(Self.event(session, .stop, at: 4)) }

        let idle = try #require(await changes.next())
        #expect(idle.revision == base + 2)
        #expect(idle.upserted.first?.state == .idle)
        // A snapshot at revision r includes every change up to r.
        let now = await source.sessions()
        #expect(now.revision == base + 2)
        #expect(now.sessions.first { $0.sessionId == session }?.state == .idle)
    }

    @Test func testRemovedSessionEmitsRemoved() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let session = UUID().uuidString
        // No transcript: once ended, the session is not listable, and the service publishes its removal.
        let missing = home.appendingPathComponent("missing.jsonl").path
        let (service, source) = await MainActor.run { Self.makeSource(home: home) }
        await MainActor.run { service.noteHookEvent(Self.event(session, .sessionStart, transcriptPath: missing)) }
        var changes = source.sessionChanges().makeAsyncIterator()
        let before = await source.sessions()
        #expect(before.sessions.map(\.sessionId) == [session])

        await MainActor.run {
            service.noteHookEvent(Self.event(session, .sessionEnd, transcriptPath: missing, at: 2))
        }

        let change = try #require(await changes.next())
        #expect(change.revision == before.revision + 1)
        #expect(change.removed == [session])
        #expect(change.upserted.isEmpty)
        let after = await source.sessions()
        #expect(after.revision == before.revision + 1)
        #expect(after.sessions.isEmpty)
    }

    /// Ended sessions stay listed for history, but only the most recent ones: the hook store keeps up to
    /// 512 sessions for a week, which would not fit an `agent.sessions` frame.
    @Test func testOnlyRecentEndedSessionsListed() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let live = UUID().uuidString
        let ended = (0..<(ShellXLinkSessionSource.maxEndedSessions + 2)).map { _ in UUID().uuidString }
        let paths = try ended.map { _ in try Self.transcript(in: home) }
        let (service, source) = await MainActor.run { Self.makeSource(home: home) }
        await MainActor.run {
            for (index, id) in ended.enumerated() {
                service.noteHookEvent(Self.event(id, .sessionStart, transcriptPath: paths[index], at: Double(index)))
                service.noteHookEvent(Self.event(id, .sessionEnd, transcriptPath: paths[index], at: Double(index) + 0.5))
            }
            service.noteHookEvent(Self.event(live, .sessionStart, at: 1))
        }

        let listed = Set(await source.sessions().sessions.map(\.sessionId))

        #expect(listed.contains(live))
        #expect(listed.subtracting([live]) == Set(ended.suffix(ShellXLinkSessionSource.maxEndedSessions)))
    }

    /// Claude Code fires no hook when it is interrupted (Esc or ctrl-C) and then waits for input. Once the
    /// shared interrupt path's key is accepted, the session turns idle and every phone is told; an interrupt
    /// the terminal never took changes nothing.
    ///
    /// The accepted key is explicit input first: the terminal's `onExplicitInput` reaches
    /// `noteAcceptedAgentInput`, which moves a needs-input session to working, and `agentChatInterrupt` then
    /// moves it to idle, in the same main-actor turn. A phone gets both changes, in order, and ends idle.
    @Test func testInterruptMovesSessionToIdle() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let working = UUID().uuidString, asking = UUID().uuidString
        let workingSurface = UUID().uuidString, askingSurface = UUID().uuidString
        let (service, source) = await MainActor.run { Self.makeSource(home: home) }
        await MainActor.run {
            service.noteHookEvent(Self.event(working, .sessionStart, surface: workingSurface))
            service.noteHookEvent(Self.event(working, .userPromptSubmit, surface: workingSurface, at: 3))
            service.noteHookEvent(Self.event(asking, .sessionStart, surface: askingSurface))
            service.noteHookEvent(Self.event(asking, .permissionRequest, surface: askingSurface, at: 4))
        }
        let changes = SessionChanges()
        let consumer = Task { for await change in source.sessionChanges() { changes.record(change) } }
        defer { consumer.cancel() }
        // The subscription registers on the main actor; this call orders it before the interrupts.
        let base = await source.sessions().revision
        // What an accepted interrupt key does in production, in one main-actor turn.
        @MainActor func acceptedInterrupt(_ sessionID: String, surface: String) {
            service.noteExplicitInput(surfaceID: surface)   // the key's `onExplicitInput`
            service.noteInterrupted(sessionID: sessionID)   // `agentChatInterrupt` after the key was accepted
        }

        // The shared path finds no terminal for this session: no key reached the agent, so nothing changes.
        let link = await MainActor.run { ShellXLinkChatSource(service: { service }) }
        #expect(await link.interrupt(sessionId: working, hard: false) == .notFound)
        #expect(await source.sessions().sessions.first { $0.sessionId == working }?.state == .working)

        // A working session: explicit input leaves it working, the interrupt makes it idle.
        await MainActor.run { acceptedInterrupt(working, surface: workingSurface) }
        #expect(await Self.waitUntil { changes.all.count == 1 })
        let stopped = try #require(changes.all.first)
        #expect(stopped.revision == base + 1)
        #expect(stopped.upserted.map(\.sessionId) == [working])
        #expect(stopped.upserted.first?.state == .idle)
        #expect(stopped.upserted.first?.stateSinceMs == nil)

        // Esc on a permission prompt rejects it and stops the turn: working for an instant, then idle.
        await MainActor.run { acceptedInterrupt(asking, surface: askingSurface) }
        #expect(await Self.waitUntil { changes.all.count == 3 })
        let states = changes.all.dropFirst().map { change in
            change.upserted.first { $0.sessionId == asking }?.state
        }
        #expect(states == [.working, .idle])
        #expect(changes.all.map(\.revision) == [base + 1, base + 2, base + 3])
        #expect(await source.sessions().sessions.first { $0.sessionId == asking }?.state == .idle)
        // An idle session stays as it is: no change is published.
        await MainActor.run { acceptedInterrupt(working, surface: workingSurface) }
        #expect(await source.sessions().revision == base + 3)
    }

    /// Claude Code runs no hook when the user stops a turn with Esc on the Mac; its process waits at the prompt,
    /// so the phone showed "Running · 52 hours". Once the agent's own activity report ends on its terminal (the
    /// sidebar's OSC 7501 settlement), the session turns idle and every phone is told. A session that went on
    /// after that report stays working.
    @Test func testMacInterruptSettlesSessionToIdle() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let stopped = UUID().uuidString, resumed = UUID().uuidString
        let stoppedSurface = UUID().uuidString, resumedSurface = UUID().uuidString
        let (service, source) = await MainActor.run { Self.makeSource(home: home) }
        await MainActor.run {
            service.noteHookEvent(Self.event(stopped, .sessionStart, surface: stoppedSurface))
            service.noteHookEvent(Self.event(stopped, .userPromptSubmit, surface: stoppedSurface, at: 3))
            service.noteHookEvent(Self.event(resumed, .sessionStart, surface: resumedSurface))
            service.noteHookEvent(Self.event(resumed, .userPromptSubmit, surface: resumedSurface, at: 3))
            service.noteHookEvent(Self.event(resumed, .preToolUse, surface: resumedSurface, at: 6))
        }
        let changes = SessionChanges()
        let consumer = Task { for await change in source.sessionChanges() { changes.record(change) } }
        defer { consumer.cancel() }
        // The subscription registers on the main actor; this call orders it before the settlement.
        let base = await source.sessions().revision

        let edge = Self.start.addingTimeInterval(5)
        let settled = await MainActor.run {
            service.noteTurnSettled(surfaceID: stoppedSurface, agentKind: .claude, at: edge)
                + service.noteTurnSettled(surfaceID: resumedSurface, agentKind: .claude, at: edge)
        }

        #expect(settled == 1)
        #expect(await Self.waitUntil { changes.all.count == 1 })
        let change = try #require(changes.all.first)
        #expect(change.revision == base + 1)
        #expect(change.upserted.map(\.sessionId) == [stopped])
        #expect(change.upserted.first?.state == .idle)
        #expect(change.upserted.first?.stateSinceMs == nil)
        let now = await source.sessions()
        #expect(now.revision == base + 1)
        #expect(now.sessions.first { $0.sessionId == resumed }?.state == .working)
        #expect(now.sessions.first { $0.sessionId == resumed }?.stateSinceMs == Self.ms(3))
    }

    /// With a phone connected the transcript is tailed, and the "[Request interrupted by user]" line Claude Code
    /// writes when the user stops a turn settles the session by itself.
    @Test func testTranscriptInterruptMarkerSettlesSessionToIdle() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let session = UUID().uuidString
        let transcript = try Self.transcript(in: home, lines: [Self.transcriptLine(text: "Refactor the parser", at: 2)])
        let (service, source) = await MainActor.run { Self.makeSource(home: home) }
        let changes = SessionChanges()
        let consumer = Task { for await change in source.sessionChanges() { changes.record(change) } }
        defer { consumer.cancel() }
        // The subscription registers on the main actor; this call orders it before the hooks, which then tail.
        _ = await source.sessions()
        await MainActor.run {
            service.noteHookEvent(Self.event(session, .sessionStart, transcriptPath: transcript.path))
            service.noteHookEvent(Self.event(session, .userPromptSubmit, transcriptPath: transcript.path, at: 2))
        }
        // Waits for the tailer's first read, so the marker arrives as a live append.
        _ = await service.history(sessionID: session, beforeSeq: nil, limit: 1)
        #expect(await source.sessions().sessions.first { $0.sessionId == session }?.state == .working)

        try Self.append(Self.interruptLine(at: 4), to: transcript)

        #expect(await Self.waitUntil {
            changes.all.last?.upserted.first { $0.sessionId == session }?.state == .idle
        })
        let listed = await source.sessions().sessions.first { $0.sessionId == session }
        #expect(listed?.state == .idle)
        #expect(listed?.stateSinceMs == nil)
    }

    /// A session stopped while no phone was connected: nothing tailed its transcript. Opening its chat reads the
    /// transcript, and an interrupt marker that ends it settles the session, here the "for tool use" marker of an
    /// Esc on a permission prompt. A hook after the marker (a newer prompt) wins over it.
    @Test func testOpeningChatSettlesSessionWhoseTranscriptEndsInterrupted() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let stopped = UUID().uuidString, resumed = UUID().uuidString
        let lines = [Self.transcriptLine(text: "Deploy it", at: 2), Self.interruptLine(at: 5, forToolUse: true)]
        let stoppedPath = try Self.transcript(in: home, lines: lines).path
        let resumedPath = try Self.transcript(in: home, lines: lines).path
        let (service, source) = await MainActor.run { Self.makeSource(home: home) }
        await MainActor.run {
            service.noteHookEvent(Self.event(stopped, .sessionStart, transcriptPath: stoppedPath))
            service.noteHookEvent(Self.event(stopped, .userPromptSubmit, transcriptPath: stoppedPath, at: 2))
            service.noteHookEvent(Self.event(stopped, .permissionRequest, transcriptPath: stoppedPath, at: 4))
            service.noteHookEvent(Self.event(resumed, .sessionStart, transcriptPath: resumedPath))
            service.noteHookEvent(Self.event(resumed, .userPromptSubmit, transcriptPath: resumedPath, at: 7))
        }
        #expect(await source.sessions().sessions.first { $0.sessionId == stopped }?.state == .needsInput)

        for session in [resumed, stopped] {
            #expect(await service.history(sessionID: session, beforeSeq: nil, limit: 50)?.messages.count == 2)
        }

        #expect(await Self.waitUntil { service.sessionRecord(sessionID: stopped)?.state == .idle })
        let listed = await source.sessions().sessions
        #expect(listed.first { $0.sessionId == stopped }?.state == .idle)
        #expect(listed.first { $0.sessionId == stopped }?.stateSinceMs == nil)
        #expect(listed.first { $0.sessionId == resumed }?.state == .working)
        #expect(listed.first { $0.sessionId == resumed }?.stateSinceMs == Self.ms(7))
    }

    @Test func testEndedSubscriberStopsObserving() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (service, source) = await MainActor.run { Self.makeSource(home: home) }
        let consumer = Task { for await _ in source.sessionChanges() {} }
        _ = await source.sessions()
        #expect(await MainActor.run { source.subscriberCount } == 1)
        #expect(await MainActor.run { service.frameObserverCount } == 1)

        consumer.cancel()
        _ = await consumer.value

        #expect(await Self.waitUntil { source.subscriberCount == 0 && service.frameObserverCount == 0 })
    }
}

/// The changes one `sessionChanges()` subscriber received, filled by its consumer task.
private final class SessionChanges: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ShellXLinkSessionSource.Change] = []
    func record(_ change: ShellXLinkSessionSource.Change) { lock.lock(); recorded.append(change); lock.unlock() }
    var all: [ShellXLinkSessionSource.Change] { lock.lock(); defer { lock.unlock() }; return recorded }
}
