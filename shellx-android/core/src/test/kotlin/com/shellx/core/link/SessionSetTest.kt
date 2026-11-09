package com.shellx.core.link

import com.shellx.core.testing.agentSession
import com.shellx.link.core.AgentState
import kotlin.test.Test
import kotlin.test.assertEquals

class SessionSetTest {
    @Test fun upsertAndRemove() {
        var set = SessionSet()
        set = set.reset(1, listOf(agentSession("s1", lastActivityMs = 100), agentSession("s2", lastActivityMs = 300)))
        // Most recent activity first.
        assertEquals(listOf("s2", "s1"), set.sessions.map { it.sessionId })

        val s1Busy = agentSession("s1", state = AgentState.NEEDS_INPUT, lastActivityMs = 500)
        var r = set.apply(2, listOf(s1Busy), listOf("s2")); set = r.value
        assertEquals(RevisionGate.Result.APPLIED, r.result)
        assertEquals(2, set.revision)
        assertEquals(listOf(s1Busy), set.sessions)

        r = set.apply(3, listOf(agentSession("s3", lastActivityMs = 200)), emptyList()); set = r.value
        assertEquals(RevisionGate.Result.APPLIED, r.result)
        assertEquals(listOf("s1", "s3"), set.sessions.map { it.sessionId })

        r = set.apply(3, emptyList(), listOf("s1")); set = r.value
        assertEquals(RevisionGate.Result.IGNORED, r.result)
        assertEquals(listOf("s1", "s3"), set.sessions.map { it.sessionId })
    }

    @Test fun listAnswerReplacesRevisionAfterMacRestart() {
        var set = SessionSet()
        set = set.reset(42, listOf(agentSession("s1")))

        // The Mac app restarted: its `agent.sessions` revision starts at 0 again. The answer replaces
        // the set's revision, so the next change (1) applies instead of looking already seen.
        set = set.reset(0, listOf(agentSession("s2")))
        assertEquals(0, set.revision)
        val r = set.apply(1, listOf(agentSession("s3")), emptyList()); set = r.value
        assertEquals(RevisionGate.Result.APPLIED, r.result)
        assertEquals(listOf("s2", "s3"), set.sessions.map { it.sessionId }.sorted())
    }

    @Test fun gapReported() {
        var set = SessionSet()
        set = set.reset(4, listOf(agentSession("s1")))

        var r = set.apply(6, listOf(agentSession("s2")), listOf("s1")); set = r.value
        assertEquals(RevisionGate.Result.GAP, r.result)
        assertEquals(4, set.revision)
        assertEquals(listOf("s1"), set.sessions.map { it.sessionId })
        r = set.apply(4, listOf(agentSession("s2")), emptyList()); set = r.value
        assertEquals(RevisionGate.Result.IGNORED, r.result)
    }
}
