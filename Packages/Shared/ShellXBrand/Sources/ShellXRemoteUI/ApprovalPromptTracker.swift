import Foundation
import ShellXRemoteCore

/// The state behind one approval prompt: which decision is in flight, which
/// requests were already decided or failed, what each request looked like
/// when it was first seen, and since when the current one has been on screen.
/// Pure: the app's controller owns the Tasks and the timer and calls these in
/// order, so a stale button, a changed or expired request, a request the
/// person has had no time to compare, or a closed prompt can never start an
/// approval.
public struct ApprovalPromptTracker: Sendable {
    public enum Decision: Equatable, Sendable { case approve, deny }

    /// How long a request is on screen before Approve works, so a click
    /// (a double click, a repeat click) or a keystroke aimed at what was there
    /// a moment ago cannot approve a request nobody compared. Deny works at once.
    public static let armingDelay: TimeInterval = 1

    private struct InFlight: Sendable {
        let decision: Decision
        let requestID: PairingRequest.ID
    }

    private struct Shown: Sendable {
        let requestID: PairingRequest.ID
        let since: Date
    }

    public private(set) var isStopped = false

    private var inFlight: InFlight?
    /// Approved or denied here; hidden until the service stops listing them,
    /// so a service that lags cannot show a decided request again.
    private var decided: Set<PairingRequest.ID> = []
    private var failures: [PairingRequest.ID: String] = [:]
    /// Each listed request as first seen: what the person compares against.
    private var pinned: [PairingRequest.ID: PairingRequest] = [:]
    /// Requests whose content changed after the first sighting, or that were
    /// ever reported suspicious: never approvable again, whatever they say later.
    private var tainted: Set<PairingRequest.ID> = []
    private var shown: Shown?

    public init() {}

    /// The model for the service's `queue`: decided requests are left out and
    /// the shown request carries its last failure, whether it still matches
    /// what was first seen, and when Approve arms.
    public func model(
        queue: [PairingRequest],
        now: Date,
        labels: ApprovalPromptLabels = .english
    ) -> ApprovalPromptModel {
        let pending = queue.filter { !decided.contains($0.id) }
        guard let current = ApprovalPromptModel(queue: pending, now: now, labels: labels).current else {
            return ApprovalPromptModel(queue: pending, now: now, labels: labels, isBusy: inFlight != nil)
        }
        // A request nobody has observed on screen is armed one delay from now.
        // A clock that went back never stretches the wait beyond one delay.
        let sinceShown = shown.flatMap { $0.requestID == current.id ? $0.since : nil } ?? now
        let armsAt = min(sinceShown, now).addingTimeInterval(Self.armingDelay)
        return ApprovalPromptModel(
            queue: pending,
            now: now,
            labels: labels,
            failureCode: failures[current.id],
            isBusy: inFlight != nil,
            contentChanged: contentChanged(current),
            approvalArmsAt: armsAt
        )
    }

    /// The controller redraws for `queue` at `now`: remember what every listed
    /// request looked like the first time, flag any that changes later, and
    /// note since when the current request has been shown. Call before `model`.
    public mutating func observe(queue: [PairingRequest], now: Date) {
        guard !isStopped else { return }
        prune(queue: queue)
        let pending = queue.filter { !decided.contains($0.id) && now < $0.expiresAt }
        for request in pending {
            if let pin = pinned[request.id] {
                if !Self.sameContent(pin, request) { tainted.insert(request.id) }
            } else {
                pinned[request.id] = request
            }
            if request.suspicious { tainted.insert(request.id) }
        }
        if let current = ApprovalPromptModel(queue: pending, now: now).current {
            if shown?.requestID != current.id { shown = Shown(requestID: current.id, since: now) }
        } else {
            shown = nil
        }
    }

    /// The person pressed Approve or Deny on `request`, the request exactly as
    /// the button was drawn. True when the service call should be made: only if
    /// that request is still, unchanged, the oldest unexpired one, only one
    /// decision at a time, never an approval the model refuses (suspicious,
    /// changed, not yet armed), never once stopped.
    public mutating func begin(
        _ decision: Decision,
        request: PairingRequest,
        queue: [PairingRequest],
        now: Date
    ) -> Bool {
        guard !isStopped, inFlight == nil else { return false }
        let live = model(queue: queue, now: now)
        guard let current = live.current, current == request else { return false }
        switch decision {
        case .approve: guard live.canApprove else { return false }
        case .deny: guard live.canDeny else { return false }
        }
        failures[request.id] = nil
        inFlight = InFlight(decision: decision, requestID: request.id)
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
        tainted.formIntersection(listed)
        failures = failures.filter { listed.contains($0.key) }
        pinned = pinned.filter { listed.contains($0.key) }
    }

    /// The prompt was closed: nothing starts or finishes after this.
    public mutating func stop() {
        isStopped = true
        inFlight = nil
    }

    private func contentChanged(_ request: PairingRequest) -> Bool {
        if tainted.contains(request.id) { return true }
        guard let pin = pinned[request.id] else { return false }
        return !Self.sameContent(pin, request)
    }

    /// What the person reads and compares: who asks, the code, the fingerprint.
    private static func sameContent(_ a: PairingRequest, _ b: PairingRequest) -> Bool {
        a.fromMachineID == b.fromMachineID
            && a.requesterName == b.requesterName
            && a.code == b.code
            && a.fingerprint == b.fingerprint
    }
}
