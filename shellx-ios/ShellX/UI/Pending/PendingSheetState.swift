import ShellXAppCore

/// What a question or plan sheet shows about its item's decision, copied from a
/// `PendingSheetModel` (render tests make it by hand).
struct PendingSheetState: Equatable {
    var status: DecisionStatus?
    var handledElsewhere = false
    /// The send buttons are on.
    var canSend = true
    /// The Mac is live and synced (false: "Reconnecting…", or what `linkNote` says).
    var actionable = true
    /// Why nothing can be sent while the item is not handled elsewhere: the Mac is reconnecting,
    /// offline, or must be paired again.
    var linkNote: PendingSheetModel.LinkNote?

    @MainActor
    init(_ model: PendingSheetModel) {
        status = model.status
        handledElsewhere = model.handledElsewhere
        canSend = model.canSend
        actionable = model.actionable
        linkNote = model.linkNote
    }

    init(
        status: DecisionStatus? = nil, handledElsewhere: Bool = false, canSend: Bool = true, actionable: Bool = true,
        linkNote: PendingSheetModel.LinkNote? = nil
    ) {
        self.status = status
        self.handledElsewhere = handledElsewhere
        self.canSend = canSend
        self.actionable = actionable
        self.linkNote = linkNote
    }

    /// The status the sheet's status line shows: "handled elsewhere" also when the item left the
    /// set without a decision from here.
    var shownStatus: DecisionStatus? {
        handledElsewhere ? .handledElsewhere : status
    }
}
