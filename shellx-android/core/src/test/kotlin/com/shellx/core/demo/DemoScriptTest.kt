package com.shellx.core.demo

import com.shellx.core.link.MachineHub
import com.shellx.core.testing.ManualClock
import com.shellx.core.testing.ManualSleeper
import com.shellx.core.testing.eventually
import com.shellx.core.testing.hubRig
import com.shellx.core.testing.instantSleep
import com.shellx.core.workspaces.WorkspaceState
import com.shellx.link.core.AgentState
import com.shellx.link.core.PendingKind
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest

/** The demo's "Mac giả": what the app shows without an account or a real Mac. */
class DemoScriptTest {
    private val clock = ManualClock()

    private fun TestScope.mac(): FakeMac = FakeMac("Mac giả", backgroundScope, nowMs = clock::nowMs)

    private suspend fun TestScope.hub(mac: FakeMac): MachineHub =
        hubRig(listOf(mac), sleep = instantSleep, clock = clock, start = true).hub

    private fun kinds(hub: MachineHub): List<PendingKind> = hub.pendingItems.map { it.item.kind }

    @Test fun setUpServesTwoWorkingSessionsAndEveryChatKind() { runTest {
        val mac = mac()
        val script = DemoScript(mac, clock::nowMs)
        script.setUp()
        val hub = hub(mac)

        val ready = eventually { hub.liveSessions.size == 3 }
        assertTrue(ready)
        assertEquals(listOf(AgentState.WORKING, AgentState.WORKING, AgentState.IDLE), hub.liveSessions.map { it.session.state })
        assertEquals(4, hub.reachableSessions.size, "and one that ended two hours ago")
        assertEquals(setOf("claude"), hub.liveSessions.map { it.session.agent }.toSet())

        val roles = HashSet<String>()
        val entryKinds = HashSet<String>()
        for (session in hub.liveSessions) {
            val page = hub.chatHistory(session.ref, beforeSeq = null, limit = 50)
            roles += page.entries.map { it.role.wire }
            entryKinds += page.entries.map { it.kind.wire }
        }
        assertEquals(setOf("user", "agent", "system"), roles)
        assertEquals(setOf("prose", "thought", "tool_use", "status"), entryKinds)
    } }

    @Test fun setUpServesWorkspacesThatHoldBothSessions() { runTest {
        val mac = mac()
        val script = DemoScript(mac, clock::nowMs)
        script.setUp()
        val hub = hub(mac)
        val id = mac.machine.machineId

        val ready = eventually { hub.workspaceRows(id).size == 3 && hub.liveSessions.size == 3 }

        assertTrue(ready)
        assertEquals(listOf("shellx", "web", "docs"), hub.workspaceRows(id).map { it.title })
        assertEquals(listOf(WorkspaceState.RUNNING, WorkspaceState.RUNNING, WorkspaceState.IDLE), hub.workspaceRows(id).map { it.state })
        // The two working sessions sit in a terminal; the idle second "Pairing sheet" is left for the "other sessions"
        // list, and the ended one is on the Ended page.
        assertEquals(listOf("demo-shellx-2"), hub.otherSessions(id).map { it.session.sessionId })

        script.step(0)
        val asks = eventually {
            hub.workspaceRows(id).map { it.state } == listOf(WorkspaceState.NEEDS_YOU, WorkspaceState.RUNNING, WorkspaceState.IDLE)
        }
        assertTrue(asks, "a pending request names the workspace of its session")
    } }

    @Test fun stepsAddPermissionQuestionPlanInTurnAndFlipSessions() { runTest {
        val mac = mac()
        val script = DemoScript(mac, clock::nowMs)
        script.setUp()
        val hub = hub(mac)
        eventually { hub.liveSessions.size == 3 }

        for (index in 0 until 3) script.step(index)

        val all = eventually { hub.pendingItems.size == 3 }
        assertTrue(all)
        assertEquals(listOf(PendingKind.PERMISSION, PendingKind.QUESTION, PendingKind.EXIT_PLAN), kinds(hub))
        val question = hub.pendingItems[1].item
        assertEquals(emptyList(), question.modes)
        assertFalse(question.questions?.firstOrNull()?.options?.isEmpty() ?: true)
        assertNotNull(hub.pendingItems[2].item.planPreview)
        val flipped = eventually { hub.liveSessions.any { it.session.state == AgentState.IDLE } }
        assertTrue(flipped, "a session went from working to idle")
    } }

    @Test fun pendingStaysBounded() { runTest {
        val mac = mac()
        val script = DemoScript(mac, clock::nowMs)
        script.setUp()
        val hub = hub(mac)

        for (index in 0 until DemoScript.MAX_PENDING + 4) script.step(index)

        val capped = eventually { hub.pendingItems.size == DemoScript.MAX_PENDING }
        assertTrue(capped, "${hub.pendingItems.size}")
    } }

    @Test fun runStepsEveryInterval() { runTest {
        val mac = mac()
        val script = DemoScript(mac, clock::nowMs)
        val sleeper = ManualSleeper()
        val hub = hub(mac)
        val running = backgroundScope.launch { script.run(sleeper.sleep) }

        val waiting = eventually { sleeper.waiting == listOf(DemoScript.INTERVAL) }
        assertTrue(waiting)
        assertEquals(0, hub.pendingItems.size, "the first request comes after one interval")
        sleeper.release()
        val first = eventually { kinds(hub) == listOf(PendingKind.PERMISSION) }
        assertTrue(first)

        running.cancel()
        running.join()
    } }

    @Test fun runAfterStepsGoesOnNumbering() { runTest {
        val mac = mac()
        val script = DemoScript(mac, clock::nowMs)
        script.setUp()
        for (index in 0 until 3) script.step(index)
        val hub = hub(mac)
        eventually { hub.liveSessions.size == 3 }
        val sleeper = ManualSleeper()
        val running = backgroundScope.launch { script.run(sleeper.sleep, setUp = false, from = 3) }

        eventually { sleeper.waiting == listOf(DemoScript.INTERVAL) }
        sleeper.release()
        val fourth = eventually { hub.pendingItems.size == 4 }
        assertTrue(fourth)

        // Step 3 flips the second session and adds a new reply; it does not overwrite step 1's.
        val web = assertNotNull(hub.liveSessions.firstOrNull { it.session.sessionId == "demo-web" })
        val page = hub.chatHistory(web.ref, beforeSeq = null, limit = 50)
        val ticks = page.entries.filter { it.id.startsWith("demo-web-tick-") }.map { it.seq }
        assertEquals(listOf(101L, 103L), ticks)
        running.cancel()
        running.join()
    } }
}
