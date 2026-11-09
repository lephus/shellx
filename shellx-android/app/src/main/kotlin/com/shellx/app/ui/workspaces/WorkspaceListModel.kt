package com.shellx.app.ui.workspaces

import com.shellx.core.home.GoneRemovalStore
import com.shellx.core.home.GoneRemovals
import com.shellx.core.link.HubState
import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.SessionRef

/** What the home shows of the hub (`WorkspaceListView.swift`'s `groups`, `closableAgents` and `removableAgents`). */
object WorkspaceListModel {
    /** The hub's Macs as groups, the default Mac first and the others in the order they were paired. A Mac's
     *  "Agents outside workspaces · N" counts the sessions its page lists: none that [removed] hides. */
    fun groups(hub: HubState, removed: GoneRemovals): List<WorkspaceGroup> {
        val defaultId = hub.defaultMachineId
        val models = hub.machines.filter { it.id == defaultId } + hub.machines.filter { it.id != defaultId }
        return models.map { model ->
            WorkspaceGroup(
                id = model.id,
                name = model.name,
                state = model.state,
                isDefault = model.id == defaultId,
                rows = hub.workspaceRows(model.id),
                allowsControl = hub.supportsWorkspaceControl(model.id),
                // A Mac not online yet has not said what it lists: no "update ShellX" before it has.
                listsWorkspaces = model.workspacesSupported || model.state != MachineLinkState.Online,
                otherSessionCount = OtherSessionsModel.sessions(hub, model.id, removed).size,
            )
        }
    }

    /** The agents whose cards swipe to Close: the ones [WorkspaceListActions.canClose] offers, on a Mac online now. */
    fun closableAgents(hub: MachineHub): Set<SessionRef> =
        hub.reachableSessions.filter { it.online && WorkspaceListActions.canClose(it, hub) }.map { it.ref }.toSet()

    /** The agents whose cards swipe to "Remove from This Phone": the ones an agent screen saw answered `not_found` this
     *  run, while their Mac reports them as it did then. A live session never is one. */
    fun removableAgents(hub: HubState, removals: GoneRemovalStore): Set<SessionRef> =
        removals.removable(hub.reachableSessions)
}
