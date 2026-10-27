import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// A signed-in hub connected to fake Macs, with a `DecisionCenter` over it, for the decision tests.
@MainActor
struct PendingRig {
    let hub: MachineHub
    let center: DecisionCenter
    let latency: LatencyLog
    /// The hub's reconnect waits.
    let backoff: ManualSleeper
    /// The center's waits (the 2 s "handled elsewhere" linger).
    let linger: ManualSleeper

    static func make(_ macs: [FakeMac], in test: XCTestCase) async throws -> PendingRig {
        let vault = AccountVault(store: InMemorySecretStore())
        try await vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "tok-1", email: "a@b.c"))
        try await vault.setMachines(macs.map(\.machine), owner: "u1")
        let suite = "PendingRig-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        test.addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let latency = LatencyLog()
        let backoff = ManualSleeper()
        let linger = ManualSleeper()
        let hub = MachineHub(
            vault: vault, relay: FakeRelayAccount(),
            connector: FakeMacFleet(macs, phoneKey: { try await vault.phoneKey() }), latency: latency,
            defaults: defaults, sleep: backoff.sleep, onUnauthorized: {})
        test.addTeardownBlock { await hub.stopAll() }
        let center = DecisionCenter(sender: hub, latency: latency, sleep: linger.sleep)
        await hub.start()
        return PendingRig(hub: hub, center: center, latency: latency, backoff: backoff, linger: linger)
    }

    func key(_ mac: FakeMac, _ requestId: String) -> PendingKey {
        PendingKey(machineID: mac.machine.machineID, requestId: requestId)
    }

    /// Waits until every Mac is online with `count` pending items, all actionable.
    func synced(count: Int) async -> Bool {
        await eventually {
            hub.machines.allSatisfy { $0.state == .online } && hub.pendingItems.count == count
                && hub.pendingItems.allSatisfy(\.actionable)
        }
    }

    /// The request ids the cards show right now.
    var visibleIDs: [String] { center.visibleItems(hub.pendingItems).map(\.item.requestId) }
}

/// A `DecisionSending` that answers from a script, for what the real Link cannot do quickly (its
/// request timeout is 10 s). Each call takes the next answer; the last one repeats.
@MainActor
final class ScriptedSender: DecisionSending {
    enum Answer {
        case outcome(ReplyOutcome)
        case failure(any Error)
    }

    private var answers: [Answer]
    /// Every call, in order.
    private(set) var calls: [(key: PendingKey, decision: LinkDecision)] = []
    /// When set, every call waits here before answering.
    var gate: Gate?

    init(_ answers: [Answer]) {
        self.answers = answers
    }

    func reply(_ key: PendingKey, decision: LinkDecision) async throws -> ReplyOutcome {
        calls.append((key, decision))
        if let gate { await gate.wait() }
        let answer = answers.count > 1 ? answers.removeFirst() : answers[0]
        switch answer {
        case let .outcome(outcome): return outcome
        case let .failure(error): throw error
        }
    }
}

func permissionItem(_ id: String, modes: [String] = ["once", "always", "deny"]) -> PendingItem {
    PendingItem(
        requestId: id, kind: .permission, agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx",
        toolName: "Bash", toolInputPreview: #"{"command":"git push"}"#, createdAtMs: 1_700_000_000_000, modes: modes)
}

func questionItem(_ id: String) -> PendingItem {
    PendingItem(
        requestId: id, kind: .question, agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx",
        createdAtMs: 1_700_000_000_001, modes: [],
        questions: [
            PendingQuestion(
                id: "q1", prompt: "Which database?", multiSelect: false,
                options: [
                    PendingQuestionOption(id: "pg", label: "Postgres"), PendingQuestionOption(id: "sq", label: "SQLite"),
                ])
        ])
}

func planItem(_ id: String) -> PendingItem {
    PendingItem(
        requestId: id, kind: .exitPlan, agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx",
        createdAtMs: 1_700_000_000_002, modes: ["auto_accept", "manual", "deny"], planPreview: "1. Add tests.\n2. Ship.")
}
