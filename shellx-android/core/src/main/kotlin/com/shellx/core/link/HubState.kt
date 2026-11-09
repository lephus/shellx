package com.shellx.core.link

import com.shellx.core.workspaces.WorkspaceRow
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.ShellXLink

/** One snapshot of everything the hub shows. Derived values are computed once per instance (lazy, NONE). */
data class HubState(
    val machines: List<MachineModel> = emptyList(),
    /** True once `start()` read the vault, so an empty [machines] means "no Mac paired yet". */
    val isLoaded: Boolean = false,
    val storedDefaultMachineId: String? = null,
    /** machineId → sessionId → when the phone saw it finish (epoch ms), until the user looks or it works again. */
    val finishTimes: Map<String, Map<String, Long>> = emptyMap(),
    /** Items that left a Mac's list while the Mac was live and synced, newest last, at most HANDLED_MEMORY. */
    val handled: List<PendingKey> = emptyList(),
) {
    /** The Mac new messages go to when nothing else picks one: the stored one while it is paired, else the first Mac. */
    val defaultMachineId: String? by lazy(LazyThreadSafetyMode.NONE) {
        storedDefaultMachineId?.takeIf { id -> machines.any { it.id == id } } ?: machines.firstOrNull()?.id
    }

    /** The default Mac has answered with its workspace list: what `LAUNCH_TO_WORKSPACE_LIST` waits for. */
    val defaultMachineListedWorkspaces: Boolean by lazy(LazyThreadSafetyMode.NONE) {
        defaultMachineId?.let { machine(it)?.workspacesSupported } ?: false
    }

    /** Every Mac's pending requests, oldest first: by (createdAtMs, machineId, requestId). */
    val pendingItems: List<MachinePendingItem> by lazy(LazyThreadSafetyMode.NONE) {
        machines.flatMap { model ->
            model.pending.items.map { MachinePendingItem(model.id, model.name, it, model.pendingActionable) }
        }.sortedWith(
            compareBy<MachinePendingItem> { it.item.createdAtMs }.thenBy { it.machineId }.thenBy { it.item.requestId },
        )
    }

    /**
     * Every session that has not ended, on every Mac, most recent activity first. An offline Mac's sessions are its
     * last known ones, with `online` false.
     */
    val liveSessions: List<MachineSession> by lazy(LazyThreadSafetyMode.NONE) {
        machines.flatMap { model ->
            model.sessions.sessions.filter { it.state != AgentState.ENDED }.map { session(model, it) }
        }.sortedWith(BY_ACTIVITY)
    }

    /**
     * Every session, in every state, of the Macs that are online, connecting or reconnecting: a Mac that is back keeps
     * its sessions, with `online` false until it answers. A Mac that is offline contributes none. Ordered as
     * [liveSessions].
     */
    val reachableSessions: List<MachineSession> by lazy(LazyThreadSafetyMode.NONE) {
        machines.filter { it.state in REACHABLE }.flatMap { model ->
            model.sessions.sessions.map { session(model, it) }
        }.sortedWith(BY_ACTIVITY)
    }

    private val handledKeys: Set<PendingKey> by lazy(LazyThreadSafetyMode.NONE) { handled.toSet() }

    fun machine(id: String): MachineModel? = machines.firstOrNull { it.id == id }

    /**
     * True when the item left its Mac's list while the Mac was live and synced: the Mac's own list said it is no
     * longer pending, so it was decided (on the Mac, another phone, or by the agent). Items dropped because the link
     * went down, or the Mac removed this phone, are not.
     */
    fun leftWhileSynced(key: PendingKey): Boolean = key in handledKeys

    /**
     * The Mac's workspaces as rows, in the Mac's order, each with the state worked out from the Mac's sessions, pending
     * requests and [finishedSessionIds]. An offline Mac's rows are its last known ones. Empty for a Mac that lists no
     * workspaces, and for an unknown one.
     */
    fun workspaceRows(machineId: String): List<WorkspaceRow> {
        val model = machine(machineId) ?: return emptyList()
        val pending = model.pending.items.map { MachinePendingItem(model.id, model.name, it, model.pendingActionable) }
        return WorkspaceRow.rows(model.workspaces, model.sessions.sessions, pending, finishedSessionIds(machineId), machineId)
    }

    /**
     * The Mac's sessions that have not ended and that no terminal of its workspaces names (`LinkTerminal.sessionId`):
     * the ones with no terminal chip, among them sessions whose workspace is gone or was never named. Most recent
     * activity first.
     */
    fun otherSessions(machineId: String): List<MachineSession> {
        val model = machine(machineId) ?: return emptyList()
        val named = namedSessionIds(model)
        return model.sessions.sessions
            .filter { it.state != AgentState.ENDED && it.sessionId !in named }
            .map { session(model, it) }
    }

    /**
     * True when a terminal of the Mac's listed workspaces names the session: the Mac finds the session's tab there,
     * which an agent close needs. False for an unknown Mac.
     */
    fun hasListedTerminal(ref: SessionRef): Boolean =
        machine(ref.machineId)?.let { ref.sessionId in namedSessionIds(it) } ?: false

    /**
     * The Mac's sessions that finished a turn (went from working or waiting to idle) and have not started again since,
     * until `markSeen` clears their workspace or the one session. WorkspaceRow shows them as DONE. Only what this
     * launch saw; nothing is saved.
     */
    fun finishedSessionIds(machineId: String): Set<String> = finishTimes[machineId]?.keys?.toSet() ?: emptySet()

    /** True when the Mac listed `workspace_control` when it was last online. False for a Mac never online yet. */
    fun supportsWorkspaceControl(machineId: String): Boolean = listed(machineId, ShellXLink.WORKSPACE_CONTROL_FEATURE)

    /** True when the Mac listed `agent_close` when it was last online. False for a Mac never online yet. */
    fun supportsAgentClose(machineId: String): Boolean = listed(machineId, ShellXLink.AGENT_CLOSE_FEATURE)

    /** True when the Mac listed `terminal_close` when it was last online. False for a Mac never online yet. */
    fun supportsTerminalClose(machineId: String): Boolean = listed(machineId, ShellXLink.TERMINAL_CLOSE_FEATURE)

    /**
     * True when the Mac listed `attachments` when it was last online: the composer offers photos and files for its
     * sessions only then. False for a Mac never online yet.
     */
    fun acceptsAttachments(machineId: String): Boolean = listed(machineId, ShellXLink.ATTACHMENTS_FEATURE)

    private fun listed(machineId: String, feature: String): Boolean =
        machine(machineId)?.hostFeatures?.contains(feature) ?: false

    private companion object {
        val REACHABLE = setOf(MachineLinkState.Online, MachineLinkState.Connecting, MachineLinkState.Reconnecting)

        /** Most recent activity first (none last), then by (machineId, sessionId). */
        val BY_ACTIVITY: Comparator<MachineSession> =
            compareByDescending<MachineSession> { it.session.lastActivityMs ?: Long.MIN_VALUE }
                .thenBy { it.machineId }
                .thenBy { it.session.sessionId }

        fun session(model: MachineModel, session: AgentSession): MachineSession =
            MachineSession(model.id, model.name, model.state == MachineLinkState.Online, session)

        /** The sessions a terminal of the Mac's listed workspaces names. */
        fun namedSessionIds(model: MachineModel): Set<String> =
            model.workspaces.workspaces.flatMap { it.terminals }.mapNotNull { it.sessionId }.toSet()
    }
}
