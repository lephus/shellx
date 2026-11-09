package com.shellx.app.ui.pending

import com.shellx.core.pending.DecisionStatus
import com.shellx.core.pending.PendingSheetModel

/**
 * What a question or plan sheet shows about its item's decision, copied from a [PendingSheetModel] (render tests make it
 * by hand). The iPhone's `PendingSheetState`; not 3C's `com.shellx.core.pending.PendingSheetState`, which is the model's
 * own part.
 */
data class PendingSheetState(
    val status: DecisionStatus? = null,
    val handledElsewhere: Boolean = false,
    /** The send buttons are on. */
    val canSend: Boolean = true,
    /** The Mac is live and synced (false: "Reconnecting…", or what [linkNote] says). */
    val actionable: Boolean = true,
    /** Why nothing can be sent while the item is not handled elsewhere: the Mac is reconnecting, offline, or must be
     *  paired again. */
    val linkNote: PendingSheetModel.LinkNote? = null,
) {
    /** The status the sheet's status line shows: "handled elsewhere" also when the item left the set without a
     *  decision from here. */
    val shownStatus: DecisionStatus? get() = if (handledElsewhere) DecisionStatus.HandledElsewhere else status

    companion object {
        /** The model's values now (read them after collecting the hub's, the center's and the model's state). */
        fun of(model: PendingSheetModel): PendingSheetState = PendingSheetState(
            status = model.status, handledElsewhere = model.handledElsewhere, canSend = model.canSend,
            actionable = model.actionable, linkNote = model.linkNote,
        )
    }
}
