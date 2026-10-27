import ShellXAppCore

/// What a question or plan sheet shows about its item's decision, copied from a
/// `PendingSheetModel` (render tests make it by hand).
struct PendingSheetState: Equatable {
    var status: DecisionStatus?
    var handledElsewhere = false
    /// The send buttons are on.
    var canSend = true
    /// The Mac is live and synced (false: "Reconnecting…").
    var actionable = true

    @MainActor
    init(_ model: PendingSheetModel) {
        status = model.status
        handledElsewhere = model.handledElsewhere
        canSend = model.canSend
        actionable = model.actionable
    }

    init(status: DecisionStatus? = nil, handledElsewhere: Bool = false, canSend: Bool = true, actionable: Bool = true) {
        self.status = status
        self.handledElsewhere = handledElsewhere
        self.canSend = canSend
        self.actionable = actionable
    }

    /// The status the sheet's status line shows: "handled elsewhere" also when the item left the
    /// set without a decision from here.
    var shownStatus: DecisionStatus? {
        handledElsewhere ? .handledElsewhere : status
    }
}
