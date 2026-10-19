import Foundation
import ShellXRemoteCore

/// The state behind one approval prompt: which decision is in flight, which
/// requests were already decided, and which failed. Pure: the app's
/// controller owns the Tasks and the timer and calls these in order, so a
/// stale button, an expired request or a closed prompt can never start an
/// approval.
public struct ApprovalPromptTracker: Sendable {
    public enum Decision: Equatable, Sendable { case approve, deny }

    private struct InFlight: Sendable {
        let decision: Decision
        let requestID: PairingRequest.ID
    }

    public private(set) var isStopped = false

    private var inFlight: InFlight?
    /// Approved or denied here; hidden until the service stops listing them,
    /// so a service that lags cannot show a decided request again.
    private var decided: Set<PairingRequest.ID> = []
    private var failures: [PairingRequest.ID: String] = [:]

    public init() {}

    /// The model for the service's `queue`: decided requests are left out and
    /// the shown request carries its last failure.
    public func model(
        queue: [PairingRequest],
        now: Date,
        labels: ApprovalPromptLabels = .english
    ) -> ApprovalPromptModel {
        let pending = queue.filter { !decided.contains($0.id) }
        let current = ApprovalPromptModel(queue: pending, now: now, labels: labels).current
        return ApprovalPromptModel(
            queue: pending,
            now: now,
            labels: labels,
            failureCode: current.flatMap { failures[$0.id] },
            isBusy: inFlight != nil
        )
    }

    /// The person pressed Approve or Deny on the request they were shown
    /// (`requestID`). True when the service call should be made: only for the
    /// request that is still the oldest unexpired one, only one decision at a
    /// time, never an approval the model refuses, never once stopped.
    public mutating func begin(
        _ decision: Decision,
        requestID: PairingRequest.ID,
        queue: [PairingRequest],
        now: Date
    ) -> Bool {
        guard !isStopped, inFlight == nil else { return false }
        let shown = model(queue: queue, now: now)
        guard shown.current?.id == requestID else { return false }
        switch decision {
        case .approve: guard shown.canApprove else { return false }
        case .deny: guard shown.canDeny else { return false }
        }
        failures[requestID] = nil
        inFlight = InFlight(decision: decision, requestID: requestID)
        return true
    }

    /// The service call finished. With a `failureCode` the request stays,
    /// with the failure shown inline; without one it is hidden at once.
    /// Ignored when stopped or when it is not the call in flight.
    public mutating func finish(_ decision: Decision, requestID: PairingRequest.ID, failureCode: String?) {
        guard !isStopped, let flight = inFlight, flight.decision == decision, flight.requestID == requestID else { return }
        inFlight = nil
        if let failureCode {
            failures[requestID] = failureCode
        } else {
            decided.insert(requestID)
        }
    }

    /// Forget requests the service no longer lists.
    public mutating func prune(queue: [PairingRequest]) {
        let listed = Set(queue.map(\.id))
        decided.formIntersection(listed)
        failures = failures.filter { listed.contains($0.key) }
    }

    /// The prompt was closed: nothing starts or finishes after this.
    public mutating func stop() {
        isStopped = true
        inFlight = nil
    }
}
