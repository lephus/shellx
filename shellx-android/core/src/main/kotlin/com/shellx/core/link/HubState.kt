package com.shellx.core.link

import com.shellx.link.core.AgentState
import com.shellx.link.core.AgentSession

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

    private companion object {
        val REACHABLE = setOf(MachineLinkState.Online, MachineLinkState.Connecting, MachineLinkState.Reconnecting)

        /** Most recent activity first (none last), then by (machineId, sessionId). */
        val BY_ACTIVITY: Comparator<MachineSession> =
            compareByDescending<MachineSession> { it.session.lastActivityMs ?: Long.MIN_VALUE }
                .thenBy { it.machineId }
                .thenBy { it.session.sessionId }

        fun session(model: MachineModel, session: AgentSession): MachineSession =
            MachineSession(model.id, model.name, model.state == MachineLinkState.Online, session)
    }
}
