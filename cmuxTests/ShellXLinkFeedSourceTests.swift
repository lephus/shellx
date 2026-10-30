import CMUXAgentLaunch
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

/// ShellX Link's `AgentFeedSource` over the app's Feed: what a phone sees and what its replies do.
/// Each test installs a fresh store on the shared coordinator, like `FeedCoordinatorTests`.
@Suite("ShellX Link feed source", .serialized, .timeLimit(.minutes(1)))
struct ShellXLinkFeedSourceTests {
    private static let workspace = (id: "11111111-2222-3333-4444-555555555555", title: "shellx")

    /// A fresh store and a source whose workspace lookup needs no live window.
    @MainActor
    private static func makeSource(
        workspaceLookup: @escaping ShellXLinkFeedSource.WorkspaceLookup = { _ in workspace }
    ) -> (WorkstreamStore, ShellXLinkFeedSource) {
        let store = WorkstreamStore(ringCapacity: 50)
        FeedCoordinator.shared.install(store: store)
        let source = ShellXLinkFeedSource(coordinator: .shared, workspaceLookup: workspaceLookup)
        return (store, source)
    }

    private static func permission(_ requestId: String, toolInputJSON: String = #"{"command":"git status"}"#,
                                   source: String = "claude", sessionId: String? = nil) -> WorkstreamEvent {
        WorkstreamEvent(
            sessionId: sessionId ?? "link-\(requestId)",
            hookEventName: .permissionRequest,
            source: source,
            cwd: "/tmp/shellx",
            toolName: "Bash",
            toolInputJSON: toolInputJSON,
            requestId: requestId
        )
    }

    /// Runs a blocking hook (`feed.push` with a wait) on a socket-like worker thread.
    private static func startBlockingHook(_ event: WorkstreamEvent, timeout: TimeInterval = 5) -> BlockingHook {
        let hook = BlockingHook()
        DispatchQueue.global(qos: .userInitiated).async {
            hook.finish(FeedCoordinator.shared.ingestBlocking(event: event, waitTimeout: timeout))
        }
        return hook
    }

    @MainActor
    private static func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    private static func resetHooks() {
        let reset: @Sendable () -> Void = {
            MainActor.assumeIsolated { FeedCoordinatorTestHooks.mobileFeedChangedObserver = nil }
        }
        if Thread.isMainThread { reset() } else { DispatchQueue.main.sync(execute: reset) }
    }

    @Test func testSnapshotListsPendingPermission() async {
        let (store, source) = await MainActor.run { Self.makeSource() }
        await MainActor.run {
            store.ingest(Self.permission("snap-pending"))
            store.ingest(WorkstreamEvent(sessionId: "link-telemetry", hookEventName: .preToolUse, source: "claude",
                                         toolName: "Read", toolInputJSON: "{}"))
            store.ingest(Self.permission("snap-resolved"))
            if let resolved = store.items.first(where: { $0.payload.requestID == "snap-resolved" }) {
                store.markResolved(resolved.id, decision: .permission(.deny))
            }
        }

        let snapshot = await source.snapshot()

        #expect(snapshot.pending.map(\.requestId) == ["snap-pending"])
        let item = snapshot.pending.first
        #expect(item?.kind == .permission)
        #expect(item?.agent == "claude")
        #expect(item?.toolName == "Bash")
        #expect(item?.toolInputPreview == #"{"command":"git status"}"#)
        #expect(item?.workspaceId == Self.workspace.id)
        #expect(item?.workspaceTitle == Self.workspace.title)
        #expect((item?.createdAtMs ?? 0) > 0)
        // Exactly what the Feed panel offers Claude Code, in wire order, and never `bypass`.
        #expect(item?.modes == ["once", "always", "all", "deny"])
    }

    @Test func testChangesEmitsAddedThenResolved() async throws {
        let (store, source) = await MainActor.run { Self.makeSource() }
        let base = await source.snapshot().revision
        var changes = source.changes().makeAsyncIterator()
        // The subscription registers on the main actor; a snapshot hop orders it before the ingest.
        _ = await source.snapshot()

        let hook = Self.startBlockingHook(Self.permission("changes-1"))
        let added = try #require(await changes.next())
        #expect(added.revision == base + 1)
        #expect(added.added.map(\.requestId) == ["changes-1"])
        #expect(added.resolved.isEmpty)

        FeedCoordinator.shared.deliverReply(requestId: "changes-1", decision: .permission(.once))
        let resolved = try #require(await changes.next())
        #expect(resolved.revision == base + 2)
        #expect(resolved.added.isEmpty)
        #expect(resolved.resolved == ["changes-1"])
        #expect(hook.wait())
        _ = store
    }

    @Test func testReplyAfterMacResolvedIsAlreadyHandled() async {
        let (store, source) = await MainActor.run { Self.makeSource() }
        let hook = Self.startBlockingHook(Self.permission("mac-first"))
        #expect(await Self.waitUntil { store.pending.contains { $0.payload.requestID == "mac-first" } })

        // The Mac decides first (Feed panel, notification or `feed.permission.reply`).
        FeedCoordinator.shared.deliverReply(requestId: "mac-first", decision: .permission(.deny))
        #expect(hook.wait())

        let outcome = await source.reply(requestId: "mac-first", decision: .permission(.always))

        #expect(outcome == .alreadyHandled)
        guard case .resolved(_, .permission(.deny))? = hook.result else {
            Issue.record("the hook must get the Mac's decision, once: \(String(describing: hook.result))")
            return
        }
        let status = await MainActor.run { store.items.first { $0.payload.requestID == "mac-first" }?.status }
        guard case .resolved(.permission(.deny), _)? = status else {
            Issue.record("the phone's late reply must not change the decision: \(String(describing: status))")
            return
        }
    }

    @Test func testReplyDeliversToTheWaitingHook() async {
        let (store, source) = await MainActor.run { Self.makeSource() }
        let hook = Self.startBlockingHook(Self.permission("phone-first"))
        #expect(await Self.waitUntil { store.pending.contains { $0.payload.requestID == "phone-first" } })

        #expect(await source.reply(requestId: "phone-first", decision: .permission(.once)) == .delivered)
        #expect(hook.wait())
        guard case .resolved(_, .permission(.once))? = hook.result else {
            Issue.record("the hook must get the phone's decision: \(String(describing: hook.result))")
            return
        }
        // A resend is answered, never resolved again.
        #expect(await source.reply(requestId: "phone-first", decision: .permission(.deny)) == .alreadyHandled)
    }

    @Test func testReplyToUnknownRequestIsUnknown() async {
        let (_, source) = await MainActor.run { Self.makeSource() }
        #expect(await source.reply(requestId: "never-seen", decision: .permission(.once)) == .unknown)
    }

    @Test func testNonPermissionAndUnknownDecisionsAreUnknown() async {
        let (store, source) = await MainActor.run { Self.makeSource() }
        let hook = Self.startBlockingHook(Self.permission("kind-mismatch"))
        #expect(await Self.waitUntil { store.pending.contains { $0.payload.requestID == "kind-mismatch" } })

        #expect(await source.reply(requestId: "kind-mismatch", decision: .question(selections: ["A"])) == .unknown)
        #expect(await source.reply(requestId: "kind-mismatch", decision: .exitPlan(.manual, feedback: nil)) == .unknown)
        #expect(await source.reply(requestId: "kind-mismatch", decision: .other(kind: "teleport")) == .unknown)
        // `bypass` is never accepted over Link, and an unknown mode is not a permission mode.
        #expect(await source.reply(requestId: "kind-mismatch", decision: .permission(.other("bypass"))) == .unknown)
        let stillPending = await MainActor.run { store.pending.contains { $0.payload.requestID == "kind-mismatch" } }
        #expect(stillPending)
        // Release the blocked hook so it does not outlive the test.
        FeedCoordinator.shared.deliverReply(requestId: "kind-mismatch", decision: .permission(.deny))
        #expect(hook.wait())
    }

    @Test func testToolInputPreviewTruncated() async throws {
        let (store, source) = await MainActor.run { Self.makeSource() }
        // 2 MB of 3-byte characters after one ASCII byte: 8192 falls inside a character.
        let huge = "x" + String(repeating: "€", count: 700_000)
        await MainActor.run { store.ingest(Self.permission("huge-1", toolInputJSON: huge)) }

        let preview = try #require(await source.snapshot().pending.first?.toolInputPreview)

        #expect(preview.utf8.count <= PendingItem.maxPreviewBytes)
        #expect(preview.utf8.count > PendingItem.maxPreviewBytes - 3)
        #expect(huge.hasPrefix(preview))
        #expect(String(bytes: Array(preview.utf8), encoding: .utf8) == preview)
    }

    @Test func testLegacyFeedChangedHandlerStillFires() async throws {
        defer { Self.resetHooks() }
        let legacy = RevisionRecorder()
        let (store, source) = await MainActor.run { Self.makeSource() }
        await MainActor.run { FeedCoordinatorTestHooks.mobileFeedChangedObserver = { legacy.record($0) } }
        var changes = source.changes().makeAsyncIterator()
        _ = await source.snapshot()

        await MainActor.run { store.ingest(Self.permission("legacy-1")) }

        let change = try #require(await changes.next())
        #expect(change.added.map(\.requestId) == ["legacy-1"])
        let expected = await MainActor.run {
            FeedCoordinator.combinedMobileFeedRevision(
                workstream: store.revision,
                notifications: TerminalNotificationStore.shared.notificationFeedHistory.revision
            )
        }
        #expect(legacy.values.last == expected)
    }

    @Test func testEndedSubscriberIsDropped() async {
        let (store, source) = await MainActor.run { Self.makeSource() }
        let observersBefore = await MainActor.run { FeedCoordinator.shared.revisionObserverCount }
        let first = Task { () -> Int in
            var count = 0
            for await _ in source.changes() { count += 1 }
            return count
        }
        _ = await source.snapshot()
        #expect(await MainActor.run { source.subscriberCount } == 1)
        #expect(await MainActor.run { FeedCoordinator.shared.revisionObserverCount } == observersBefore + 1)
        first.cancel()
        _ = await first.value
        #expect(await Self.waitUntil { source.subscriberCount == 0 })
        // The last subscriber gone, the Feed no longer calls back into the source.
        #expect(await Self.waitUntil { FeedCoordinator.shared.revisionObserverCount == observersBefore })
        // Nothing is yielded to the ended stream, and nobody deadlocks.
        await MainActor.run { store.ingest(Self.permission("after-cancel")) }
        #expect(await source.snapshot().pending.map(\.requestId) == ["after-cancel"])
    }
}

extension ShellXLinkFeedSourceTests {
    /// A pending card with no hook waiting (restored from the Feed log after a relaunch, or pushed without
    /// a wait): nothing would receive the phone's decision. The phone hears `already_handled`, and the card
    /// expires instead of recording a decision no agent got, so it leaves every phone's pending set.
    @Test func testReplyWithoutWaiterIsAlreadyHandled() async throws {
        let (store, source) = await MainActor.run { Self.makeSource() }
        let seen = ChangeRecorder()
        let stream = source.changes()
        let consumer = Task { for await change in stream { seen.record(change) } }
        defer { consumer.cancel() }
        // The subscription registers on the main actor; a snapshot hop orders it before the ingest.
        _ = await source.snapshot()
        await MainActor.run { store.ingest(Self.permission("orphan-1")) }
        #expect(await Self.waitUntil { seen.added.contains("orphan-1") })
        let addedRevision = try #require(seen.changes.last?.revision)

        // One main-actor turn: the reply, then the state it left before any other code ran.
        let (outcome, statusAtReturn) = await MainActor.run { () -> (ReplyOutcome, WorkstreamStatus?) in
            let outcome = source.resolveReply(requestId: "orphan-1", decision: .permission(.deny))
            return (outcome, store.items.first { $0.payload.requestID == "orphan-1" }?.status)
        }

        #expect(outcome == .alreadyHandled)
        guard case .expired? = statusAtReturn else {
            Issue.record("no agent received a decision, so the card must expire: \(String(describing: statusAtReturn))")
            return
        }
        // Published by the reply itself: no snapshot runs before the phone hears the card left.
        #expect(await Self.waitUntil { seen.resolved.contains("orphan-1") })
        let change = seen.changes.first { $0.resolved.contains("orphan-1") }
        #expect(change?.revision == addedRevision + 1)
        #expect(change?.added.isEmpty == true)
        #expect(await source.snapshot().pending.map(\.requestId).contains("orphan-1") == false)
        // A resend is answered and changes nothing.
        #expect(await source.reply(requestId: "orphan-1", decision: .permission(.once)) == .alreadyHandled)
        let status = await MainActor.run { store.items.first { $0.payload.requestID == "orphan-1" }?.status }
        guard case .expired? = status else {
            Issue.record("a resend must not resolve the expired card: \(String(describing: status))")
            return
        }
    }

    /// Another entry point (`feed.permission.reply` on a socket thread, a notification action) wins the
    /// waiter while the main actor is busy, so its store update is still queued when the phone's reply runs.
    @Test func testLosingReplyKeepsTheWinnersDecision() async {
        let (store, source) = await MainActor.run { Self.makeSource() }
        let hook = Self.startBlockingHook(Self.permission("race-1"))
        #expect(await Self.waitUntil { store.pending.contains { $0.payload.requestID == "race-1" } })

        let (phone, lateMacReply) = await MainActor.run { () -> (ReplyOutcome, Bool) in
            let winnerReturned = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                FeedCoordinator.shared.deliverReply(requestId: "race-1", decision: .permission(.deny))
                winnerReturned.signal()
            }
            _ = winnerReturned.wait(timeout: .now() + 5)
            return (
                source.resolveReply(requestId: "race-1", decision: .permission(.once)),
                FeedCoordinator.shared.deliverReply(requestId: "race-1", decision: .permission(.always))
            )
        }

        #expect(phone == .alreadyHandled)
        #expect(lateMacReply == false)
        #expect(hook.wait())
        guard case .resolved(_, .permission(.deny))? = hook.result else {
            Issue.record("the hook must get the winner's decision: \(String(describing: hook.result))")
            return
        }
        let recordsWinner = await Self.waitUntil {
            guard case .resolved(.permission(.deny), _)? = store.items.first(where: {
                $0.payload.requestID == "race-1"
            })?.status else { return false }
            return true
        }
        #expect(recordsWinner, "the store must record the decision the hook received")
    }

    /// Workspace lookup reads hook-session files; it runs once per workstream, not once per request.
    @Test func testWorkspaceLookupIsCachedPerWorkstream() async {
        let lookups = RevisionRecorder()
        let (store, source) = await MainActor.run {
            Self.makeSource(workspaceLookup: { _ in
                lookups.record(1)
                return Self.workspace
            })
        }
        await MainActor.run {
            store.ingest(Self.permission("same-ws-1", sessionId: "link-shared-session"))
            store.ingest(Self.permission("same-ws-2", sessionId: "link-shared-session"))
        }

        let pending = await source.snapshot().pending

        #expect(pending.map(\.requestId) == ["same-ws-1", "same-ws-2"])
        #expect(pending.allSatisfy { $0.workspaceTitle == Self.workspace.title })
        #expect(lookups.values.count == 1)
    }
}

// MARK: - Questions, plans and the Claude-only rule (Task 10)

extension ShellXLinkFeedSourceTests {
    private static let questionJSON = #"""
    {"questions":[
      {"id":"q-db","header":"Database","question":"Which database?","multiSelect":false,
       "options":[{"id":"pg","label":"Postgres","description":"Server"},{"id":"lite","label":"SQLite"}]},
      {"id":"q-goals","question":"What matters?","multiSelect":true,
       "options":[{"id":"fast","label":"Fast"},{"id":"cheap","label":"Cheap"}]}
    ]}
    """#

    private static func question(_ requestId: String, toolInputJSON: String = questionJSON,
                                 source: String = "claude") -> WorkstreamEvent {
        WorkstreamEvent(sessionId: "link-\(requestId)", hookEventName: .askUserQuestion, source: source,
                        cwd: "/tmp/shellx", toolName: "AskUserQuestion", toolInputJSON: toolInputJSON,
                        requestId: requestId)
    }

    private static func exitPlan(_ requestId: String, plan: String = "1. Split step 2") -> WorkstreamEvent {
        let json = String(data: try! JSONSerialization.data(withJSONObject: ["plan": plan]), encoding: .utf8)!
        return WorkstreamEvent(sessionId: "link-\(requestId)", hookEventName: .exitPlanMode, source: "claude",
                               cwd: "/tmp/shellx", toolName: "ExitPlanMode", toolInputJSON: json,
                               requestId: requestId)
    }

    /// Releases a blocked hook so it does not outlive the test.
    private static func release(_ requestId: String, _ hook: BlockingHook) {
        FeedCoordinator.shared.deliverReply(requestId: requestId, decision: .permission(.deny))
        _ = hook.wait()
    }

    /// v1 phones answer Claude Code only: another agent's card never reaches a phone, and a reply to it is
    /// a request the phone never saw.
    @Test func testOnlyClaudeItemsArePending() async {
        let (store, source) = await MainActor.run { Self.makeSource() }
        await MainActor.run {
            store.ingest(Self.permission("only-claude", source: "claude"))
            store.ingest(Self.permission("only-codex", source: "codex"))
            store.ingest(Self.permission("only-hermes", source: "hermes-agent"))
            // An unregistered agent is stored as `.claude` with its raw id in `sourceID`.
            store.ingest(Self.permission("only-custom", source: "my-agent"))
            store.ingest(Self.question("only-codex-question", source: "codex"))
        }

        let pending = await source.snapshot().pending

        #expect(pending.map(\.requestId) == ["only-claude"])
        #expect(pending.allSatisfy { $0.agent == "claude" })
        for requestId in ["only-codex", "only-custom"] {
            #expect(await source.reply(requestId: requestId, decision: .permission(.deny)) == .unknown)
        }
        let stillPending = await MainActor.run {
            ["only-codex", "only-custom"].allSatisfy { id in store.pending.contains { $0.payload.requestID == id } }
        }
        #expect(stillPending)
    }

    @Test func testQuestionItemCarriesQuestionsAndAnswers() async throws {
        let (store, source) = await MainActor.run { Self.makeSource() }
        let longHeader = String(repeating: "é", count: 600)   // 1200 bytes
        let json = String(data: try JSONSerialization.data(withJSONObject: ["questions": [
            ["id": "q-long", "header": longHeader, "question": "Pick", "multiSelect": false,
             "options": [["id": "a", "label": "A"]]],
        ]]), encoding: .utf8)!
        await MainActor.run { store.ingest(Self.question("question-long", toolInputJSON: json)) }
        let hook = Self.startBlockingHook(Self.question("question-1"))
        #expect(await Self.waitUntil { store.pending.contains { $0.payload.requestID == "question-1" } })

        let pending = await source.snapshot().pending
        let item = try #require(pending.first { $0.requestId == "question-1" })
        #expect(item.kind == .question)
        #expect(item.modes.isEmpty)
        #expect(item.questions == [
            PendingQuestion(id: "q-db", header: "Database", prompt: "Which database?", multiSelect: false, options: [
                PendingQuestionOption(id: "pg", label: "Postgres", description: "Server"),
                PendingQuestionOption(id: "lite", label: "SQLite"),
            ]),
            PendingQuestion(id: "q-goals", prompt: "What matters?", multiSelect: true, options: [
                PendingQuestionOption(id: "fast", label: "Fast"),
                PendingQuestionOption(id: "cheap", label: "Cheap"),
            ]),
        ])
        // Every text field is cut to 1024 bytes on a scalar boundary.
        let cutHeader = try #require(pending.first { $0.requestId == "question-long" }?.questions?.first?.header)
        #expect(cutHeader.utf8.count == 1024)
        #expect(longHeader.hasPrefix(cutHeader))

        // Positional answers: an option label, and a multi-select answer joined with ", ".
        let outcome = await source.reply(requestId: "question-1",
                                         decision: .question(selections: ["Postgres", "Fast, Cheap"]))
        #expect(outcome == .delivered)
        #expect(hook.wait())
        guard case .resolved(_, .question(let selections))? = hook.result else {
            Issue.record("the hook must get the phone's answers: \(String(describing: hook.result))")
            return
        }
        #expect(selections == ["Postgres", "Fast, Cheap"])
    }

    /// Any string that is not an option label is a free-text answer, passed to the hook unchanged; 1024
    /// bytes is the longest answer accepted.
    @Test func testFreeTextSelectionDelivered() async {
        let (store, source) = await MainActor.run { Self.makeSource() }
        let hook = Self.startBlockingHook(Self.question("free-text-1"))
        #expect(await Self.waitUntil { store.pending.contains { $0.payload.requestID == "free-text-1" } })
        let longest = String(repeating: "x", count: 1021) + "€"   // 1024 bytes

        let outcome = await source.reply(requestId: "free-text-1",
                                         decision: .question(selections: ["Use DuckDB instead", longest]))

        #expect(outcome == .delivered)
        #expect(hook.wait())
        guard case .resolved(_, .question(let selections))? = hook.result else {
            Issue.record("the hook must get the free-text answers: \(String(describing: hook.result))")
            return
        }
        #expect(selections == ["Use DuckDB instead", longest])
    }

    @Test func testSelectionCountMismatchIsUnknown() async {
        let (store, source) = await MainActor.run { Self.makeSource() }
        let hook = Self.startBlockingHook(Self.question("mismatch-1"))
        #expect(await Self.waitUntil { store.pending.contains { $0.payload.requestID == "mismatch-1" } })
        let tooLong = String(repeating: "x", count: 1022) + "€"   // 1025 bytes

        for selections in [["Postgres"], ["Postgres", "Fast", "Cheap"], [], ["Postgres", ""], ["Postgres", tooLong]] {
            #expect(await source.reply(requestId: "mismatch-1", decision: .question(selections: selections)) == .unknown)
        }
        // A permission or plan decision does not answer a question either.
        #expect(await source.reply(requestId: "mismatch-1", decision: .permission(.once)) == .unknown)
        #expect(await source.reply(requestId: "mismatch-1", decision: .exitPlan(.manual, feedback: nil)) == .unknown)

        let stillPending = await MainActor.run { store.pending.contains { $0.payload.requestID == "mismatch-1" } }
        #expect(stillPending)
        #expect(hook.result == nil)
        Self.release("mismatch-1", hook)
    }

    @Test func testExitPlanItemModesExcludeBypass() async throws {
        let (store, source) = await MainActor.run { Self.makeSource() }
        let plan = "# Plan\n" + String(repeating: "€", count: 5000)   // 15 007 bytes
        let hook = Self.startBlockingHook(Self.exitPlan("plan-modes", plan: plan))
        #expect(await Self.waitUntil { store.pending.contains { $0.payload.requestID == "plan-modes" } })

        let item = try #require(await source.snapshot().pending.first { $0.requestId == "plan-modes" })

        #expect(item.kind == .exitPlan)
        #expect(item.modes == ["ultraplan", "auto_accept", "manual", "deny"])
        // The plan text itself (not the tool's JSON envelope), cut to 8192 bytes on a scalar boundary.
        let preview = try #require(item.planPreview)
        #expect(preview.utf8.count <= PendingItem.maxPreviewBytes)
        #expect(preview.utf8.count > PendingItem.maxPreviewBytes - 3)
        #expect(plan.hasPrefix(preview))
        #expect(item.questions == nil)
        for mode in ["bypassPermissions", "bypass_permissions", "bypass"] {
            #expect(await source.reply(requestId: "plan-modes", decision: .exitPlan(.other(mode), feedback: nil)) == .unknown)
        }
        #expect(await source.reply(requestId: "plan-modes", decision: .question(selections: ["A"])) == .unknown)
        #expect(hook.result == nil)
        Self.release("plan-modes", hook)
    }

    @Test func testExitPlanFeedbackDelivered() async {
        let (store, source) = await MainActor.run { Self.makeSource() }
        let hook = Self.startBlockingHook(Self.exitPlan("plan-feedback"))
        #expect(await Self.waitUntil { store.pending.contains { $0.payload.requestID == "plan-feedback" } })
        let longest = String(repeating: "f", count: 4093) + "€"   // 4096 bytes

        // Longer than 4096 bytes is not a decision the Mac accepts; the item stays pending.
        let tooLong = await source.reply(requestId: "plan-feedback", decision: .exitPlan(.deny, feedback: longest + "f"))
        #expect(tooLong == .unknown)
        #expect(hook.result == nil)

        let outcome = await source.reply(requestId: "plan-feedback", decision: .exitPlan(.deny, feedback: longest))

        #expect(outcome == .delivered)
        #expect(hook.wait())
        guard case .resolved(_, .exitPlan(.deny, let feedback))? = hook.result else {
            Issue.record("the hook must get the plan decision: \(String(describing: hook.result))")
            return
        }
        #expect(feedback == longest)

        // Modes map by name: `auto_accept` is the Feed's `autoAccept`.
        let accept = Self.startBlockingHook(Self.exitPlan("plan-accept"))
        #expect(await Self.waitUntil { store.pending.contains { $0.payload.requestID == "plan-accept" } })
        #expect(await source.reply(requestId: "plan-accept", decision: .exitPlan(.autoAccept, feedback: nil)) == .delivered)
        #expect(accept.wait())
        guard case .resolved(_, .exitPlan(.autoAccept, nil))? = accept.result else {
            Issue.record("auto_accept must reach the hook as autoAccept: \(String(describing: accept.result))")
            return
        }
    }

    /// `feed.*.reply` reports whether a waiting hook took the decision (`deliverReply`), not always `true`.
    @Test func testFeedReplySocketReportsNotDelivered() async {
        let (store, _) = await MainActor.run { Self.makeSource() }
        let controller = await MainActor.run { TerminalController.shared }
        let results = [
            controller.v2FeedPermissionReply(params: ["request_id": "socket-none-1", "mode": "once"]),
            controller.v2FeedQuestionReply(params: ["request_id": "socket-none-2", "selections": ["A"]]),
            controller.v2FeedExitPlanReply(params: ["request_id": "socket-none-3", "mode": "manual"]),
        ]
        #expect(results.map(Self.delivered) == [false, false, false])

        let hook = Self.startBlockingHook(Self.permission("socket-waiting"))
        #expect(await Self.waitUntil { store.pending.contains { $0.payload.requestID == "socket-waiting" } })
        let waiting = controller.v2FeedPermissionReply(params: ["request_id": "socket-waiting", "mode": "once"])
        #expect(Self.delivered(waiting) == true)
        #expect(hook.wait())
    }

    private static func delivered(_ result: TerminalController.V2CallResult) -> Bool? {
        guard case .ok(let payload) = result else { return nil }
        return (payload as? [String: Any])?["delivered"] as? Bool
    }

    /// Once a phone's answer reaches the waiting hook the agent resumes, but Claude Code fires no hook until its
    /// next tool call or stop. The session turns `working` as soon as the reply is delivered, and every phone is
    /// pushed the change with no further hook event. While the session still waits on another request, it
    /// stays `needs_input`.
    @Test func testReplyMovesSessionToWorkingAtOnce() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("shellx-link-reply-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let session = UUID().uuidString, surface = UUID().uuidString
        let (store, feed) = await MainActor.run { Self.makeSource() }
        // `deliverReply` reaches the app's transcript service, so this test's service stands in for it.
        let (service, sessions, previous) = await MainActor.run {
            () -> (AgentChatTranscriptService, ShellXLinkSessionSource, AgentChatTranscriptService?) in
            let service = AgentChatTranscriptService(
                registry: AgentChatSessionRegistry(hookStore: AgentChatHookSessionStore(homeDirectory: home)),
                resolver: AgentChatTranscriptResolver(homeDirectory: home, environment: [:]),
                hasEventSubscribers: { false },
                emitEventPayload: { _ in }
            )
            let previous = TerminalController.shared.agentChatTranscriptService
            TerminalController.shared.agentChatTranscriptService = service
            let sessions = ShellXLinkSessionSource(
                service: { service }, workspaceLookup: { _ in Self.workspace },
                terminalIsOpen: { _ in true }, changeSignal: { _ in {} }
            )
            return (service, sessions, previous)
        }
        defer {
            let restore: @Sendable () -> Void = {
                MainActor.assumeIsolated {
                    TerminalController.shared.agentChatTranscriptService = previous
                    service.shutdown()
                }
            }
            if Thread.isMainThread { restore() } else { DispatchQueue.main.sync(execute: restore) }
        }
        func permission(_ requestId: String) -> WorkstreamEvent {
            WorkstreamEvent(sessionId: session, hookEventName: .permissionRequest, source: "claude", surfaceId: surface,
                            cwd: "/tmp/shellx", toolName: "Bash", toolInputJSON: #"{"command":"git status"}"#,
                            requestId: requestId)
        }
        await MainActor.run {
            service.noteHookEvent(WorkstreamEvent(sessionId: session, hookEventName: .sessionStart, source: "claude",
                                                  surfaceId: surface, cwd: "/tmp/shellx"))
            service.noteHookEvent(permission("resume-1"))
            service.noteHookEvent(permission("resume-2"))
        }
        let changes = SessionChangeRecorder()
        let consumer = Task { for await change in sessions.sessionChanges() { changes.record(change) } }
        defer { consumer.cancel() }
        // The subscription registers on the main actor; this call orders it before the replies.
        let before = await sessions.sessions()
        #expect(before.sessions.first { $0.sessionId == session }?.state == .needsInput)
        let first = Self.startBlockingHook(permission("resume-1"))
        let second = Self.startBlockingHook(permission("resume-2"))
        #expect(await Self.waitUntil {
            Set(store.pending.compactMap(\.payload.requestID)).isSuperset(of: ["resume-1", "resume-2"])
        })

        // The session still waits on its other request.
        #expect(await feed.reply(requestId: "resume-1", decision: .permission(.once)) == .delivered)
        #expect(first.wait())
        #expect(changes.all.isEmpty)
        #expect(await sessions.sessions().revision == before.revision)

        // Its last request answered, the agent resumes: pushed at once, with no hook event and no list pull.
        #expect(await feed.reply(requestId: "resume-2", decision: .permission(.once)) == .delivered)
        #expect(await Self.waitUntil { !changes.all.isEmpty })
        let resumed = try #require(changes.all.first)
        #expect(resumed.revision == before.revision + 1)
        #expect(resumed.upserted.map(\.sessionId) == [session])
        #expect(resumed.upserted.first?.state == .working)
        #expect(second.wait())
    }
}

/// The changes one `sessionChanges()` subscriber received, filled by its consumer task.
private final class SessionChangeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ShellXLinkSessionSource.Change] = []
    func record(_ change: ShellXLinkSessionSource.Change) { lock.lock(); recorded.append(change); lock.unlock() }
    var all: [ShellXLinkSessionSource.Change] { lock.lock(); defer { lock.unlock() }; return recorded }
}

/// The result of one blocking hook, filled on its worker thread.
private final class BlockingHook: @unchecked Sendable {
    private let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var value: FeedCoordinator.IngestBlockingResult?

    var result: FeedCoordinator.IngestBlockingResult? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func finish(_ result: FeedCoordinator.IngestBlockingResult) {
        lock.lock(); value = result; lock.unlock()
        done.signal()
    }

    /// True once the hook returned (within 5 s).
    func wait() -> Bool {
        guard done.wait(timeout: .now() + 5) == .success else { return false }
        done.signal()   // later waits return at once
        return true
    }
}

private final class RevisionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Int] = []
    func record(_ value: Int) { lock.lock(); recorded.append(value); lock.unlock() }
    var values: [Int] { lock.lock(); defer { lock.unlock() }; return recorded }
}

/// The changes one subscriber received, by request id, filled by its consumer task.
private final class ChangeRecorder: @unchecked Sendable {
    struct Change {
        let revision: Int
        let added: [String]
        let resolved: [String]
    }

    private let lock = NSLock()
    private var recorded: [Change] = []

    func record(_ change: ShellXLinkFeedSource.Change) {
        let entry = Change(revision: change.revision, added: change.added.map(\.requestId), resolved: change.resolved)
        lock.lock(); recorded.append(entry); lock.unlock()
    }

    var changes: [Change] { lock.lock(); defer { lock.unlock() }; return recorded }
    var added: [String] { changes.flatMap(\.added) }
    var resolved: [String] { changes.flatMap(\.resolved) }
}
