package com.shellx.core.home

import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.MachineSession
import com.shellx.core.testing.agentSession
import com.shellx.core.testing.pendingItem
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Which group of the home each session goes in. */
class HomeFocusTest {
    private val nowMs = 1_800_000_000_000L

    private fun ms(ago: Double): Long = nowMs - (ago * 1000).toLong()

    private fun on(machine: String, session: AgentSession) = MachineSession(machine, machine, true, session)

    private fun request(
        id: String,
        machine: String = "m1",
        workspace: String = "shellx",
        agent: String = "claude",
        preview: String? = null,
    ): MachinePendingItem =
        MachinePendingItem(machine, machine, pendingItem(id, workspace = workspace).copy(agent = agent, toolInputPreview = preview), true)

    private fun make(
        sessions: List<MachineSession>,
        pending: List<MachinePendingItem> = emptyList(),
        finished: Map<String, Map<String, Long>> = emptyMap(),
    ): HomeFocus = HomeFocus.make(sessions, pending, finished, nowMs = nowMs, zone = ZoneId.of("UTC"))

    private fun ids(items: List<FocusItem>): List<String> = items.map { it.session.session.sessionId }

    @Test fun eachSessionGoesToItsGroup() {
        val sessions = listOf(
            on("m1", agentSession("s1", state = AgentState.NEEDS_INPUT)),
            on("m1", agentSession("s2", state = AgentState.WORKING)),
            on("m1", agentSession("s3", state = AgentState.IDLE)),
            on("m1", agentSession("s4", state = AgentState.IDLE)),
            on("m1", agentSession("s5", state = AgentState.ENDED, stateSinceMs = ms(ago = 3600.0))),
        )
        val focus = make(sessions, finished = mapOf("m1" to mapOf("s3" to nowMs - 600_000)))
        assertEquals(listOf("s1"), ids(focus.needsYou))
        assertEquals(listOf("s2"), ids(focus.running))
        assertEquals(listOf("s3"), ids(focus.justDone))
        assertEquals(listOf("s5"), ids(focus.ended))
        assertEquals(nowMs - 600_000, focus.justDone.firstOrNull()?.finishedAtMs)
        assertFalse(focus.isQuiet)
    }

    @Test fun quietWhenOnlyEndedOrNothing() {
        assertTrue(make(emptyList()).isQuiet)
        assertTrue(HomeFocus.EMPTY.isQuiet)
        val ended = on("m1", agentSession("s", state = AgentState.ENDED, stateSinceMs = ms(ago = 5.0)))
        assertTrue(make(listOf(ended)).isQuiet)
    }

    @Test fun justDoneLastsAnHour() {
        val s = listOf(on("m1", agentSession("s", state = AgentState.IDLE)))
        assertEquals(listOf("s"), ids(make(s, finished = mapOf("m1" to mapOf("s" to nowMs - 3_599_000))).justDone))
        assertEquals(emptyList(), ids(make(s, finished = mapOf("m1" to mapOf("s" to nowMs - 3_600_000))).justDone))
    }

    @Test fun endedLastsTwelveHours() {
        fun ended(age: Double): List<FocusItem> =
            make(listOf(on("m1", agentSession("s", state = AgentState.ENDED, stateSinceMs = ms(ago = age))))).ended
        assertEquals(listOf("s"), ids(ended(43_199.0)))
        assertEquals(emptyList(), ids(ended(43_200.0)))
    }

    @Test fun endedAgeFallsBackToLastActivity() {
        val s = agentSession("s", state = AgentState.ENDED, lastActivityMs = ms(ago = 60.0), stateSinceMs = null)
        assertEquals(listOf("s"), ids(make(listOf(on("m1", s))).ended))
    }

    @Test fun endedWithoutAnyTimeIsHidden() {
        val s = agentSession("s", state = AgentState.ENDED, lastActivityMs = null, stateSinceMs = null)
        assertTrue(make(listOf(on("m1", s))).ended.isEmpty())
    }

    @Test fun endedFromAMacClockAheadShows() {
        val s = agentSession("s", state = AgentState.ENDED, stateSinceMs = nowMs + 300_000)
        assertEquals(listOf("s"), ids(make(listOf(on("m1", s))).ended))
    }

    @Test fun endedIsNewestFirst() {
        val sessions = listOf(
            on("m1", agentSession("old", state = AgentState.ENDED, stateSinceMs = ms(ago = 7200.0))),
            on("m1", agentSession("new", state = AgentState.ENDED, stateSinceMs = ms(ago = 60.0))),
            on("m1", agentSession("mid", state = AgentState.ENDED, stateSinceMs = ms(ago = 600.0))),
        )
        assertEquals(listOf("new", "mid", "old"), ids(make(sessions).ended))
    }

    @Test fun theQuestionGoesToTheNewestWaitingSession() {
        val sessions = listOf(
            on("m1", agentSession("a", state = AgentState.NEEDS_INPUT, lastActivityMs = 5)),
            on("m1", agentSession("b", state = AgentState.NEEDS_INPUT, lastActivityMs = 9)),
        )
        val focus = make(sessions, pending = listOf(request("r1", preview = "Cho phép chạy xcodebuild?\nchi tiết")))
        assertEquals(2, focus.needsYou.size)
        assertEquals(listOf("b", "a"), ids(focus.needsYou))
        assertEquals("Cho phép chạy xcodebuild?", focus.needsYou[0].question)
        assertNull(focus.needsYou[1].question)
    }

    @Test fun theFirstMatchingRequestKeepsTheQuestion() {
        val sessions = listOf(on("m1", agentSession("a", state = AgentState.NEEDS_INPUT)))
        val focus = make(sessions, pending = listOf(request("r1", preview = "first"), request("r2", preview = "second")))
        assertEquals("first", focus.needsYou.firstOrNull()?.question)
    }

    @Test fun aRequestPromotesTheNewestLiveSession() {
        val sessions = listOf(
            on("m1", agentSession("s", state = AgentState.WORKING, lastActivityMs = 9)),
            on("m1", agentSession("e", state = AgentState.ENDED, lastActivityMs = 99)),
        )
        val focus = make(sessions, pending = listOf(request("r1", preview = "ok?")))
        assertEquals(listOf("s"), ids(focus.needsYou))
        assertEquals("ok?", focus.needsYou.firstOrNull()?.question)
        assertTrue(focus.running.isEmpty())
    }

    @Test fun aRequestMatchingNoSessionMakesNoCard() {
        val focus = make(listOf(on("m1", agentSession("s"))), pending = listOf(request("r1", workspace = "wf-123")))
        assertTrue(focus.needsYou.isEmpty())
        assertEquals(listOf("s"), ids(focus.running))
    }

    @Test fun requestsOfAnotherMacOrAgentDoNotMatch() {
        val s = on("m1", agentSession("s"))
        assertTrue(make(listOf(s), pending = listOf(request("r1", machine = "m2"))).needsYou.isEmpty())
        assertTrue(make(listOf(s), pending = listOf(request("r2", agent = "codex"))).needsYou.isEmpty())
    }

    @Test fun noSessionIsInTwoGroups() {
        val states = listOf(AgentState.IDLE, AgentState.WORKING, AgentState.NEEDS_INPUT, AgentState.ENDED, AgentState("x"))
        for (withRequest in listOf(false, true)) {
            val sessions = mutableListOf<MachineSession>()
            val finished = mutableMapOf<String, Long>()
            states.forEachIndexed { i, state ->
                sessions += on("m1", agentSession("s$i", state = state, lastActivityMs = i.toLong(), stateSinceMs = ms(ago = 10.0)))
                finished["s$i"] = nowMs - 10_000
            }
            val focus = make(sessions, pending = if (withRequest) listOf(request("r")) else emptyList(), finished = mapOf("m1" to finished))
            val all = (focus.needsYou + focus.running + focus.justDone + focus.ended).map { it.id }
            assertEquals(all.toSet().size, all.size)
        }
    }

    @Test fun namesAreDistinctAcrossTheTopGroups() {
        val a = agentSession("s1", state = AgentState.WORKING).copy(title = "Fix bug")
        val b = agentSession("s2", state = AgentState.NEEDS_INPUT).copy(title = "Fix bug")
        val focus = make(listOf(on("m1", a), on("m1", b)))
        assertEquals("Fix bug", focus.running.firstOrNull()?.name)
        assertEquals("Fix bug · #2", focus.needsYou.firstOrNull()?.name)
    }

    @Test fun theSameSessionIdOnTwoMacsIsTwoItems() {
        val focus = make(listOf(on("m1", agentSession("s")), on("m2", agentSession("s"))))
        assertEquals(2, focus.running.size)
        assertEquals(2, focus.running.map { it.id }.toSet().size)
        assertEquals(2, focus.running.map { it.name }.toSet().size)
    }
}
