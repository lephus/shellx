package com.shellx.core.link

import com.shellx.link.core.PendingItem

/** Names one pending request across all Macs. */
data class PendingKey(val machineId: String, val requestId: String)

/**
 * A pending request with the Mac it came from. [actionable] is false while the Mac's session is not live and synced:
 * the card shows, its buttons do not act. The Mac's name never prints.
 */
data class MachinePendingItem(val machineId: String, val machineName: String, val item: PendingItem, val actionable: Boolean) {
    val id: PendingKey get() = PendingKey(machineId, item.requestId)

    /** Whether the request comes from [workspaceId] on [machineId]: one agent screen's requests. */
    fun isIn(machineId: String, workspaceId: String): Boolean =
        this.machineId == machineId && item.workspaceId == workspaceId

    override fun toString(): String =
        "MachinePendingItem(machineId=$machineId, machineName=<redacted>, item=$item, actionable=$actionable)"
}
