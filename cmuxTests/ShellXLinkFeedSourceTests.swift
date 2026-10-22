import CMUXAgentLaunch
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
@Suite("ShellX Link feed source", .serialized)
struct ShellXLinkFeedSourceTests {
    private static let workspace = (id: "11111111-2222-3333-4444-555555555555", title: "shellx")

    /// A fresh store and a source whose workspace lookup needs no live window.
    @MainActor
    private static func makeSource() -> (WorkstreamStore, ShellXLinkFeedSource) {
        let store = WorkstreamStore(ringCapacity: 50)
        FeedCoordinator.shared.install(store: store)
        let source = ShellXLinkFeedSource(coordinator: .shared, workspaceLookup: { _ in workspace })
        return (store, source)
    }

    private static func permission(_ requestId: String, toolInputJSON: String = #"{"command":"git status"}"#,
                                   source: String = "claude") -> WorkstreamEvent {
        WorkstreamEvent(
            sessionId: "link-\(requestId)",
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

        let outcome = await source.reply(requestId: "mac-first", mode: .always)

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

        #expect(await source.reply(requestId: "phone-first", mode: .once) == .delivered)
        #expect(hook.wait())
        guard case .resolved(_, .permission(.once))? = hook.result else {
            Issue.record("the hook must get the phone's decision: \(String(describing: hook.result))")
            return
        }
        // A resend is answered, never resolved again.
        #expect(await source.reply(requestId: "phone-first", mode: .deny) == .alreadyHandled)
    }

    @Test func testReplyToUnknownRequestOrDisallowedModeIsUnknown() async {
        let (store, source) = await MainActor.run { Self.makeSource() }
        #expect(await source.reply(requestId: "never-seen", mode: .once) == .unknown)

        // Hermes has no persistent permission modes (`FeedPermissionActionPolicy`).
        await MainActor.run { store.ingest(Self.permission("hermes-1", source: "hermes-agent")) }
        #expect(await source.reply(requestId: "hermes-1", mode: .always) == .unknown)
        let stillPending = await MainActor.run { store.pending.contains { $0.payload.requestID == "hermes-1" } }
        #expect(stillPending)
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
        let first = Task { () -> Int in
            var count = 0
            for await _ in source.changes() { count += 1 }
            return count
        }
        _ = await source.snapshot()
        #expect(await MainActor.run { source.subscriberCount } == 1)
        first.cancel()
        _ = await first.value
        #expect(await Self.waitUntil { source.subscriberCount == 0 })
        // Nothing is yielded to the ended stream, and nobody deadlocks.
        await MainActor.run { store.ingest(Self.permission("after-cancel")) }
        #expect(await source.snapshot().pending.map(\.requestId) == ["after-cancel"])
    }
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
