package com.shellx.core.pending

import com.shellx.link.core.ExitPlanMode
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.PermissionMode

/** One thing a pending card lets the user do. `PendingItem.actions` lists the ones an item offers. */
sealed interface PendingAction {
    /** Permission: allow this one call (`once`). */
    data object AllowOnce : PendingAction

    /** Permission: refuse (`deny`). */
    data object Deny : PendingAction

    /** Permission: allow this kind of call from now on (`always`). */
    data object AllowAlways : PendingAction

    /** Permission: allow every tool from now on (`all`). */
    data object AllowAllTools : PendingAction

    /** Question: open the answer sheet. */
    data object Answer : PendingAction

    /** Plan: approve it in this mode. */
    data class ApprovePlan(val mode: ExitPlanMode) : PendingAction

    /** Plan: send it back with feedback (`deny` plus the user's text). */
    data object RevisePlan : PendingAction

    /** Plan: refuse it (`deny`, no feedback). */
    data object RejectPlan : PendingAction

    /** Nothing the phone can answer: the card says to open it on the Mac. */
    data object OpenOnMac : PendingAction

    /** The decision this action sends as it is; null when it needs more from a sheet ([Answer], [RevisePlan]) or
     *  sends nothing ([OpenOnMac]). */
    val decision: LinkDecision?
        get() = when (this) {
            AllowOnce -> LinkDecision.Permission(PermissionMode.ONCE)
            Deny -> LinkDecision.Permission(PermissionMode.DENY)
            AllowAlways -> LinkDecision.Permission(PermissionMode.ALWAYS)
            AllowAllTools -> LinkDecision.Permission(PermissionMode.ALL)
            is ApprovePlan -> LinkDecision.ExitPlan(mode, feedback = null)
            RejectPlan -> LinkDecision.ExitPlan(ExitPlanMode.DENY, feedback = null)
            Answer, RevisePlan, OpenOnMac -> null
        }
}
