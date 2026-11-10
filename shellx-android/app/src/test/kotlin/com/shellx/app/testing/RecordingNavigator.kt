package com.shellx.app.testing

import com.shellx.app.ui.nav.SessionListKind
import com.shellx.app.ui.nav.ShellXNavigator
import com.shellx.core.link.SessionRef
import com.shellx.core.workspaces.WorkspaceRef

/**
 * A navigator that records each call: "workspace:<m>/<w>", "agent:<m>/<s>", "pending", "pending:<m>/<w>",
 * "sessions:ended", "sessions:other:<m>", "machines", "settings", "pairing", "showPairing", "back".
 */
class RecordingNavigator : ShellXNavigator {
    private val recorded = mutableListOf<String>()

    val calls: List<String> get() = synchronized(recorded) { recorded.toList() }

    private fun record(call: String) {
        synchronized(recorded) { recorded += call }
    }

    override fun openWorkspace(ref: WorkspaceRef) = record("workspace:${ref.machineId}/${ref.workspaceId}")

    override fun openAgent(ref: SessionRef) = record("agent:${ref.machineId}/${ref.sessionId}")

    override fun openPending(only: WorkspaceRef?) =
        record(if (only == null) "pending" else "pending:${only.machineId}/${only.workspaceId}")

    override fun openSessions(kind: SessionListKind, machineId: String?) =
        record(listOfNotNull("sessions", kind.wire, machineId).joinToString(":"))

    override fun openMachines() = record("machines")

    override fun openSettings() = record("settings")

    override fun openPairing() = record("pairing")

    override fun showPairing() = record("showPairing")

    override fun back() = record("back")
}
