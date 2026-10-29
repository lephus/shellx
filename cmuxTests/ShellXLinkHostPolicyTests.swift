import CmuxSettings
import Foundation
import ShellXLinkCore
import ShellXLinkSession
import ShellXRemoteCore
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// A configuration profile that disables remote control (`DisableRemoteControl`) or incoming device access
/// (`DisableIncomingDeviceAccess`) keeps this Mac from serving phones over ShellX Link, also when it arrives
/// while the link host runs. Lifting it serves phones again for the session still signed in.
@MainActor
struct ShellXLinkHostPolicyTests {
    /// The managed policy as the link host reads it.
    final class Policy {
        var blocked = false
    }

    let policy = Policy()
    let center = NotificationCenter()
    let controller: ShellXLinkHostController

    init() {
        let policy = policy
        controller = ShellXLinkHostController(
            core: ShellXCoreClient(OfflineCore()), storage: InMemoryLinkSecretStorage(), feed: EmptyFeed(),
            hostVersion: "1.5.1", machineName: "Mac", isBlockedByPolicy: { policy.blocked },
            notificationCenter: center)
    }

    /// What `ShellXRemoteService` does once `machines.register` gave this Mac its link slot.
    func startForSession() {
        controller.start(machineID: "m_self", linkSlot: "link-self", accountID: "acct")
    }

    /// A profile installed or removed while the app runs (`ManagedPolicyEnforcementObserver` posts this).
    func policyChanges(blocked: Bool) {
        policy.blocked = blocked
        center.post(name: ManagedDevicePolicy.didChangeNotification, object: nil)
    }

    @Test func linkHostServesWithoutAPolicy() {
        defer { controller.stop() }
        startForSession()
        #expect(controller.pairingHost?.linkSlot == "link-self")
    }

    @Test func policyKeepsTheLinkHostFromStarting() {
        defer { controller.stop() }
        policy.blocked = true
        startForSession()
        #expect(controller.pairingHost == nil)
    }

    @Test func runningLinkHostStopsWhenThePolicyArrives() async {
        defer { controller.stop() }
        startForSession()
        #expect(controller.pairingHost != nil)
        policyChanges(blocked: true)
        #expect(await Self.eventually { self.controller.pairingHost == nil })
    }

    @Test func liftedPolicyServesTheSignedInSessionAgain() async {
        defer { controller.stop() }
        startForSession()
        policyChanges(blocked: true)
        #expect(await Self.eventually { self.controller.pairingHost == nil })
        policyChanges(blocked: false)
        #expect(await Self.eventually { self.controller.pairingHost != nil })
        #expect(controller.pairingHost?.accountID == "acct")
    }

    /// The session ended (signed out) while the policy held the host stopped: a lift starts nothing.
    @Test func liftedPolicyAfterTheSessionEndedStartsNothing() async {
        defer { controller.stop() }
        policy.blocked = true
        startForSession()
        controller.stop()
        policyChanges(blocked: false)
        for _ in 0..<20 { await Task.yield() }
        #expect(controller.pairingHost == nil)
    }

    /// True once `condition` holds, polling for up to a second.
    static func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(1)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return condition()
    }
}

/// shellx-core with no network: every call fails, so the link host keeps retrying its registration.
private struct OfflineCore: ShellXCoreCalling {
    func call(method: String, json: Data) throws -> Data {
        Data(#"{"error":{"code":"network","message":"offline"}}"#.utf8)
    }
}

/// A Feed with nothing pending.
private struct EmptyFeed: AgentFeedSource {
    func snapshot() async -> (revision: Int, pending: [PendingItem]) { (0, []) }
    func changes() -> AsyncStream<(revision: Int, added: [PendingItem], resolved: [String])> {
        AsyncStream { $0.finish() }
    }
    func reply(requestId: String, decision: LinkDecision) async -> ReplyOutcome { .unknown }
}
