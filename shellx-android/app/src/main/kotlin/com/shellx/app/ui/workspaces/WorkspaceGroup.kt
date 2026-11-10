package com.shellx.app.ui.workspaces

import com.shellx.core.link.MachineLinkState
import com.shellx.core.workspaces.WorkspaceRow

/** One Mac's group on the home (`WorkspaceGroup` in `WorkspaceListScreen.swift`). */
data class WorkspaceGroup(
    val id: String,
    val name: String,
    val state: MachineLinkState,
    val isDefault: Boolean,
    val rows: List<WorkspaceRow>,
    /** The Mac listed the `workspace_control` feature: it takes make, rename and close. */
    val allowsControl: Boolean,
    /** False when the Mac is online but lists no workspaces: a ShellX from before them. */
    val listsWorkspaces: Boolean,
    /** How many sessions no workspace row accounts for (the agents outside workspaces). */
    val otherSessionCount: Int,
) {
    /** What the group shows under its header. */
    enum class Listing {
        /** Nothing: the Mac is out of reach, and its header says why. */
        HIDDEN,

        /** A notice in place of the cards: the Mac is online but its ShellX lists no workspaces. */
        UPDATE_MAC,

        /** A line saying the Mac has no workspace. */
        EMPTY,

        /** A card per workspace. */
        ROWS,
    }

    val showsRows: Boolean get() = rowsShow(state)

    /** Commands reach the Mac: it is online and takes them. */
    val canControl: Boolean get() = state == MachineLinkState.Online && allowsControl

    val listing: Listing
        get() = when {
            !showsRows -> Listing.HIDDEN
            !listsWorkspaces -> Listing.UPDATE_MAC
            rows.isEmpty() && state == MachineLinkState.Online -> Listing.EMPTY
            else -> Listing.ROWS
        }

    /** The last row, "Agents outside workspaces · N". */
    val showsOtherSessions: Boolean get() = showsRows && otherSessionCount > 0

    companion object {
        /** Rows show for a Mac that is, or was a moment ago, online; any other Mac shows only why it has none. */
        fun rowsShow(state: MachineLinkState): Boolean = when (state) {
            MachineLinkState.Online, MachineLinkState.Connecting, MachineLinkState.Reconnecting -> true
            is MachineLinkState.Offline, MachineLinkState.Revoked, MachineLinkState.HostKeyChanged,
            MachineLinkState.NeedsUpdate,
            -> false
        }
    }
}
