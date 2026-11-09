package com.shellx.core.pending

import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.MachineModel
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.PendingKey
import com.shellx.link.core.LinkDecision
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** A pending sheet's own part ([PendingSheetModel.state]). */
data class PendingSheetState(
    /** The status this sheet's own last send ended with, kept after the center forgets it. */
    val ownResult: DecisionStatus? = null,
    /** True while this sheet's send is out. */
    val sending: Boolean = false,
)

/**
 * What the question and plan sheets need about their one item: whether it can still be answered from here, and what
 * became of the answer (PendingSheetModel.swift).
 *
 * The sheet stays open while the user reads and types, so the item may be decided elsewhere meanwhile (on the Mac, on
 * another phone): then [handledElsewhere] turns true and nothing can be sent any more. An item also leaves the hub's
 * list when its Mac goes offline, removes this phone or changes its key. That is not a decision: the sheet keeps what
 * was typed, sends nothing, and says why ([linkNote]) until the Mac is back with the item, or its synced list shows it
 * was decided.
 *
 * Main-confined. Derived getters read [state], hub.state and center.state.
 */
class PendingSheetModel(val key: PendingKey, private val hub: MachineHub, private val center: DecisionCenter) {
    /** Why nothing can be sent from the sheet right now, while its item was not handled elsewhere. */
    enum class LinkNote {
        /** The session ended; the link is coming back ("Reconnecting…"). */
        RECONNECTING,

        /** The Mac could not be reached ("<Mac> is offline · Not sent"). */
        OFFLINE,

        /** The Mac removed this phone, its key changed, or it is no longer paired. */
        NEEDS_PAIRING,

        /** The Mac speaks another protocol version. */
        NEEDS_UPDATE,
    }

    /** The item as it was when the sheet opened (null when it was already gone). What it asks never changes, so the
     *  sheet keeps showing it after the item left the pending set. */
    val opened: MachinePendingItem? = hub.pendingItems.firstOrNull { it.id == key }

    private val _state = MutableStateFlow(PendingSheetState())
    val state: StateFlow<PendingSheetState> = _state.asStateFlow()

    /** The item as the hub has it now; null once it left the pending set. */
    val current: MachinePendingItem? get() = hub.pendingItems.firstOrNull { it.id == key }

    val status: DecisionStatus? get() = center.status[key] ?: state.value.ownResult

    /** The Mac's session is live and synced (false while reconnecting). */
    val actionable: Boolean get() = current?.actionable ?: false

    /**
     * The item was decided without this sheet: while this sheet had sent nothing (or only a send that failed), it left
     * the Mac's list while the Mac was live and synced, or the Mac's synced list no longer has it; or the Mac answered
     * `already_handled`. An item dropped because the link went down does not count.
     */
    val handledElsewhere: Boolean
        get() {
            if (state.value.sending) return false
            return when (status) {
                DecisionStatus.HandledElsewhere -> true
                DecisionStatus.Sending, DecisionStatus.Done -> false
                is DecisionStatus.Failed, null -> current == null && (hub.leftWhileSynced(key) || macSynced)
            }
        }

    /** Why nothing can be sent while the item is neither sendable nor handled elsewhere; null when the item is live and
     *  synced, or was handled elsewhere. */
    val linkNote: LinkNote?
        get() {
            if (actionable || handledElsewhere) return null
            val machine = machine ?: return LinkNote.NEEDS_PAIRING
            return when (machine.state) {
                MachineLinkState.Revoked, MachineLinkState.HostKeyChanged -> LinkNote.NEEDS_PAIRING
                MachineLinkState.NeedsUpdate -> LinkNote.NEEDS_UPDATE
                is MachineLinkState.Offline -> LinkNote.OFFLINE
                MachineLinkState.Connecting, MachineLinkState.Reconnecting, MachineLinkState.Online -> LinkNote.RECONNECTING
            }
        }

    /** The send buttons are on: the item is pending and synced, and nothing is out or taken yet. */
    val canSend: Boolean
        get() {
            if (state.value.sending || !actionable || handledElsewhere) return false
            return when (status) {
                DecisionStatus.Sending, DecisionStatus.Done, DecisionStatus.HandledElsewhere -> false
                is DecisionStatus.Failed, null -> true
            }
        }

    /** The item's Mac; null once it is no longer paired. */
    private val machine: MachineModel? get() = hub.machines.firstOrNull { it.id == key.machineId }

    /** The Mac's pending list is live and synced: an item missing from it is no longer pending there. */
    private val macSynced: Boolean
        get() {
            val machine = machine ?: return false
            return machine.state == MachineLinkState.Online && machine.pendingActionable
        }

    /**
     * Sends [decision] through the center, unless [canSend] is false. The sheet's own result is set when the center's
     * work ends, also when the caller was cancelled meanwhile (review 3a m-1): until then [PendingSheetState.sending]
     * stays true.
     */
    suspend fun send(decision: LinkDecision) {
        if (!canSend) return
        _state.update { it.copy(sending = true) }
        center.send(decision, key) { final -> _state.value = PendingSheetState(ownResult = final, sending = false) }
    }
}
