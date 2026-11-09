package com.shellx.core.home

import com.shellx.core.testing.agentSession
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import kotlin.test.Test
import kotlin.test.assertEquals

/** Which sessions just finished: working or waiting on the user before, idle now. */
class SessionFinishDetectorTest {
    private fun session(id: String, state: AgentState, since: Long?): AgentSession =
        agentSession(id, state = state, stateSinceMs = since)

    @Test fun workingToIdleIsFinished() {
        val detector = SessionFinishDetector()
        val first = detector.observe("m1", listOf(session("s1", AgentState.WORKING, 1), session("s2", AgentState.NEEDS_INPUT, 1)))
        assertEquals(emptyList(), first)
        // Another Mac's list leaves m1's alone.
        assertEquals(emptyList(), detector.observe("m2", emptyList()))

        val finished = detector.observe("m1", listOf(session("s1", AgentState.IDLE, 2), session("s2", AgentState.IDLE, 3)))

        assertEquals(listOf("s1", "s2"), finished.map { it.sessionId })
        assertEquals(listOf("m1", "m1"), finished.map { it.machineId })
        assertEquals("claude", finished.firstOrNull()?.agent)
        assertEquals("shellx", finished.firstOrNull()?.workspaceTitle)
    }

    @Test fun finishedWhileAppClosedDetectedFromSaved() {
        val detector = SessionFinishDetector()
        detector.observe("m1", listOf(session("s1", AgentState.WORKING, 1)))

        // The app closes; the next launch reads the saved detector, then sees the Mac's list.
        val restored = detector.copy()
        val finished = restored.observe("m1", listOf(session("s1", AgentState.IDLE, 5)))

        assertEquals(listOf("s1"), finished.map { it.sessionId })
    }

    @Test fun sameFinishNotRepeatedAfterResync() {
        val detector = SessionFinishDetector()
        detector.observe("m1", listOf(session("s1", AgentState.WORKING, 1)))
        assertEquals(1, detector.observe("m1", listOf(session("s1", AgentState.IDLE, 2))).size)

        // A resync (a reconnect, a restarted Mac app) replays an older list, then the same finish.
        detector.observe("m1", listOf(session("s1", AgentState.WORKING, 1)))
        assertEquals(emptyList(), detector.observe("m1", listOf(session("s1", AgentState.IDLE, 2))))
        // Also after a relaunch.
        val restored = detector.copy()
        restored.observe("m1", listOf(session("s1", AgentState.WORKING, 1)))
        assertEquals(emptyList(), restored.observe("m1", listOf(session("s1", AgentState.IDLE, 2))))

        // The next turn's finish is a new one.
        restored.observe("m1", listOf(session("s1", AgentState.WORKING, 3)))
        assertEquals(1, restored.observe("m1", listOf(session("s1", AgentState.IDLE, 4))).size)
    }

    @Test fun idleToIdleNotFinished() {
        val detector = SessionFinishDetector()
        assertEquals(emptyList(), detector.observe("m1", listOf(session("s1", AgentState.IDLE, 1))))
        assertEquals(emptyList(), detector.observe("m1", listOf(session("s1", AgentState.IDLE, 2))))
        // A session first seen idle, and a session that ended instead of finishing.
        detector.observe("m1", listOf(session("s1", AgentState.IDLE, 2), session("s2", AgentState.WORKING, 1)))
        val changed = detector.observe("m1", listOf(session("s2", AgentState.ENDED, 3), session("s3", AgentState.IDLE, 3)))
        assertEquals(emptyList(), changed)
    }

    @Test fun keepsTheTwoNewestFinishesPerSession() {
        val detector = SessionFinishDetector()
        for (turn in 0 until 5) {
            val start = (turn * 10).toLong()
            detector.observe("m1", listOf(session("s1", AgentState.WORKING, start + 1)))
            assertEquals(1, detector.observe("m1", listOf(session("s1", AgentState.IDLE, start + 2))).size)
        }
        assertEquals(2, detector.reportedCount("m1"))

        // The latest finish is still known: a replay of it stays quiet.
        detector.observe("m1", listOf(session("s1", AgentState.WORKING, 41)))
        assertEquals(emptyList(), detector.observe("m1", listOf(session("s1", AgentState.IDLE, 42))))
    }

    @Test fun forgetsMacsNoLongerPaired() {
        val detector = SessionFinishDetector()
        detector.observe("m1", listOf(session("s1", AgentState.WORKING, 1)))
        detector.observe("m2", listOf(session("s1", AgentState.WORKING, 1)))

        detector.retain(setOf("m2"))

        assertEquals(emptyList(), detector.observe("m1", listOf(session("s1", AgentState.IDLE, 2))))
        assertEquals(1, detector.observe("m2", listOf(session("s1", AgentState.IDLE, 2))).size)
    }
}
