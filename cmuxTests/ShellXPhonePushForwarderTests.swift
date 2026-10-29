import Foundation
import ShellXLinkCore
import ShellXRemoteCore
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// What this Mac tells its paired iPhones through the relay (`notify.phones`) as Feed requests come and go.
@Suite("ShellX phone push forwarder", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ShellXPhonePushForwarderTests {
    /// Records what the forwarder sends, in order.
    final class Sent: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [PhoneNotification] = []
        func append(_ n: PhoneNotification) { lock.lock(); items.append(n); lock.unlock() }
        var all: [PhoneNotification] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private static func item(_ id: String, agent: String = "claude", workspace: String = "shellx") -> PendingItem {
        PendingItem(requestId: id, kind: .permission, agent: agent, workspaceId: "ws", workspaceTitle: workspace, createdAtMs: 1)
    }

    private static func forwarder(
        allows: Bool = true, hidesWorkspace: Bool = false, sent: Sent,
        changes: @escaping () -> AsyncStream<ShellXPhonePushForwarder.Change> = { AsyncStream { _ in } }
    ) -> ShellXPhonePushForwarder {
        ShellXPhonePushForwarder(
            changes: changes, allows: { allows }, hidesWorkspace: { hidesWorkspace },
            send: { sent.append($0) })
    }

    @Test func aNewRequestTellsThePhonesOnceWithTheAgentAndWorkspace() async {
        let sent = Sent()
        let forwarder = Self.forwarder(sent: sent)

        await forwarder.handle((revision: 1, added: [Self.item("r1")], resolved: []))
        await forwarder.handle((revision: 2, added: [Self.item("r1"), Self.item("r2", agent: "codex", workspace: "web")], resolved: []))

        #expect(sent.all == [
            .needsYou(requestID: "r1", agent: "Claude Code", workspaceTitle: "shellx"),
            .needsYou(requestID: "r2", agent: "Codex", workspaceTitle: "web"),
        ])
    }

    @Test func aHandledRequestIsTakenAwayOnlyIfThePhonesWereTold() async {
        let sent = Sent()
        let forwarder = Self.forwarder(sent: sent)

        await forwarder.handle((revision: 1, added: [Self.item("r1")], resolved: []))
        await forwarder.handle((revision: 2, added: [], resolved: ["r1", "r-never-told"]))
        await forwarder.handle((revision: 3, added: [], resolved: ["r1"]))

        #expect(sent.all == [
            .needsYou(requestID: "r1", agent: "Claude Code", workspaceTitle: "shellx"),
            .resolved(requestID: "r1"),
        ])
    }

    @Test func aRequestAlertedBeforeAHostRestartStillGetsItsResolvedPush() async {
        let sent = Sent()
        let forwarder = Self.forwarder(sent: sent)

        forwarder.start()
        await forwarder.handle((revision: 1, added: [Self.item("r1")], resolved: []))
        forwarder.stop()
        forwarder.start()
        await forwarder.handle((revision: 2, added: [], resolved: ["r1"]))
        forwarder.stop()

        #expect(sent.all == [
            .needsYou(requestID: "r1", agent: "Claude Code", workspaceTitle: "shellx"),
            .resolved(requestID: "r1"),
        ])
    }

    @Test func forwardingTurnedOffOrTheUserAtTheMacSendsNothing() async {
        let sent = Sent()
        let forwarder = Self.forwarder(allows: false, sent: sent)

        await forwarder.handle((revision: 1, added: [Self.item("r1")], resolved: []))
        await forwarder.handle((revision: 2, added: [], resolved: ["r1"]))

        #expect(sent.all.isEmpty)
    }

    @Test func hideContentLeavesTheWorkspaceOut() async {
        let sent = Sent()
        let forwarder = Self.forwarder(hidesWorkspace: true, sent: sent)

        await forwarder.handle((revision: 1, added: [Self.item("r1")], resolved: []))

        #expect(sent.all == [.needsYou(requestID: "r1", agent: "Claude Code", workspaceTitle: "")])
    }

    @Test func itFollowsTheFeedFromStartUntilStop() async {
        let sent = Sent()
        let (stream, feed) = AsyncStream<ShellXPhonePushForwarder.Change>.makeStream()
        var subscribed = 0
        let forwarder = Self.forwarder(sent: sent, changes: { subscribed += 1; return stream })

        forwarder.start()
        forwarder.start()
        feed.yield((revision: 1, added: [Self.item("r1")], resolved: []))
        #expect(await Self.waitUntil { sent.all.count == 1 })
        forwarder.stop()
        feed.yield((revision: 2, added: [Self.item("r2")], resolved: []))
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(subscribed == 1, "a second start keeps the one subscription")
        #expect(sent.all == [.needsYou(requestID: "r1", agent: "Claude Code", workspaceTitle: "shellx")])
    }

    private static func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}
