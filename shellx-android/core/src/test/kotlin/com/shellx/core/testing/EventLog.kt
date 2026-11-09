package com.shellx.core.testing

import com.shellx.core.link.MachineEvent
import com.shellx.core.link.MachineLinkState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

/** Collects a connection's events in [scope] and keeps them for checks (EventLog in AsyncTestSupport.swift). Thread-safe. */
class EventLog(events: Flow<MachineEvent>, scope: CoroutineScope) {
    private val lock = Any()
    private val stateList = mutableListOf<MachineLinkState>()
    private val pendingList = mutableListOf<MachineEvent.Pending>()
    private val sessionList = mutableListOf<MachineEvent.Sessions>()
    private val workspaceList = mutableListOf<MachineEvent.Workspaces>()
    private val featureList = mutableListOf<Set<String>>()
    private var chatCount = 0
    private var resetCount = 0
    private var signedOutCount = 0
    private var isFinished = false

    init {
        scope.launch {
            events.collect { add(it) }
            synchronized(lock) { isFinished = true }
        }
    }

    val states: List<MachineLinkState> get() = synchronized(lock) { stateList.toList() }
    val state: MachineLinkState? get() = states.lastOrNull()
    val pendingEvents: List<MachineEvent.Pending> get() = synchronized(lock) { pendingList.toList() }
    val pending: MachineEvent.Pending? get() = pendingEvents.lastOrNull()
    val pendingIds: List<String> get() = pending?.set?.items?.map { it.requestId } ?: emptyList()
    val sessions: MachineEvent.Sessions? get() = synchronized(lock) { sessionList.lastOrNull() }
    val sessionIds: List<String> get() = sessions?.set?.sessions?.map { it.sessionId } ?: emptyList()
    val workspaceEvents: List<MachineEvent.Workspaces> get() = synchronized(lock) { workspaceList.toList() }
    val workspaces: MachineEvent.Workspaces? get() = workspaceEvents.lastOrNull()
    val workspaceIds: List<String> get() = workspaces?.set?.workspaces?.map { it.workspaceId } ?: emptyList()
    val features: Set<String>? get() = synchronized(lock) { featureList.lastOrNull() }

    /** Chat entries seen, over every `Chat` event. */
    val chatEntries: Int get() = synchronized(lock) { chatCount }
    val chatResets: Int get() = synchronized(lock) { resetCount }
    val signedOut: Int get() = synchronized(lock) { signedOutCount }

    /** True once the connection finished its event stream. */
    val finished: Boolean get() = synchronized(lock) { isFinished }

    val isOnline: Boolean get() = state == MachineLinkState.Online
    val isOffline: Boolean get() = state is MachineLinkState.Offline

    private fun add(event: MachineEvent) {
        synchronized(lock) {
            when (event) {
                is MachineEvent.State -> stateList += event.state
                is MachineEvent.Features -> featureList += event.features
                is MachineEvent.Pending -> pendingList += event
                is MachineEvent.Sessions -> sessionList += event
                is MachineEvent.Workspaces -> workspaceList += event
                is MachineEvent.Chat -> chatCount += event.entries.size
                is MachineEvent.ChatReset -> resetCount += 1
                MachineEvent.SignedOut -> signedOutCount += 1
            }
        }
    }
}
