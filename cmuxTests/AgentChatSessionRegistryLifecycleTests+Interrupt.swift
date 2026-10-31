import CMUXAgentLaunch
import CmuxAgentChat
@testable import CmuxMobileHost
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Claude Code runs no hook when the user stops a turn with Esc on the Mac, and then waits at its prompt
/// with its process alive. Without another signal the chat session stays working for good, and a phone
/// shows "Running · 52 hours". Two signals settle it the way the phone's own interrupt does (idle, still
/// hook-established): Claude's OSC 7501 activity record ending on its terminal, and the interrupt marker
/// Claude writes to its transcript.
extension AgentChatSessionRegistryLifecycleTests {
    private static func time(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    @MainActor
    @discardableResult
    private static func hook(
        _ registry: AgentChatSessionRegistry,
        _ sessionID: String,
        _ name: WorkstreamEvent.HookEventName,
        source: String = "claude",
        surface: String,
        at seconds: TimeInterval
    ) -> AgentChatSessionRecord {
        registry.noteHookEvent(WorkstreamEvent(
            sessionId: sessionID,
            hookEventName: name,
            source: source,
            surfaceId: surface,
            receivedAt: time(seconds)
        ))
    }

    @MainActor
    @Test("A turn whose agent reported its end on the terminal settles from working to idle")
    func settledTurnMovesWorkingSessionToIdle() throws {
        let registry = AgentChatSessionRegistry()
        let sessionID = "esc-session"
        let surfaceID = UUID().uuidString
        Self.hook(registry, sessionID, .sessionStart, surface: surfaceID, at: 100)
        Self.hook(registry, sessionID, .userPromptSubmit, surface: surfaceID, at: 101)
        Self.hook(registry, sessionID, .preToolUse, surface: surfaceID, at: 102)

        #expect(registry.noteTurnSettled(surfaceID: surfaceID, agentKind: .claude, at: Self.time(103)) == [sessionID])

        let settled = try #require(registry.record(sessionID: sessionID))
        #expect(settled.state == .idle)
        #expect(settled.hasHookLifecycleState)
        #expect(settled.lastActivityAt == Self.time(103))
        // Already idle: a repeated report changes nothing.
        #expect(registry.noteTurnSettled(surfaceID: surfaceID, agentKind: .claude, at: Self.time(104)).isEmpty)
        // The next prompt starts a new turn: hooks stay authoritative.
        let resumed = Self.hook(registry, sessionID, .userPromptSubmit, surface: surfaceID, at: 105)
        #expect(resumed.state == .working(since: Self.time(105)))
    }

    @MainActor
    @Test("A turn that went on after the agent's report keeps working")
    func turnThatResumedAfterTheEdgeStaysWorking() throws {
        let registry = AgentChatSessionRegistry()
        let surfaceID = UUID().uuidString
        let prompted = "prompted-again", toolUse = "tool-after-edge"
        let answered = "answered-after-edge"
        for sessionID in [prompted, toolUse, answered] {
            Self.hook(registry, sessionID, .sessionStart, surface: surfaceID, at: 100)
        }
        // A prompt sent while working keeps the turn's start time but is later activity.
        Self.hook(registry, prompted, .userPromptSubmit, surface: surfaceID, at: 101)
        Self.hook(registry, prompted, .userPromptSubmit, surface: surfaceID, at: 103)
        Self.hook(registry, toolUse, .userPromptSubmit, surface: surfaceID, at: 101)
        Self.hook(registry, toolUse, .preToolUse, surface: surfaceID, at: 103)
        // An answer typed after the edge reopens the turn.
        Self.hook(registry, answered, .permissionRequest, surface: surfaceID, at: 101)
        #expect(registry.noteUserInput(surfaceID: surfaceID, at: Self.time(103)) == 1)

        #expect(registry.noteTurnSettled(surfaceID: surfaceID, agentKind: .claude, at: Self.time(102)).isEmpty)

        #expect(registry.record(sessionID: prompted)?.state == .working(since: Self.time(101)))
        #expect(registry.record(sessionID: toolUse)?.state == .working(since: Self.time(101)))
        #expect(registry.record(sessionID: answered)?.state == .working(since: Self.time(103)))
    }

    @MainActor
    @Test("Esc on a permission prompt settles the needs-input state it cancelled")
    func settledTurnClearsCancelledNeedsInput() throws {
        let registry = AgentChatSessionRegistry()
        let waiting = "waiting-prompt", typed = "typed-esc"
        let waitingSurface = UUID().uuidString, typedSurface = UUID().uuidString
        Self.hook(registry, waiting, .sessionStart, surface: waitingSurface, at: 100)
        Self.hook(registry, waiting, .permissionRequest, surface: waitingSurface, at: 101)
        Self.hook(registry, typed, .sessionStart, surface: typedSurface, at: 100)
        Self.hook(registry, typed, .permissionRequest, surface: typedSurface, at: 101)
        // The Esc key typed on the Mac is explicit input first: needs-input becomes working.
        #expect(registry.noteUserInput(surfaceID: typedSurface, at: Self.time(102)) == 1)

        #expect(registry.noteTurnSettled(surfaceID: waitingSurface, agentKind: .claude, at: Self.time(103)) == [waiting])
        #expect(registry.noteTurnSettled(surfaceID: typedSurface, agentKind: .claude, at: Self.time(103)) == [typed])

        #expect(registry.record(sessionID: waiting)?.state == .idle)
        #expect(registry.record(sessionID: typed)?.state == .idle)
        #expect(registry.record(sessionID: typed)?.hasHookLifecycleState == true)
    }

    @MainActor
    @Test("Only the reporting agent on its own terminal settles")
    func settlementIsScopedToTheReportingAgentAndTerminal() throws {
        let registry = AgentChatSessionRegistry()
        let surfaceID = UUID().uuidString, otherSurface = UUID().uuidString
        let claude = "surface-session", neighbour = "neighbour-session", codex = "surface-codex-thread"
        Self.hook(registry, claude, .userPromptSubmit, surface: surfaceID, at: 101)
        Self.hook(registry, neighbour, .userPromptSubmit, surface: otherSurface, at: 101)
        Self.hook(registry, codex, .userPromptSubmit, source: "codex", surface: surfaceID, at: 101)

        #expect(registry.noteTurnSettled(surfaceID: surfaceID, agentKind: .claude, at: Self.time(102)) == [claude])

        #expect(registry.record(sessionID: claude)?.state == .idle)
        #expect(registry.record(sessionID: neighbour)?.state == .working(since: Self.time(101)))
        #expect(registry.record(sessionID: codex)?.state == .working(since: Self.time(101)))
    }

    @MainActor
    @Test("A transcript interrupt marker settles the turn it ends, including a cancelled tool prompt")
    func transcriptInterruptMarkerSettlesTheTurnItEnds() throws {
        let registry = AgentChatSessionRegistry()
        let surfaceID = UUID().uuidString
        let working = "marker-working", asking = "marker-tool-use"
        let idle = "marker-idle", codex = "marker-codex-thread"
        Self.hook(registry, working, .userPromptSubmit, surface: surfaceID, at: 101)
        // "[Request interrupted by user for tool use]": Esc on a permission prompt.
        Self.hook(registry, asking, .permissionRequest, surface: UUID().uuidString, at: 101)
        Self.hook(registry, idle, .sessionStart, surface: UUID().uuidString, at: 101)
        Self.hook(registry, codex, .userPromptSubmit, source: "codex", surface: UUID().uuidString, at: 101)

        // A marker from before this turn started (an earlier turn, a replayed tail) settles nothing.
        #expect(registry.noteTranscriptInterrupt(sessionID: working, at: Self.time(100)) == false)
        #expect(registry.record(sessionID: working)?.state == .working(since: Self.time(101)))

        #expect(registry.noteTranscriptInterrupt(sessionID: working, at: Self.time(102)))
        #expect(registry.noteTranscriptInterrupt(sessionID: asking, at: Self.time(102)))
        #expect(registry.noteTranscriptInterrupt(sessionID: idle, at: Self.time(102)) == false)
        #expect(registry.noteTranscriptInterrupt(sessionID: codex, at: Self.time(102)) == false)

        let settled = try #require(registry.record(sessionID: working))
        #expect(settled.state == .idle)
        #expect(settled.hasHookLifecycleState)
        #expect(settled.lastActivityAt == Self.time(102))
        #expect(registry.record(sessionID: asking)?.state == .idle)
        #expect(registry.record(sessionID: codex)?.state == .working(since: Self.time(101)))
        // A prompt after the interrupt reopens the turn, and the old marker cannot end it again.
        Self.hook(registry, working, .userPromptSubmit, surface: surfaceID, at: 103)
        #expect(registry.noteTranscriptInterrupt(sessionID: working, at: Self.time(102)) == false)
        #expect(registry.record(sessionID: working)?.state == .working(since: Self.time(103)))
    }

    @MainActor
    @Test("A transcript interrupt marker older than the session's latest hook settles nothing")
    func transcriptInterruptMarkerBeforeALaterHookKeepsTheTurn() throws {
        let registry = AgentChatSessionRegistry()
        let sessionID = "marker-before-prompt"
        let surfaceID = UUID().uuidString
        Self.hook(registry, sessionID, .userPromptSubmit, surface: surfaceID, at: 101)
        // A prompt sent while working keeps the turn's start time, but is activity after the marker.
        Self.hook(registry, sessionID, .userPromptSubmit, surface: surfaceID, at: 103)

        #expect(registry.noteTranscriptInterrupt(sessionID: sessionID, at: Self.time(102)) == false)

        let record = try #require(registry.record(sessionID: sessionID))
        #expect(record.state == .working(since: Self.time(101)))
        #expect(record.lastActivityAt == Self.time(103))
    }
}
