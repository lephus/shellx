package com.shellx.app.ui.nav

import com.shellx.core.link.SessionRef
import com.shellx.core.workspaces.WorkspaceRef

/**
 * Where 3D's screens go. The app's one is Task 16's `NavControllerNavigator`; tests record the calls.
 *
 * Every `open…` navigates with `launchSingleTop`, which compares destinations, not arguments: opening a sibling page of
 * the destination on top (another agent from an agent page) replaces that page and keeps its ViewModels. A screen that
 * opens a page of its own route compares the target with the top entry instead (3D review m-4).
 */
interface ShellXNavigator {
    fun openWorkspace(ref: WorkspaceRef)

    fun openAgent(ref: SessionRef)

    fun openPending(only: WorkspaceRef? = null)

    fun openSessions(kind: SessionListKind, machineId: String? = null)

    fun openMachines()

    fun openSettings()

    /** The pairing model is cancelled (a fresh scan), then the page opens (the iPhone's openPairing). */
    fun openPairing()

    /** The page opens on the model's current step (a link took it to the confirmation). */
    fun showPairing()

    fun back()
}
