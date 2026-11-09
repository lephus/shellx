package com.shellx.core.link

import com.shellx.link.core.ChatEntry

/**
 * One chat push from a Mac, as `MachineHub.chatUpdates` hands it out, in the order it arrived: new or changed entries
 * of a session, or the reset of that session's transcript (PROTOCOL.md section 4, `chat.entries` and `chat.reset`).
 */
sealed interface ChatUpdate {
    /** The session the push is about. */
    val ref: SessionRef

    /** The upserted entries; empty for [Reset]. */
    val entries: List<ChatEntry>

    /** New or changed entries (upserts by `ChatEntry.id`). */
    data class Upsert(override val ref: SessionRef, override val entries: List<ChatEntry>) : ChatUpdate

    /**
     * The transcript was replaced: every entry held for the session, its `seq` values and any history answer asked
     * for before are void. Pushes after this one belong to the new transcript.
     */
    data class Reset(override val ref: SessionRef) : ChatUpdate {
        override val entries: List<ChatEntry> get() = emptyList()
    }
}
