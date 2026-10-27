import Foundation
import Observation
import ShellXLinkCore

/// What the question and plan sheets need about their one item: whether it can still be answered
/// from here, and what became of the answer.
///
/// The sheet stays open while the user reads and types, so the item may be decided elsewhere
/// meanwhile (on the Mac, on another phone): then `handledElsewhere` turns true and nothing can be
/// sent any more (Review Focus 2).
@MainActor @Observable
public final class PendingSheetModel {
    public let key: PendingKey
    /// The item as it was when the sheet opened (nil when it was already gone). What it asks never
    /// changes, so the sheet keeps showing it after the item left the pending set.
    public let opened: MachinePendingItem?

    /// The status this sheet's own last send ended with, kept after the center forgets it.
    private var ownResult: DecisionStatus?
    /// True while this sheet's send is out.
    private var sending = false

    @ObservationIgnored private let hub: MachineHub
    @ObservationIgnored private let center: DecisionCenter

    public init(key: PendingKey, hub: MachineHub, center: DecisionCenter) {
        self.key = key
        self.hub = hub
        self.center = center
        opened = hub.pendingItems.first { $0.id == key }
    }

    /// The item as the hub has it now; nil once it left the pending set.
    public var current: MachinePendingItem? {
        hub.pendingItems.first { $0.id == key }
    }

    public var status: DecisionStatus? {
        center.status[key] ?? ownResult
    }

    /// The Mac's session is live and synced (false while reconnecting).
    public var actionable: Bool {
        current?.actionable ?? false
    }

    /// The item was decided without this sheet: it left the pending set while this sheet had sent
    /// nothing (or only a send that failed), or the Mac answered `already_handled`.
    public var handledElsewhere: Bool {
        if sending { return false }
        switch status {
        case .handledElsewhere: return true
        case .sending, .done: return false
        case .failed, nil: return current == nil
        }
    }

    /// The send buttons are on: the item is pending and synced, and nothing is out or taken yet.
    public var canSend: Bool {
        guard !sending, actionable, !handledElsewhere else { return false }
        switch status {
        case .sending, .done, .handledElsewhere: return false
        case .failed, nil: return true
        }
    }

    /// Sends `decision` through the center, unless `canSend` is false.
    public func send(_ decision: LinkDecision) async {
        guard canSend else { return }
        sending = true
        await center.send(decision, for: key)
        ownResult = center.status[key]
        sending = false
    }
}
