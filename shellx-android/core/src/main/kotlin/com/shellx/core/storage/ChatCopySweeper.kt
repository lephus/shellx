package com.shellx.core.storage

import com.shellx.core.link.ChatUpdate
import com.shellx.core.link.MachineHub

/**
 * Drops a session's stored chat copy when its Mac resets the transcript (`chat.reset`, PROTOCOL.md section 4), whether
 * or not an agent screen follows that session: the copy is the old transcript's, and a screen opened later must show
 * the new one only. (A screen that is open does the same itself.)
 *
 * The signed-in screen runs it for as long as it is shown. It writes with a store writer of the account that started
 * it, so nothing is written after a sign-out wipe. Main-confined.
 */
class ChatCopySweeper(private val hub: MachineHub, private val store: ConversationStore) {
    /** Watches the hub until cancelled (or the hub stops). */
    suspend fun run() {
        // Subscribe first, so no reset falls between the subscription and the writer.
        val updates = hub.chatUpdates()
        val writer = store.writer()
        updates.collect { update -> if (update is ChatUpdate.Reset) writer.remove(StoreDocument.Thread(update.ref)) }
    }
}
