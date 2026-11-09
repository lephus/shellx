package com.shellx.core.agent

/**
 * Whether an agent's chat follows its newest entry. It does only while the bottom of the chat is on screen. Otherwise
 * the user is reading older entries: the chat stays where it is, and [hasUnseen] asks the screen to offer
 * "New messages ↓". Mutable (Conventions): one owner, not thread-safe.
 */
class ChatFollow {
    /** The bottom of the chat is on screen (true until the screen says otherwise). */
    var atBottom: Boolean = true
        private set

    /** Newer entries came while the user read older ones. */
    var hasUnseen: Boolean = false
        private set

    private var newestId: String? = null

    /** The bottom of the chat came into view (the user scrolled down to it) or left it. */
    fun bottomVisible(visible: Boolean) {
        atBottom = visible
        if (visible) hasUnseen = false
    }

    /**
     * The chat's newest entry is now [id]. Returns true when the chat should scroll to it; a new entry while the user
     * reads older ones only sets [hasUnseen]. The same newest entry (an older page came in above, an entry grew in
     * place) changes nothing.
     */
    fun newest(id: String?): Boolean {
        if (id == newestId) return false
        newestId = id
        if (id == null) {
            hasUnseen = false
            return false
        }
        if (atBottom) return true
        hasUnseen = true
        return false
    }

    /** The user tapped "New messages": the chat scrolls to the bottom. */
    fun jumpedToBottom() {
        atBottom = true
        hasUnseen = false
    }
}
