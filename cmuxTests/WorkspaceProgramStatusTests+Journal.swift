import CMUXAgentLaunch
import CmuxAgentChat
import CmuxAgentJournal
import CmuxSidebar
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// A Claude session its hooks bound to the terminal (`SessionStart` records an agent-hook resume binding) has
/// its pane's lifecycle projected by the agent journal, so a settlement from Claude's OSC 7501 record goes
/// through the journal as well: the journal's fold, its notification reconciler and the sidebar then agree,
/// and the next hook event is judged against it.
extension WorkspaceProgramStatusTests {
    /// Esc during a turn of a bound session: the settlement's `turnCompleted` at the edge settles the pane's
    /// lifecycle after the turn's earlier hook events, which the journal holds with earlier times.
    @Test func claudeEscSettlesABoundSessionThroughTheJournal() async throws {
        try await withChatService { _ in
            try await Self.withBoundClaudePane { pane in
                let prompted = Date().addingTimeInterval(-10)
                pane.journal(.sessionStarted, at: prompted.addingTimeInterval(-1), nativeEvent: "SessionStart")
                pane.journal(.turnStarted, at: prompted, nativeEvent: "UserPromptSubmit")
                #expect(await Self.waitUntil { pane.lifecycle == .running })
                pane.workspace.setStatusEntry(
                    SidebarStatusEntry(key: "claude_code", value: "Running", timestamp: prompted, workState: .running),
                    key: "claude_code",
                    panelId: pane.panelId
                )
                pane.report(.working)

                pane.report(.clear)

                #expect(await Self.waitUntil { pane.lifecycle == .idle }, "lifecycle \(String(describing: pane.lifecycle))")
                #expect(pane.workspace.agentStatusEntriesByPanelId[pane.panelId]?["claude_code"]?.value != "Running")
                // The journal holds the settlement at the edge: a tool event from before it, delivered late, belongs
                // to the interrupted turn and does not reopen it.
                pane.journal(.stateChanged, at: prompted, nativeEvent: "PreToolUse", declaredPhase: .running)
                try await Task.sleep(nanoseconds: 200_000_000)
                #expect(pane.lifecycle == .idle)
            }
        }
    }

    /// Esc on a permission prompt of a bound session: the journal's needs-input phase settles to idle, so the
    /// pill and the waiting border stop.
    @Test func claudeEscOnAPromptSettlesABoundSessionThroughTheJournal() async throws {
        try await withChatService { _ in
            try await Self.withBoundClaudePane { pane in
                let asked = Date().addingTimeInterval(-10)
                pane.journal(.sessionStarted, at: asked.addingTimeInterval(-2), nativeEvent: "SessionStart")
                pane.journal(.turnStarted, at: asked.addingTimeInterval(-1), nativeEvent: "UserPromptSubmit")
                pane.journal(.approvalRequested, at: asked, nativeEvent: "PermissionRequest", request: "toolu_esc")
                #expect(await Self.waitUntil { pane.lifecycle == .needsInput })
                pane.workspace.setStatusEntry(
                    SidebarStatusEntry(key: "claude_code", value: "Needs input", icon: "bell.fill", timestamp: asked),
                    key: "claude_code",
                    panelId: pane.panelId
                )
                pane.report(.working)
                pane.report(.blocked, kind: .permission)
                #expect(pane.workspace.agentNeedsInput)

                pane.report(.clear)

                #expect(await Self.waitUntil { pane.lifecycle == .idle }, "lifecycle \(String(describing: pane.lifecycle))")
                #expect(!pane.workspace.agentNeedsInput)
                // The journal holds the settlement at the edge: an event from before it, delivered late, does not
                // bring the cancelled prompt's turn back.
                pane.journal(.stateChanged, at: asked, nativeEvent: "PreToolUse", declaredPhase: .running)
                try await Task.sleep(nanoseconds: 200_000_000)
                #expect(pane.lifecycle == .idle)
            }
        }
    }

    /// An answered prompt of a bound session: the journal resolves the wait, so the pane runs again and a later
    /// tool event of the same turn keeps it running instead of bringing the wait back.
    @Test func claudeAnswerReturnsABoundSessionToRunningThroughTheJournal() async throws {
        try await Self.withBoundClaudePane { pane in
            let asked = Date().addingTimeInterval(-10)
            pane.journal(.sessionStarted, at: asked.addingTimeInterval(-2), nativeEvent: "SessionStart")
            pane.journal(.turnStarted, at: asked.addingTimeInterval(-1), nativeEvent: "UserPromptSubmit")
            pane.journal(.questionRequested, at: asked, nativeEvent: "PreToolUse", request: "toolu_question")
            #expect(await Self.waitUntil { pane.lifecycle == .needsInput })
            pane.workspace.setStatusEntry(
                SidebarStatusEntry(key: "claude_code", value: "Needs input", icon: "bell.fill", timestamp: asked),
                key: "claude_code",
                panelId: pane.panelId
            )
            pane.report(.working)
            pane.report(.blocked, kind: .question)

            pane.report(.working)

            #expect(await Self.waitUntil { pane.lifecycle == .running }, "lifecycle \(String(describing: pane.lifecycle))")
            #expect(!pane.workspace.agentNeedsInput)
            // The next tool of the same turn: its PreToolUse asserts running, which a pending wait would turn
            // back into needs input.
            pane.journal(.stateChanged, at: Date(), nativeEvent: "PreToolUse", declaredPhase: .running)
            try await Task.sleep(nanoseconds: 100_000_000)
            #expect(pane.lifecycle == .running)
        }
    }

    /// One terminal the app can find by its panel, as the journal's projection does, with a Claude session
    /// bound to it by its hooks.
    @MainActor
    struct BoundClaudePane {
        let workspace: Workspace
        let panelId: UUID
        let sessionID: String

        /// The pane's Claude lifecycle in the sidebar.
        var lifecycle: AgentHibernationLifecycleState? {
            workspace.agentLifecycleStatesByPanelId[panelId]?["claude_code"]
        }

        /// Journals one Claude hook event for the pane, as `cmux claude-hook` does.
        func journal(
            _ kind: AgentJournalEventKind,
            at date: Date,
            nativeEvent: String,
            request: String? = nil,
            declaredPhase: AgentLifecyclePhase? = nil
        ) {
            AgentJournalLifecycleCenter.shared.enqueueAppend(AgentJournalEventDraft(
                kind: kind,
                occurredAtMs: Int64(date.timeIntervalSince1970 * 1_000),
                source: "claude",
                agentKey: "claude_code",
                sessionId: sessionID,
                workspaceId: workspace.id.uuidString,
                surfaceId: panelId.uuidString,
                nativeEvent: nativeEvent,
                declaredPhase: declaredPhase,
                attention: request.map { AgentAttentionContext(requestIdentity: $0) }
            ))
        }

        /// Claude Code's own OSC 7501 report on the pane.
        func report(_ state: ProgramStatusState, kind: ProgramStatusKind = .none) {
            workspace.applyProgramStatus(
                ProgramStatusReport(state: state, kind: kind, app: state == .clear ? nil : "claude-code"),
                panelId: panelId
            )
        }
    }

    /// Runs `body` with a fresh workspace in the app's tab manager and a Claude session bound to its terminal.
    static func withBoundClaudePane(_ body: (BoundClaudePane) async throws -> Void) async throws {
        let previousApp = AppDelegate.shared
        let app = previousApp ?? AppDelegate()
        let previousManager = app.tabManager
        let manager = TabManager(autoWelcomeIfNeeded: false)
        AppDelegate.shared = app
        app.tabManager = manager
        defer {
            app.tabManager = previousManager
            AppDelegate.shared = previousApp
            manager.finalizeAllWorkspacesForWindowClose()
        }
        let workspace = try #require(manager.selectedWorkspace)
        let panelId = try #require(workspace.focusedPanelId)
        let sessionID = UUID().uuidString
        workspace.surfaceResumeBindingsByPanelId[panelId] = SurfaceResumeBindingSnapshot(
            name: "Claude Code",
            kind: "claude",
            command: "claude --resume \(sessionID)",
            checkpointId: sessionID,
            source: "agent-hook"
        )
        try await body(BoundClaudePane(workspace: workspace, panelId: panelId, sessionID: sessionID))
    }
}
