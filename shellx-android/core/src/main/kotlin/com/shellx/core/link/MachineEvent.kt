package com.shellx.core.link

import com.shellx.link.core.ChatEntry

/** What a [MachineConnection] reports, in order (MachineEvent.swift). */
sealed interface MachineEvent {
    data class State(val state: MachineLinkState) : MachineEvent

    /** The optional capabilities the Mac listed in `welcome.features` for the new session, just before its Online. */
    data class Features(val features: Set<String>) : MachineEvent

    /** The pending set. [actionable] is false whenever the set is not backed by a live, synced session. */
    data class Pending(val set: PendingSet, val actionable: Boolean) : MachineEvent

    /** The session list. [supported] is false when the Mac has no session list (an older ShellX). */
    data class Sessions(val set: SessionSet, val supported: Boolean) : MachineEvent

    /** The workspace list. [supported] is false when the Mac lists none (an older ShellX). */
    data class Workspaces(val set: WorkspaceSet, val supported: Boolean) : MachineEvent

    /** New or changed chat entries of one session (upserts by [ChatEntry.id]). ChatEntry prints no text. */
    data class Chat(val sessionId: String, val entries: List<ChatEntry>) : MachineEvent

    /** The session's transcript was replaced (`chat.reset`), in order with its [Chat] events. */
    data class ChatReset(val sessionId: String) : MachineEvent

    /** The relay refused the account token. The connection has stopped; the owner signs the user out. */
    data object SignedOut : MachineEvent
}
