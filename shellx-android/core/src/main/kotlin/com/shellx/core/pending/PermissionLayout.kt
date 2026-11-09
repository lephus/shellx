package com.shellx.core.pending

/**
 * How a permission card lays out its actions (ruling P3-R4): Deny and Allow (`once`, the primary button) in the row,
 * the lasting grants ("Always allow", "All tools") in the "…" menu. A lasting grant is never the one-tap primary
 * button, also when the Mac does not offer `once`. The card only renders this.
 */
data class PermissionLayout(
    /** The buttons in the row, in order. */
    val buttons: List<PendingAction>,
    /** The actions in the "…" menu, in order. */
    val menu: List<PendingAction>,
) {
    companion object {
        /** The layout of the permission actions among [actions]; any other action is left out. */
        fun of(actions: List<PendingAction>): PermissionLayout = PermissionLayout(
            buttons = listOf(PendingAction.Deny, PendingAction.AllowOnce).filter { it in actions },
            menu = listOf(PendingAction.AllowAlways, PendingAction.AllowAllTools).filter { it in actions },
        )
    }
}
