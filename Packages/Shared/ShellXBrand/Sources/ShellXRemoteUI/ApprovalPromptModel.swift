import Foundation
import ShellXRemoteCore

/// Localized text for the on-site approval prompt, injected so this module
/// needs no bundle. `title` takes the requesting machine's name as its one
/// `%@`; `queue` takes the position and the pending count as `%lld`, `%lld`.
public struct ApprovalPromptLabels: Equatable, Sendable {
    public let title: String
    public let compare: String
    public let suspicious: String
    public let approve: String
    public let deny: String
    public let queue: String
    /// Shown for a failed approval with the code `network`; any other code is shown as is.
    public let network: String
    public let codeLabel: String
    public let fingerprintLabel: String

    public init(
        title: String, compare: String, suspicious: String, approve: String, deny: String,
        queue: String, network: String, codeLabel: String, fingerprintLabel: String
    ) {
        self.title = title
        self.compare = compare
        self.suspicious = suspicious
        self.approve = approve
        self.deny = deny
        self.queue = queue
        self.network = network
        self.codeLabel = codeLabel
        self.fingerprintLabel = fingerprintLabel
    }

    public static let english = ApprovalPromptLabels(
        title: "%@ wants to view and control this Mac",
        compare: "Approve only if the code and fingerprint match the other screen.",
        suspicious: "The fingerprint does not match what the server reports. Do not approve.",
        approve: "Approve",
        deny: "Deny",
        queue: "%lld of %lld",
        network: "Can't reach relay.shellx.pro",
        codeLabel: "Code",
        fingerprintLabel: "Fingerprint"
    )
}

/// What the on-site approval prompt shows for the service's pending
/// requests. The person on this Mac compares the code and the requester's
/// fingerprint with the other screen, so both are always shown together, and
/// a request the server reports as suspicious can never be approved.
public struct ApprovalPromptModel: Equatable, Sendable {
    /// The error code the core reports when the requester's fingerprint does
    /// not match what the server reports.
    public static let fingerprintMismatchCode = "fingerprint_mismatch"

    /// The oldest request that has not expired.
    public let current: PairingRequest?
    public let title: String
    /// The view shows the title on one line with tail truncation.
    public let titleLineLimit = 1
    public let compareText: String
    /// "123 456"
    public let codeText: String
    /// The requester's fingerprint, "a1b2 c3d4 e5f6 0718".
    public let fingerprintText: String
    /// The suspicious text, shown in the `error` tone. Nil when nothing is wrong with the fingerprint.
    public let warning: String?
    /// A failed approval, shown inline in the `error` tone.
    public let errorText: String?
    public let canApprove: Bool
    /// Deny stays available for every request, suspicious or not.
    public let canDeny: Bool
    public let isBusy: Bool
    /// "1 of 2": the shown request's place among the pending ones. Nil with at most one pending.
    public let queueText: String?
    public let approveTitle: String
    public let denyTitle: String
    public let codeLabel: String
    public let fingerprintLabel: String
    /// When the shown request expires: when the view must ask for a new model.
    public let nextExpiry: Date?
    /// While Approve is held back so the person has time to compare the code
    /// and fingerprint: the moment it becomes available. Nil once armed, and
    /// for a model built without one.
    public let armsAt: Date?

    /// The next moment the model changes by itself: Approve arms, or the
    /// shown request expires. The view asks for a new model then.
    public var nextWake: Date? {
        [armsAt, nextExpiry].compactMap { $0 }.min()
    }

    /// `queue` is the service's `pendingApprovals`, in any order. Requests with
    /// `now >= expiresAt` are dropped. `failureCode` is the last failed
    /// approval of the shown request; `isBusy` while a decision is in flight.
    /// `contentChanged` marks a request whose code, fingerprint or requester
    /// differs from what was first shown for its id: it is treated like a
    /// fingerprint mismatch. `approvalArmsAt` holds Approve back (never Deny)
    /// until that moment; nil means armed.
    public init(
        queue: [PairingRequest],
        now: Date,
        labels: ApprovalPromptLabels = .english,
        failureCode: String? = nil,
        isBusy: Bool = false,
        contentChanged: Bool = false,
        approvalArmsAt: Date? = nil
    ) {
        // Stable: requests seen at the same time keep the order they were listed in.
        let live = queue.enumerated()
            .filter { now < $0.element.expiresAt }
            .sorted { lhs, rhs in
                lhs.element.firstSeen == rhs.element.firstSeen
                    ? lhs.offset < rhs.offset
                    : lhs.element.firstSeen < rhs.element.firstSeen
            }
            .map(\.element)
        current = live.first
        compareText = labels.compare
        approveTitle = labels.approve
        denyTitle = labels.deny
        codeLabel = labels.codeLabel
        fingerprintLabel = labels.fingerprintLabel
        self.isBusy = isBusy
        nextExpiry = live.first?.expiresAt
        let waiting = live.first != nil ? approvalArmsAt.flatMap { $0 > now ? $0 : nil } : nil
        armsAt = waiting
        queueText = live.count > 1
            ? String(format: labels.queue, Int64(1), Int64(live.count))
            : nil

        guard let request = live.first else {
            title = ""
            codeText = ""
            fingerprintText = ""
            warning = nil
            errorText = nil
            canApprove = false
            canDeny = false
            return
        }
        title = String(format: labels.title, request.requesterName)
        codeText = PairingDisplay.code(request.code)
        fingerprintText = PairingDisplay.fingerprint(request.fingerprint)
        let mismatch = failureCode == Self.fingerprintMismatchCode
        let blocked = request.suspicious || mismatch || contentChanged
        warning = blocked ? labels.suspicious : nil
        if let failureCode, !mismatch {
            errorText = failureCode == "network" ? labels.network : failureCode
        } else {
            errorText = nil
        }
        canApprove = !blocked && !isBusy && waiting == nil
        canDeny = !isBusy
    }
}
