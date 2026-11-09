package com.shellx.core.pending

/** Where the user's decision on one pending item stands. No status: nothing was sent. */
sealed interface DecisionStatus {
    /** On its way to the Mac; other taps on the item are ignored. */
    data object Sending : DecisionStatus

    /** The waiting agent took it: the card is gone. */
    data object Done : DecisionStatus

    /** The item was decided before this decision arrived (on the Mac, another phone, or it expired). The card says
     *  so, then goes. */
    data object HandledElsewhere : DecisionStatus

    /** Not taken; the card stays and says why. */
    data class Failed(val failure: DecisionFailure) : DecisionStatus
}
