import AppKit
import Combine
import Foundation
import ShellXRemoteCore
import ShellXRemoteUI

/// Shows the approval panel while the service has pending approvals and
/// closes it when none is left. It follows `pendingApprovals` live, drops a
/// request on its own when it expires (no click needed), and turns Approve and
/// Deny into service calls. Everything the person may or may not do is decided
/// by the package's `ApprovalPromptTracker`; this class owns the Tasks, the
/// timer and the panel.
///
/// It is created by `ShellXRemoteUIModel` only when the remote UI has a
/// service, so with the gate off nothing here exists or runs. It never reads
/// `ShellXRemoteUIModel.shared`: it is started from that singleton's initializer.
@MainActor
final class ApprovalPromptController {
    private let service: any ShellXRemoteServicing
    private let now: () -> Date
    private let viewModel = ApprovalPromptViewModel()
    private var tracker = ApprovalPromptTracker()
    private var changeCancellable: AnyCancellable?
    private var expiryTask: Task<Void, Never>?
    private var decisionTask: Task<Void, Never>?
    private var panel: ApprovalPromptPanel?

    init(service: any ShellXRemoteServicing, now: @escaping () -> Date = { Date() }) {
        self.service = service
        self.now = now
        viewModel.onApprove = { [weak self] id in self?.decide(.approve, requestID: id) }
        viewModel.onDeny = { [weak self] id in self?.decide(.deny, requestID: id) }
    }

    /// Starts following the service. The first pass runs on the next turn, so
    /// it never happens inside the creator's initializer.
    func start() {
        guard changeCancellable == nil, !tracker.isStopped else { return }
        // `changePublisher` fires before the change lands; read on the next turn.
        changeCancellable = service.changePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }

    /// No Task, timer, subscription or panel outlives this call.
    func stop() {
        tracker.stop()
        changeCancellable = nil
        decisionTask?.cancel()
        decisionTask = nil
        closePanel()
    }

    func refresh() {
        guard !tracker.isStopped else { return }
        let queue = service.pendingApprovals
        tracker.prune(queue: queue)
        let state = tracker.model(queue: queue, now: now(), labels: .localized)
        // ShellX: TODO bell item (W1 Task 11, after checkpoint 1)
        guard state.current != nil else {
            closePanel()
            return
        }
        if state != viewModel.state {
            viewModel.state = state
        }
        present(title: state.title)
        scheduleExpiry(at: state.nextExpiry)
    }

    /// Approve or Deny on the request the buttons were drawn for. The tracker
    /// refuses a stale button, an expired or suspicious request and a second
    /// decision; a refused click just redraws what is true now.
    private func decide(_ decision: ApprovalPromptTracker.Decision, requestID: PairingRequest.ID) {
        let began = tracker.begin(decision, requestID: requestID, queue: service.pendingApprovals, now: now())
        guard began else {
            refresh()
            return
        }
        refresh()
        let service = service
        decisionTask = Task { @MainActor [weak self] in
            var failureCode: String?
            switch decision {
            case .approve:
                do {
                    try await service.approve(requestID)
                } catch {
                    // The core's code, or `network` when the transport threw first.
                    failureCode = (error as? ShellXCoreError)?.code ?? "network"
                }
            case .deny:
                await service.deny(requestID)
            }
            guard !Task.isCancelled, let self else { return }
            self.decisionTask = nil
            self.tracker.finish(decision, requestID: requestID, failureCode: failureCode)
            self.refresh()
        }
    }

    private func present(title: String) {
        let panel = self.panel ?? ApprovalPromptPanel(viewModel: viewModel)
        self.panel = panel
        panel.title = title
        guard !panel.isVisible else { return }
        panel.center()
        // In front of other apps' windows too, so the person at this Mac sees
        // it, and key so the buttons take clicks. It does not activate the app.
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func closePanel() {
        expiryTask?.cancel()
        expiryTask = nil
        guard let panel else { return }
        panel.orderOut(nil)
        self.panel = nil
    }

    /// Wakes once the shown request expires and asks for a new model, so an
    /// expired request disappears without a click. The delay is bounded, so a
    /// far-off deadline only re-arms the timer.
    private func scheduleExpiry(at deadline: Date?) {
        expiryTask?.cancel()
        expiryTask = nil
        guard let deadline else { return }
        let seconds = min(max(deadline.timeIntervalSince(now()), 0) + 0.05, 3600)
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        expiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self else { return }
            self.expiryTask = nil
            self.refresh()
        }
    }
}
