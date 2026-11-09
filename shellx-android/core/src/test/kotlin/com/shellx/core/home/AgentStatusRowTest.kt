package com.shellx.core.home

import com.shellx.core.testing.liveSession
import com.shellx.link.core.AgentState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/** The "Agents · N" rows: how long each state has lasted, and in which order they show. */
class AgentStatusRowTest {
    private val nowMs: Long = 1_700_000_000_000

    @Test fun elapsedClampsNegative() {
        // The Mac's clock runs ahead of the phone's: the state seems to begin in the future.
        val ahead = liveSession("s1", activity = nowMs, since = nowMs + 5_000)
        assertEquals(Duration.ZERO, AgentStatusRow.of(ahead, nowMs).elapsed)

        val running = liveSession("s1", activity = nowMs, since = nowMs - 240_000)
        assertEquals(240.seconds, AgentStatusRow.of(running, nowMs).elapsed)
    }

    @Test fun elapsedNilWithoutSince() {
        val row = AgentStatusRow.of(liveSession("s1", activity = nowMs, since = null), nowMs)
        assertNull(row.elapsed)
    }

    @Test fun rowsOrderNeedsYouThenRunningThenDone() {
        val sessions = listOf(
            liveSession("done-new", state = AgentState.IDLE, activity = 900),
            liveSession("running-old", state = AgentState.WORKING, activity = 100),
            liveSession("unknown", state = AgentState("paused"), activity = 1_000),
            liveSession("needs-you", state = AgentState.NEEDS_INPUT, activity = 50),
            liveSession("running-new", mac = "m2", online = false, state = AgentState.WORKING, activity = 500),
            liveSession("done-old", state = AgentState.IDLE, activity = 200),
        )

        val rows = AgentStatusRow.rows(sessions, nowMs)

        assertEquals(
            listOf("needs-you", "running-new", "running-old", "done-new", "done-old", "unknown"),
            rows.map { it.ref.sessionId },
        )
        val offline = rows[1]
        assertEquals("Mac m2", offline.machineName)
        assertFalse(offline.online)
        assertEquals(AgentState.WORKING, offline.state)
        assertEquals(sessions[4].ref, offline.id)
    }
}
