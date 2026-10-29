import Foundation
import os
import ShellXLinkCore
import ShellXLinkSession
import ShellXRemoteCore

/// Tells this Mac's paired iPhones, through the ShellX relay (`notify.phones`), when a Claude Code request
/// starts waiting for the user and when it was handled. It follows the Feed on its own subscription, so the
/// phones hear about a request while none of them is connected. The Notifications page's "Forward
/// notifications to my iPhone" settings decide whether it sends (`allows`, including "only when away"); with
/// "Hide content" the alert leaves the workspace out. The alert never says what the agent asks.
///
/// ``ShellXLinkHostController`` starts it with the link host and stops it with the host.
@MainActor
final class ShellXPhonePushForwarder {
    typealias Change = (revision: Int, added: [PendingItem], resolved: [String])

    nonisolated private static let log = Logger(subsystem: "pro.shellx.desktop", category: "phone-push")

    private let changes: () -> AsyncStream<Change>
    private let allows: @MainActor () -> Bool
    private let hidesWorkspace: @MainActor () -> Bool
    private let send: @Sendable (PhoneNotification) async -> Void
    /// The requests the phones were told about and not yet told are handled. Kept across ``stop()`` and
    /// ``start()``: a request alerted before a host restart and handled after it still gets its `resolved`.
    private var told: Set<String> = []
    private var following: Task<Void, Never>?

    /// - Parameters:
    ///   - changes: The Feed's pending changes (``ShellXLinkFeedSource/changes()``).
    ///   - allows: Whether forwarding is on and, in "only when away" mode, the user is away.
    ///   - hidesWorkspace: "Hide content": the alert names only the agent.
    ///   - send: Delivers one notification; failures are its own to log.
    init(changes: @escaping () -> AsyncStream<Change>, allows: @escaping @MainActor () -> Bool,
         hidesWorkspace: @escaping @MainActor () -> Bool, send: @escaping @Sendable (PhoneNotification) async -> Void) {
        self.changes = changes
        self.allows = allows
        self.hidesWorkspace = hidesWorkspace
        self.send = send
    }

    /// The app's forwarder: the Notifications page's settings, and shellx-core off the main thread.
    static func live(feed: any AgentFeedSource, core: ShellXCoreClient) -> ShellXPhonePushForwarder {
        ShellXPhonePushForwarder(
            changes: { feed.changes() },
            allows: { PhonePushClient.shared.currentAdmission() == .allowed },
            hidesWorkspace: { UserDefaults.standard.bool(forKey: PhonePushSettings.hideContentKey) },
            send: { notification in
                await Task.detached {
                    do {
                        try core.notifyPhones(notification)
                    } catch {
                        // `push_unavailable` until the relay has its APNs key; never the request's content.
                        Self.log.notice("phone push not sent: \(String(describing: type(of: error)), privacy: .public)")
                    }
                }.value
            })
    }

    /// Follows the Feed until ``stop()``; a second call keeps the one subscription.
    func start() {
        guard following == nil else { return }
        let stream = changes()
        following = Task { [weak self] in
            for await change in stream {
                guard let self, !Task.isCancelled else { return }
                await self.handle(change)
            }
        }
    }

    func stop() {
        following?.cancel()
        following = nil
    }

    /// One Feed change: tell the phones about each new request (when allowed), and take away the alert of
    /// each handled request they were told about. In order, so a handled request never arrives first.
    func handle(_ change: Change) async {
        for item in change.added where !told.contains(item.requestId) {
            guard allows() else { continue }
            told.insert(item.requestId)
            await send(.needsYou(
                requestID: item.requestId, agent: Self.agentName(item.agent),
                workspaceTitle: hidesWorkspace() ? "" : item.workspaceTitle))
        }
        for id in change.resolved where told.remove(id) != nil {
            await send(.resolved(requestID: id))
        }
    }

    /// The agent's product name, as the phone shows it.
    static func agentName(_ agent: String) -> String {
        switch agent {
        case "claude": "Claude Code"
        case "codex": "Codex"
        default: agent
        }
    }
}
