package com.shellx.core.agent

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Whether a new entry scrolls the chat down: only while its bottom shows. Otherwise the user is reading older entries,
 * and a "New messages" notice says that more came below.
 */
class ChatFollowTest {
    @Test fun followsOnlyWhileTheBottomShows() {
        val follow = ChatFollow()
        assertTrue(follow.newest("e1"), "the first entries come into view")
        assertTrue(follow.newest("e2"), "at the bottom: follow")
        assertFalse(follow.newest("e2"), "the same newest entry (an older page came in above): nothing")
        assertFalse(follow.hasUnseen)

        // The user scrolls up to read.
        follow.bottomVisible(false)
        assertFalse(follow.newest("e3"), "never pulled down while reading")
        assertTrue(follow.hasUnseen)
        assertFalse(follow.newest("e4"))
        assertTrue(follow.hasUnseen)

        // Scrolling back down by hand clears the notice, and new entries are followed again.
        follow.bottomVisible(true)
        assertFalse(follow.hasUnseen)
        assertTrue(follow.newest("e5"))

        // Tapping "New messages" jumps down and clears it.
        follow.bottomVisible(false)
        follow.newest("e6")
        assertTrue(follow.hasUnseen)
        follow.jumpedToBottom()
        assertFalse(follow.hasUnseen)
        assertTrue(follow.newest("e7"))

        // A chat that empties has nothing to follow.
        assertFalse(follow.newest(null))
        assertFalse(follow.hasUnseen)
    }
}
