import CMUXAgentLaunch
import CmuxAgentChat
import CmuxMobileHost
import Foundation
import Testing
import CmuxSidebar

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Serialized: the chat-session settlement tests swap the process-wide `Workspace.agentTurnSettlementWait` and
/// `TerminalController.shared.agentChatTranscriptService`.
@MainActor
@Suite(.serialized)
struct WorkspaceProgramStatusTests {
    @Test func projectsMostUrgentPanelRecord() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        workspace.applyProgramStatus(
            ProgramStatusReport(state: .working, app: "cargo", message: "Building"),
            panelId: panelId
        )
        workspace.applyProgramStatus(
            ProgramStatusReport(state: .blocked, kind: .permission, id: "deploy", message: "Approve?"),
            panelId: panelId
        )
        let entry = try #require(workspace.statusEntries[Workspace.programStatusKey])
        #expect(entry.icon == "bell.fill")
        #expect(entry.value.contains("Approve?"))
        #expect(workspace.programStatusStoresByPanelId[panelId]?.mostUrgentRecord()?.state == .blocked)
    }

    @Test func programStatusIsNotAgentLifecycleState() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        workspace.applyProgramStatus(
            ProgramStatusReport(state: .blocked, kind: .auth, app: "brew"),
            panelId: panelId
        )
        #expect(workspace.agentLifecycleStatesByPanelId[panelId] == nil)
        #expect(workspace.agentRuntimeState(forPanelId: panelId) == nil)
        #expect(workspace.statusEntries[Workspace.programStatusKey]?.value == "brew · Needs sign-in")
    }

    @Test func workingShowsPercentAndPromptDropsTransientRecords() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        workspace.applyProgramStatus(
            ProgramStatusReport(state: .done, id: "lint", app: "cargo", message: "Lint clean"),
            panelId: panelId
        )
        workspace.applyProgramStatus(
            ProgramStatusReport(state: .working, progress: 40, app: "cargo", message: "Building"),
            panelId: panelId
        )
        #expect(workspace.statusEntries[Workspace.programStatusKey]?.value == "cargo · Building · 40%")

        workspace.applyProgramStatus(ProgramStatusReport(event: .promptStart, state: .idle), panelId: panelId)
        let entry = try #require(workspace.statusEntries[Workspace.programStatusKey])
        #expect(entry.icon == "checkmark.circle.fill")
        #expect(entry.value == "cargo · Lint clean")

        workspace.dismissCompletedProgramStatus(panelId: panelId)
        #expect(workspace.statusEntries[Workspace.programStatusKey] == nil)
    }

    @Test func closingPaneRemovesItsProgramStatusRow() throws {
        let workspace = Workspace()
        let firstPanelId = try #require(workspace.focusedPanelId)
        let blockedPanel = try #require(
            workspace.newTerminalSplit(from: firstPanelId, orientation: .horizontal, focus: false)
        )
        workspace.applyProgramStatus(
            ProgramStatusReport(state: .blocked, kind: .permission, app: "terraform"),
            panelId: blockedPanel.id
        )
        #expect(workspace.statusEntries[Workspace.programStatusKey] != nil)

        workspace.discardClosedPanelLifecycleState(
            panelId: blockedPanel.id,
            paneId: nil,
            panel: blockedPanel,
            origin: "program_status_test",
            closePanel: false,
            publishSurfaceClosedEvent: false,
            clearSurfaceNotifications: false,
            requestTransferredRemoteCleanup: false
        )

        #expect(workspace.statusEntries[Workspace.programStatusKey] == nil)
        #expect(workspace.programStatusStoresByPanelId[blockedPanel.id] == nil)
    }

    @Test func promptStartOrClearWithoutRecordsDoesNotCreateState() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        workspace.applyProgramStatus(ProgramStatusReport(event: .promptStart, state: .idle), panelId: panelId)
        #expect(workspace.programStatusStoresByPanelId[panelId] == nil)
        workspace.applyProgramStatus(ProgramStatusReport(state: .clear), panelId: panelId)
        #expect(workspace.programStatusStoresByPanelId[panelId] == nil)
        #expect(workspace.statusEntries[Workspace.programStatusKey] == nil)
    }

    @Test func programStatusChangesReachTheMacEventStream() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        CmuxEventBus.shared.resetForTesting()
        defer { CmuxEventBus.shared.resetForTesting() }

        workspace.applyProgramStatus(
            ProgramStatusReport(state: .done, id: "lint", app: "cargo"),
            panelId: panelId
        )
        workspace.applyProgramStatus(
            ProgramStatusReport(state: .working, id: "build", app: "cargo"),
            panelId: panelId
        )
        workspace.applyProgramStatus(
            ProgramStatusReport(event: .promptStart, state: .idle),
            panelId: panelId
        )
        CmuxEventBus.shared.flushEventLogForTesting()

        let events = CmuxEventBus.shared.retainedSnapshot().filter {
            $0["name"] as? String == "program_status.changed"
        }
        #expect(events.count == 3)
        let promptPayload = try #require(events.last?["payload"] as? [String: Any])
        #expect(promptPayload["event"] as? String == "prompt_start")
        let records = try #require(promptPayload["records"] as? [[String: Any]])
        #expect(records.map { $0["id"] as? String } == ["lint"])
    }

    @Test func programStatusClearReachesTheMacEventStream() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        CmuxEventBus.shared.resetForTesting()
        defer { CmuxEventBus.shared.resetForTesting() }

        workspace.applyProgramStatus(
            ProgramStatusReport(state: .working, id: "build", app: "cargo"),
            panelId: panelId
        )
        workspace.applyProgramStatus(
            ProgramStatusReport(state: .clear, id: "build"),
            panelId: panelId
        )
        CmuxEventBus.shared.flushEventLogForTesting()

        let events = CmuxEventBus.shared.retainedSnapshot().filter {
            $0["name"] as? String == "program_status.changed"
        }
        #expect(events.count == 2)
        let clearPayload = try #require(events.last?["payload"] as? [String: Any])
        #expect(clearPayload["event"] as? String == "clear")
        #expect(clearPayload["id"] as? String == "build")
        #expect(clearPayload["record"] is NSNull)
        let records = try #require(clearPayload["records"] as? [[String: Any]])
        #expect(records.isEmpty)
    }

    @Test func transientCleanupPublishesOnceBeforePromptStartNoOp() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        CmuxEventBus.shared.resetForTesting()
        defer { CmuxEventBus.shared.resetForTesting() }

        workspace.applyProgramStatus(
            ProgramStatusReport(state: .blocked, kind: .permission, id: "deploy"),
            panelId: panelId
        )
        workspace.dropTransientProgramStatus(panelId: panelId)
        // Shell integration can deliver this after prompt-idle cleanup. It is
        // intentionally a no-op because the snapshot was already published.
        workspace.applyProgramStatus(
            ProgramStatusReport(event: .promptStart, state: .idle),
            panelId: panelId
        )
        CmuxEventBus.shared.flushEventLogForTesting()

        let events = CmuxEventBus.shared.retainedSnapshot().filter {
            $0["name"] as? String == "program_status.changed"
        }
        #expect(events.count == 2)
        let cleanupPayload = try #require(events.last?["payload"] as? [String: Any])
        #expect(cleanupPayload["event"] as? String == "transient_drop")
        let records = try #require(cleanupPayload["records"] as? [[String: Any]])
        #expect(records.isEmpty)
    }

    @Test func dismissingCompletedStatusPublishesUpdatedSnapshot() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        CmuxEventBus.shared.resetForTesting()
        defer { CmuxEventBus.shared.resetForTesting() }

        workspace.applyProgramStatus(
            ProgramStatusReport(state: .done, id: "build"),
            panelId: panelId
        )
        workspace.dismissCompletedProgramStatus(panelId: panelId)
        workspace.dismissCompletedProgramStatus(panelId: panelId)
        CmuxEventBus.shared.flushEventLogForTesting()

        let events = CmuxEventBus.shared.retainedSnapshot().filter {
            $0["name"] as? String == "program_status.changed"
        }
        #expect(events.count == 2)
        let dismissedPayload = try #require(events.last?["payload"] as? [String: Any])
        #expect(dismissedPayload["event"] as? String == "dismissed")
        let records = try #require(dismissedPayload["records"] as? [[String: Any]])
        #expect(records.isEmpty)
    }

    @Test func movedPaneKeepsItsProgramStatusRecords() throws {
        let source = Workspace()
        let destination = Workspace()
        let firstPanelId = try #require(source.focusedPanelId)
        let movedPanel = try #require(
            source.newTerminalSplit(from: firstPanelId, orientation: .horizontal, focus: false)
        )
        source.applyProgramStatus(
            ProgramStatusReport(state: .blocked, kind: .question, app: "deploy", message: "Region?"),
            panelId: movedPanel.id
        )

        let detached = try #require(source.detachSurface(panelId: movedPanel.id))
        let destinationPane = try #require(destination.bonsplitController.allPaneIds.first)
        _ = try #require(destination.attachDetachedSurface(detached, inPane: destinationPane, focus: false))

        #expect(source.statusEntries[Workspace.programStatusKey] == nil)
        #expect(destination.programStatusStoresByPanelId[movedPanel.id]?.mostUrgentRecord()?.state == .blocked)
        #expect(destination.statusEntries[Workspace.programStatusKey]?.value == "deploy · Region?")
    }

    @Test func closingTerminalsPublishesRemovedSnapshotOnlyForReportingPanes() throws {
        let workspace = Workspace()
        let reportingPanelId = try #require(workspace.focusedPanelId)
        let quietPanel = try #require(
            workspace.newTerminalSplit(from: reportingPanelId, orientation: .horizontal, focus: false)
        )
        workspace.applyProgramStatus(
            ProgramStatusReport(state: .done, id: "lint", app: "cargo"),
            panelId: reportingPanelId
        )
        CmuxEventBus.shared.resetForTesting()
        defer { CmuxEventBus.shared.resetForTesting() }

        workspace.teardownAllPanels()
        CmuxEventBus.shared.flushEventLogForTesting()

        let events = CmuxEventBus.shared.retainedSnapshot().filter {
            $0["name"] as? String == "program_status.changed"
        }
        #expect(events.count == 1)
        let removed = try #require(events.first)
        #expect(removed["workspace_id"] as? String == workspace.id.uuidString)
        #expect(removed["surface_id"] as? String == reportingPanelId.uuidString)
        #expect(removed["surface_id"] as? String != quietPanel.id.uuidString)
        let payload = try #require(removed["payload"] as? [String: Any])
        #expect(payload["event"] as? String == "removed")
        #expect(payload["record"] is NSNull)
        #expect(payload["records_total"] as? Int == 0)
        let records = try #require(payload["records"] as? [[String: Any]])
        #expect(records.isEmpty)
    }

    @Test func movedPanePublishesRemovalAndAdoptionUnderEachWorkspace() throws {
        let source = Workspace()
        let destination = Workspace()
        let firstPanelId = try #require(source.focusedPanelId)
        let movedPanel = try #require(
            source.newTerminalSplit(from: firstPanelId, orientation: .horizontal, focus: false)
        )
        source.applyProgramStatus(
            ProgramStatusReport(state: .blocked, kind: .question, id: "deploy", app: "deploy"),
            panelId: movedPanel.id
        )
        CmuxEventBus.shared.resetForTesting()
        defer { CmuxEventBus.shared.resetForTesting() }

        let detached = try #require(source.detachSurface(panelId: movedPanel.id))
        let destinationPane = try #require(destination.bonsplitController.allPaneIds.first)
        _ = try #require(destination.attachDetachedSurface(detached, inPane: destinationPane, focus: false))
        CmuxEventBus.shared.flushEventLogForTesting()

        let events = CmuxEventBus.shared.retainedSnapshot().filter {
            $0["name"] as? String == "program_status.changed"
        }
        #expect(events.count == 2)
        let removed = try #require(events.first)
        #expect(removed["workspace_id"] as? String == source.id.uuidString)
        #expect(removed["surface_id"] as? String == movedPanel.id.uuidString)
        let removedPayload = try #require(removed["payload"] as? [String: Any])
        #expect(removedPayload["event"] as? String == "removed")
        #expect((removedPayload["records"] as? [[String: Any]])?.isEmpty == true)

        let adopted = try #require(events.last)
        #expect(adopted["workspace_id"] as? String == destination.id.uuidString)
        #expect(adopted["surface_id"] as? String == movedPanel.id.uuidString)
        let adoptedPayload = try #require(adopted["payload"] as? [String: Any])
        #expect(adoptedPayload["event"] as? String == "adopted")
        #expect(adoptedPayload["record"] is NSNull)
        let records = try #require(adoptedPayload["records"] as? [[String: Any]])
        #expect(records.map { $0["id"] as? String } == ["deploy"])
        #expect(records.first?["state"] as? String == "blocked")
        #expect(records.first?["kind"] as? String == "question")
    }

    @Test func sidebarResetPublishesClearForReportingPanes() throws {
        let workspace = Workspace()
        let reportingPanelId = try #require(workspace.focusedPanelId)
        _ = try #require(
            workspace.newTerminalSplit(from: reportingPanelId, orientation: .horizontal, focus: false)
        )
        workspace.applyProgramStatus(
            ProgramStatusReport(state: .working, id: "build", app: "cargo"),
            panelId: reportingPanelId
        )
        CmuxEventBus.shared.resetForTesting()
        defer { CmuxEventBus.shared.resetForTesting() }

        workspace.resetSidebarContext(reason: "test")
        CmuxEventBus.shared.flushEventLogForTesting()

        let events = CmuxEventBus.shared.retainedSnapshot().filter {
            $0["name"] as? String == "program_status.changed"
        }
        #expect(events.count == 1)
        let cleared = try #require(events.first)
        #expect(cleared["workspace_id"] as? String == workspace.id.uuidString)
        #expect(cleared["surface_id"] as? String == reportingPanelId.uuidString)
        let payload = try #require(cleared["payload"] as? [String: Any])
        #expect(payload["event"] as? String == "clear")
        #expect(payload["id"] is NSNull)
        let records = try #require(payload["records"] as? [[String: Any]])
        #expect(records.isEmpty)
        #expect(workspace.programStatusStoresByPanelId.isEmpty)
    }

    /// Claude Code runs no Stop hook when the user stops a turn with Esc, and its process waits at the prompt,
    /// so the phone's chat session stayed working for days ("Running · 52 hours"). Its OSC 7501 working record
    /// ending settles the pane after the grace, and the same settlement settles the chat session on that terminal.
    @Test func claudeEscSettlesTheChatSessionOnItsTerminal() async throws {
        try await withChatService { service in
            let workspace = Workspace()
            let panelId = try #require(workspace.focusedPanelId)
            let session = UUID().uuidString
            let prompted = Date().addingTimeInterval(-10)
            service.noteHookEvent(WorkstreamEvent(
                sessionId: session, hookEventName: .userPromptSubmit, source: "claude",
                surfaceId: panelId.uuidString, receivedAt: prompted
            ))
            // The prompt hook's sidebar row.
            workspace.setAgentLifecycle(key: "claude_code", panelId: panelId, lifecycle: .running)
            workspace.setStatusEntry(
                SidebarStatusEntry(key: "claude_code", value: "Running", timestamp: prompted, workState: .running),
                key: "claude_code",
                panelId: panelId
            )
            workspace.applyProgramStatus(ProgramStatusReport(state: .working, app: "claude-code"), panelId: panelId)

            // Esc: Claude Code clears its working record and runs no Stop hook.
            workspace.applyProgramStatus(ProgramStatusReport(state: .clear), panelId: panelId)

            #expect(await Self.waitUntil { workspace.agentLifecycleStatesByPanelId[panelId]?["claude_code"] == .idle })
            #expect(await Self.waitUntil { service.sessionRecord(sessionID: session)?.state == .idle })
            #expect(service.sessionRecord(sessionID: session)?.hasHookLifecycleState == true)
        }
    }

    /// Esc on a Claude permission prompt: the typed key moved the chat session from needs-input to working, and
    /// Claude's blocked record ends with no hook. The chat session settles although the pane's row is not a
    /// hook-reported Running row.
    @Test func claudeEscOnPermissionPromptSettlesTheChatSession() async throws {
        try await withChatService { service in
            let workspace = Workspace()
            let panelId = try #require(workspace.focusedPanelId)
            let session = UUID().uuidString
            service.noteHookEvent(WorkstreamEvent(
                sessionId: session, hookEventName: .permissionRequest, source: "claude",
                surfaceId: panelId.uuidString, receivedAt: Date().addingTimeInterval(-10)
            ))
            workspace.setAgentLifecycle(key: "claude_code", panelId: panelId, lifecycle: .needsInput)
            workspace.applyProgramStatus(
                ProgramStatusReport(state: .blocked, kind: .permission, app: "claude-code"),
                panelId: panelId
            )
            // The Esc key is explicit input on the terminal before Claude reacts to it.
            #expect(service.noteExplicitInput(surfaceID: panelId.uuidString) == 1)

            workspace.applyProgramStatus(ProgramStatusReport(state: .clear), panelId: panelId)

            #expect(await Self.waitUntil { service.sessionRecord(sessionID: session)?.state == .idle })
        }
    }

    /// Esc during a foreground Task/Agent subagent or a blocking wait tool (`sleep N`, `gh run watch`, Monitor):
    /// Claude's PreToolUse left the pane's row at "Running subagents" or "Waiting", and no hook runs after the Esc.
    /// The row's background-work state does not keep the chat session working.
    @Test func claudeEscDuringASubagentOrWaitToolSettlesTheChatSession() async throws {
        for (tool, workState) in [("Task", SidebarAgentWorkState.subagents), ("Bash", .waiting)] {
            try await withChatService { service in
                let workspace = Workspace()
                let panelId = try #require(workspace.focusedPanelId)
                let session = UUID().uuidString
                let calledTool = Date().addingTimeInterval(-10)
                service.noteHookEvent(WorkstreamEvent(
                    sessionId: session, hookEventName: .userPromptSubmit, source: "claude",
                    surfaceId: panelId.uuidString, receivedAt: calledTool.addingTimeInterval(-1)
                ))
                service.noteHookEvent(WorkstreamEvent(
                    sessionId: session, hookEventName: .preToolUse, source: "claude",
                    surfaceId: panelId.uuidString, toolName: tool, receivedAt: calledTool
                ))
                // The PreToolUse hook's sidebar row.
                workspace.setAgentLifecycle(key: "claude_code", panelId: panelId, lifecycle: .running)
                workspace.setStatusEntry(
                    SidebarStatusEntry(key: "claude_code", value: "Busy", timestamp: calledTool, workState: workState),
                    key: "claude_code",
                    panelId: panelId
                )
                workspace.applyProgramStatus(ProgramStatusReport(state: .working, app: "claude-code"), panelId: panelId)

                workspace.applyProgramStatus(ProgramStatusReport(state: .clear), panelId: panelId)

                #expect(
                    await Self.waitUntil { service.sessionRecord(sessionID: session)?.state == .idle },
                    "Esc during \(tool) left the chat session \(String(describing: service.sessionRecord(sessionID: session)?.state))"
                )
                // The row stays as it is: Subagents or Waiting can also be a turn that ended with background
                // work still live, which the edge cannot tell apart from an Esc. The next hook settles it.
                #expect(workspace.agentLifecycleStatesByPanelId[panelId]?["claude_code"] == .running)
                let row = workspace.agentStatusEntriesByPanelId[panelId]?["claude_code"]
                #expect(row?.value == "Busy")
                #expect(row?.workState == workState)
            }
        }
    }

    /// Esc on a Claude permission prompt or question: Claude keeps its OSC 7501 record blocked while the prompt
    /// waits, and only cancelling it ends the record, with no hook. The pane's "Needs input" row and lifecycle
    /// settle to idle at that edge, so the status pill and the waiting border stop (spec 2026-10-29 §6.7).
    @Test func claudeEscOnPermissionPromptIdlesTheSidebarRow() async throws {
        try await withChatService { service in
            let workspace = Workspace()
            let panelId = try #require(workspace.focusedPanelId)
            let session = UUID().uuidString
            let asked = Date().addingTimeInterval(-10)
            service.noteHookEvent(WorkstreamEvent(
                sessionId: session, hookEventName: .permissionRequest, source: "claude",
                surfaceId: panelId.uuidString, receivedAt: asked
            ))
            // The Notification hook's sidebar row for the prompt.
            workspace.setAgentLifecycle(key: "claude_code", panelId: panelId, lifecycle: .needsInput)
            workspace.setStatusEntry(
                SidebarStatusEntry(key: "claude_code", value: "Needs input", icon: "bell.fill", timestamp: asked),
                key: "claude_code",
                panelId: panelId
            )
            workspace.applyProgramStatus(ProgramStatusReport(state: .working, app: "claude-code"), panelId: panelId)
            workspace.applyProgramStatus(
                ProgramStatusReport(state: .blocked, kind: .permission, app: "claude-code"),
                panelId: panelId
            )
            #expect(workspace.agentNeedsInput)

            workspace.applyProgramStatus(ProgramStatusReport(state: .clear), panelId: panelId)

            #expect(await Self.waitUntil { workspace.agentLifecycleStatesByPanelId[panelId]?["claude_code"] == .idle })
            #expect(!workspace.agentNeedsInput)
            #expect(workspace.agentStatusEntriesByPanelId[panelId]?["claude_code"]?.value != "Needs input")
        }
    }

    /// A turn that failed (`StopFailure`) also ends Claude's record, and the journal shows its error as needs
    /// input. That row is an error, not a prompt the person cancelled: the edge leaves it as it is.
    @Test func claudeFailureKeepsItsSidebarRowWhenItsRecordEnds() async throws {
        try await withChatService { service in
            let workspace = Workspace()
            let panelId = try #require(workspace.focusedPanelId)
            let session = UUID().uuidString
            let failed = Date().addingTimeInterval(-10)
            service.noteHookEvent(WorkstreamEvent(
                sessionId: session, hookEventName: .userPromptSubmit, source: "claude",
                surfaceId: panelId.uuidString, receivedAt: failed.addingTimeInterval(-5)
            ))
            workspace.setAgentLifecycle(key: "claude_code", panelId: panelId, lifecycle: .needsInput)
            workspace.setStatusEntry(
                SidebarStatusEntry(
                    key: "claude_code",
                    value: "Usage limit",
                    icon: "exclamationmark.triangle.fill",
                    color: "#FF453A",
                    timestamp: failed
                ),
                key: "claude_code",
                panelId: panelId
            )
            workspace.applyProgramStatus(ProgramStatusReport(state: .working, app: "claude-code"), panelId: panelId)

            workspace.applyProgramStatus(ProgramStatusReport(state: .error, app: "claude-code"), panelId: panelId)

            // The settlement ran: it settles the chat session before it looks at the row.
            #expect(await Self.waitUntil { service.sessionRecord(sessionID: session)?.state == .idle })
            #expect(workspace.agentLifecycleStatesByPanelId[panelId]?["claude_code"] == .needsInput)
            #expect(workspace.agentStatusEntriesByPanelId[panelId]?["claude_code"]?.value == "Usage limit")
        }
    }

    /// A permission prompt that still waits keeps Claude's record blocked: nothing ends, so even with no grace
    /// the pane's Needs input row, the waiting border and the chat session all keep waiting.
    @Test func claudeLivePromptKeepsItsRowAndChatSessionWaiting() async throws {
        try await withChatService { service in
            let workspace = Workspace()
            let panelId = try #require(workspace.focusedPanelId)
            let session = UUID().uuidString
            let asked = Date().addingTimeInterval(-10)
            service.noteHookEvent(WorkstreamEvent(
                sessionId: session, hookEventName: .permissionRequest, source: "claude",
                surfaceId: panelId.uuidString, receivedAt: asked
            ))
            workspace.setAgentLifecycle(key: "claude_code", panelId: panelId, lifecycle: .needsInput)
            workspace.setStatusEntry(
                SidebarStatusEntry(key: "claude_code", value: "Needs input", icon: "bell.fill", timestamp: asked),
                key: "claude_code",
                panelId: panelId
            )

            workspace.applyProgramStatus(ProgramStatusReport(state: .working, app: "claude-code"), panelId: panelId)
            workspace.applyProgramStatus(
                ProgramStatusReport(state: .blocked, kind: .permission, app: "claude-code"),
                panelId: panelId
            )
            // The grace is skipped: any settlement the reports scheduled has run by now.
            try await Task.sleep(nanoseconds: 100_000_000)

            #expect(workspace.agentTurnSettlementTasks.isEmpty)
            #expect(workspace.agentLifecycleStatesByPanelId[panelId]?["claude_code"] == .needsInput)
            #expect(workspace.agentNeedsInput)
            #expect(workspace.agentStatusEntriesByPanelId[panelId]?["claude_code"]?.value == "Needs input")
            #expect(service.sessionRecord(sessionID: session)?.state == .needsInput(since: asked))
        }
    }

    /// Claude keeps its record blocked while a permission prompt or a question waits, and reports working again
    /// once the person answers, often long before the next hook: an AskUserQuestion or ExitPlanMode under
    /// bypassPermissions has none until the next tool, an approved tool none until it ends. The pane's Needs
    /// input row returns to Running at that edge, so the waiting border stops while the agent goes on.
    @Test func claudeAnswerReturnsTheNeedsInputRowToRunning() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        let asked = Date().addingTimeInterval(-10)
        // The PreToolUse hook's sidebar row for an AskUserQuestion under bypassPermissions.
        workspace.setAgentLifecycle(key: "claude_code", panelId: panelId, lifecycle: .needsInput)
        workspace.setStatusEntry(
            SidebarStatusEntry(key: "claude_code", value: "Needs input", icon: "bell.fill", timestamp: asked),
            key: "claude_code",
            panelId: panelId
        )
        workspace.applyProgramStatus(ProgramStatusReport(state: .working, app: "claude-code"), panelId: panelId)

        workspace.applyProgramStatus(
            ProgramStatusReport(state: .blocked, kind: .question, app: "claude-code"),
            panelId: panelId
        )
        // working → blocked: the question waits.
        #expect(workspace.agentLifecycleStatesByPanelId[panelId]?["claude_code"] == .needsInput)
        #expect(workspace.agentNeedsInput)

        // blocked → working: the person answered.
        workspace.applyProgramStatus(ProgramStatusReport(state: .working, app: "claude-code"), panelId: panelId)

        #expect(workspace.agentLifecycleStatesByPanelId[panelId]?["claude_code"] == .running)
        #expect(!workspace.agentNeedsInput)
        let row = try #require(workspace.agentStatusEntriesByPanelId[panelId]?["claude_code"])
        #expect(row.workState == .running)
        #expect(row.icon == "bolt.fill")
        #expect(row.timestamp > asked)
    }

    /// The journal shows a failed turn as needs input with the error triangle. Claude reporting working again
    /// does not answer a failure: its row stays.
    @Test func claudeAnswerLeavesAFailureRowAsItIs() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        workspace.setAgentLifecycle(key: "claude_code", panelId: panelId, lifecycle: .needsInput)
        workspace.setStatusEntry(
            SidebarStatusEntry(
                key: "claude_code",
                value: "Usage limit",
                icon: "exclamationmark.triangle.fill",
                color: "#FF453A",
                timestamp: Date().addingTimeInterval(-10)
            ),
            key: "claude_code",
            panelId: panelId
        )

        workspace.applyProgramStatus(
            ProgramStatusReport(state: .blocked, kind: .permission, app: "claude-code"),
            panelId: panelId
        )
        workspace.applyProgramStatus(ProgramStatusReport(state: .working, app: "claude-code"), panelId: panelId)

        #expect(workspace.agentLifecycleStatesByPanelId[panelId]?["claude_code"] == .needsInput)
        #expect(workspace.agentStatusEntriesByPanelId[panelId]?["claude_code"]?.value == "Usage limit")
    }

    /// Runs `body` with a private agent chat service as the app's, and the settlement grace skipped.
    func withChatService(_ body: (AgentChatTranscriptService) async throws -> Void) async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("program-status-chat-\(UUID().uuidString)", isDirectory: true)
        let previousService = TerminalController.shared.agentChatTranscriptService
        let previousWait = Workspace.agentTurnSettlementWait
        let service = AgentChatTranscriptService(
            registry: AgentChatSessionRegistry(hookStore: AgentChatHookSessionStore(homeDirectory: home)),
            resolver: AgentChatTranscriptResolver(homeDirectory: home, environment: [:]),
            hasEventSubscribers: { false },
            emitEventPayload: { _ in }
        )
        TerminalController.shared.agentChatTranscriptService = service
        Workspace.agentTurnSettlementWait = { _ in }
        defer {
            TerminalController.shared.agentChatTranscriptService = previousService
            Workspace.agentTurnSettlementWait = previousWait
            try? FileManager.default.removeItem(at: home)
        }
        try await body(service)
    }

    static func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<300 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    @Test func sanitizesInvisibleFormattingAndCapsDisplay() {
        let workspace = Workspace()
        let value = workspace.sanitizedProgramStatusText("hello\u{202E}world")
        #expect(value == "helloworld")
        #expect(workspace.sanitizedProgramStatusText(String(repeating: "x", count: 600))?.count == 512)
    }
}
