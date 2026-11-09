package com.shellx.core.link

import com.shellx.link.account.PairedMachine

/**
 * What the UI shows for one paired Mac (MachineModel.swift), as an immutable snapshot inside [HubState]. [MachineHub]
 * is the only writer: it replaces the model with `copy(…)`. The Mac's name never prints.
 */
data class MachineModel(
    val machine: PairedMachine,
    /** The Mac's name: the paired one, then the relay's when `refreshGrants()` sees it renamed. */
    val name: String = machine.name,
    val state: MachineLinkState = MachineLinkState.Connecting,
    val pending: PendingSet = PendingSet(),
    /** False while the session is not live and synced: cards show, their buttons do not act. */
    val pendingActionable: Boolean = false,
    val sessions: SessionSet = SessionSet(),
    /** False when the Mac has no session list (an older ShellX). True until known. */
    val sessionsSupported: Boolean = true,
    /** The Mac's workspaces; the last known list while the Mac reconnects. */
    val workspaces: WorkspaceSet = WorkspaceSet(),
    /** True when the Mac listed the `workspaces` feature when it was last online and answered with its list. */
    val workspacesSupported: Boolean = false,
    /** What the Mac listed in `welcome.features` when it was last online (empty until then); kept while it reconnects. */
    val hostFeatures: Set<String> = emptySet(),
) {
    /** The Mac's machineId. */
    val id: String get() = machine.machineId

    override fun toString(): String = "MachineModel(id=$id, name=<redacted>, state=$state, pending=$pending, " +
        "pendingActionable=$pendingActionable, sessions=$sessions, sessionsSupported=$sessionsSupported, " +
        "workspaces=$workspaces, workspacesSupported=$workspacesSupported, hostFeatures=$hostFeatures)"
}
