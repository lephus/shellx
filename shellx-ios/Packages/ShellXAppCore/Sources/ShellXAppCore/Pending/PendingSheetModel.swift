import Foundation
import Observation
import ShellXLinkCore

/// What the question and plan sheets need about their one item: whether it can still be answered
/// from here, and what became of the answer.
///
/// The sheet stays open while the user reads and types, so the item may be decided elsewhere
/// meanwhile (on the Mac, on another phone): then `handledElsewhere` turns true and nothing can be
/// sent any more (Review Focus 2).
///
/// An item also leaves the hub's list when its Mac goes offline, removes this iPhone or changes its
/// key. That is not a decision: the sheet keeps what was typed, sends nothing, and says why
/// (`linkNote`) until the Mac is back with the item, or its synced list shows it was decided.
@MainActor @Observable
public final class PendingSheetModel {
    /// Why nothing can be sent from the sheet right now, while its item was not handled elsewhere.
    public enum LinkNote: Equatable, Sendable {
        /// The session ended; the link is coming back ("Reconnecting…").
        case reconnecting
        /// The Mac could not be reached ("<Mac> is offline · Not sent").
        case offline
        /// The Mac removed this iPhone, its key changed, or it is no longer paired.
        case needsPairing
        /// The Mac speaks another protocol version.
        case needsUpdate
    }

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

    /// The item was decided without this sheet: while this sheet had sent nothing (or only a send
    /// that failed), it left the Mac's list while the Mac was live and synced, or the Mac's synced
    /// list no longer has it; or the Mac answered `already_handled`. An item dropped because the
    /// link went down does not count.
    public var handledElsewhere: Bool {
        if sending { return false }
        switch status {
        case .handledElsewhere: return true
        case .sending, .done: return false
        case .failed, nil:
            guard current == nil else { return false }
            return hub.leftWhileSynced(key) || macSynced
        }
    }

    /// Why nothing can be sent while the item is neither sendable nor handled elsewhere; nil when
    /// the item is live and synced, or was handled elsewhere.
    public var linkNote: LinkNote? {
        guard !actionable, !handledElsewhere else { return nil }
        guard let machine else { return .needsPairing }
        switch machine.state {
        case .revoked, .hostKeyChanged: return .needsPairing
        case .needsUpdate: return .needsUpdate
        case .offline: return .offline
        case .connecting, .reconnecting, .online: return .reconnecting
        }
    }

    /// The item's Mac; nil once it is no longer paired.
    private var machine: MachineModel? {
        hub.machines.first { $0.id == key.machineID }
    }

    /// The Mac's pending list is live and synced: an item missing from it is no longer pending there.
    private var macSynced: Bool {
        guard let machine else { return false }
        return machine.state == .online && machine.pendingActionable
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
