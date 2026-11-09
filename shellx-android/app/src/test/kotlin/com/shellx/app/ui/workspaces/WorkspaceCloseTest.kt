@file:OptIn(ExperimentalCoroutinesApi::class)

package com.shellx.app.ui.workspaces

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.testComposition
import com.shellx.app.testing.waitFor
import com.shellx.core.demo.FakeMac
import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.SessionRef
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import com.shellx.link.core.WorkspaceControlOutcome
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith

/** The one Close Agent and Close Tab path, against fake Macs (WorkspaceListActionsTests' close tests). */
@RunWith(AndroidJUnit4::class)
class WorkspaceCloseTest {
    @get:Rule val folder = TemporaryFolder()

    private val alerts = mutableListOf<WorkspaceAlert>()
    private val tasks = mutableListOf<Deferred<WorkspaceFeedback>>()

    private suspend fun TestScope.hubOver(macs: List<FakeMac>): MachineHub {
        val t = testComposition(folder.root, macs = macs)
        t.composition.lifecycle.onStart()
        assertTrue(waitFor { t.composition.real.coordinator.hub.value != null })
        return t.composition.real.coordinator.hub.value!!
    }

    /** A Mac with the workspace `shellx`, whose one tab runs the agent `claude` (session `s1`). */
    private fun TestScope.macWithAnAgent(): FakeMac = FakeMac("MacBook Pro", backgroundScope).apply {
        setWorkspaces(
            listOf(
                LinkWorkspace(
                    "ws-shellx", "shellx", 0,
                    terminals = listOf(LinkTerminal("shellx-t1", "claude", 0, selected = true, sessionId = "s1")),
                ),
            ),
        )
        upsertSession(AgentSession("s1", "claude", "ws-shellx", "shellx", state = AgentState.WORKING))
    }

    /** A Mac with the workspace `shellx`: a shell `t1` and the agent `claude` (session `s1`) in `t2`. */
    private fun TestScope.macWithTabs(name: String = "MacBook Pro", acceptsTerminalClose: Boolean = true): FakeMac =
        FakeMac(name, backgroundScope, acceptsTerminalClose = acceptsTerminalClose).apply {
            setWorkspaces(
                listOf(
                    LinkWorkspace(
                        "ws-shellx", "shellx", 0,
                        terminals = listOf(
                            LinkTerminal("t1", "zsh", 0, selected = true),
                            LinkTerminal("t2", "claude", 1, selected = false, sessionId = "s1"),
                        ),
                    ),
                ),
            )
            upsertSession(AgentSession("s1", "claude", "ws-shellx", "shellx", state = AgentState.WORKING))
        }

    private fun agentRef(mac: FakeMac) = SessionRef(mac.machine.machineId, "s1", "claude", "shellx")

    private fun closeAgent(mac: FakeMac, hub: MachineHub) {
        WorkspaceListActions.closeAgent(agentRef(mac), hub, alerts::add)?.let(tasks::add)
    }

    private fun closeTab(mac: FakeMac, hub: MachineHub, terminalId: String) {
        WorkspaceListActions.closeTab(mac.machine.machineId, "ws-shellx", terminalId, hub, alerts::add)?.let(tasks::add)
    }

    private fun tabs(hub: MachineHub, mac: FakeMac): List<String> =
        hub.machines.firstOrNull { it.id == mac.machine.machineId }?.workspaces?.workspace("ws-shellx")?.terminals
            ?.map { it.terminalId } ?: emptyList()

    private fun terminalCloses(mac: FakeMac): List<String> = mac.terminalCloses.map { "${it.workspaceId}/${it.terminalId}" }

    private suspend fun TestScope.running(hub: MachineHub): Boolean =
        waitFor { hub.machines.firstOrNull()?.state == MachineLinkState.Online && hub.liveSessions.size == 1 }

    @Test
    fun closeAgentAsksTheMacOnce() {
        runTest {
            val mac = macWithAnAgent()
            val hub = hubOver(listOf(mac))
            assertTrue(running(hub))
            mac.holdWorkspaceControl()

            closeAgent(mac, hub)
            closeAgent(mac, hub)
            assertEquals("the second tap started nothing", 1, tasks.size)
            assertTrue(waitFor { mac.agentCloses == listOf("s1") })
            mac.releaseWorkspaceControl()
            val feedback = tasks.last().await()

            assertEquals("the card leaves for Ended by the Mac's push", WorkspaceFeedback.None, feedback)
            assertEquals(listOf("s1"), mac.agentCloses)
            assertEquals(emptyList<WorkspaceAlert>(), alerts)
            assertTrue(waitFor { hub.liveSessions.isEmpty() })

            // Answered: Close goes out again (and the Mac says this agent has stopped).
            closeAgent(mac, hub)
            assertEquals(2, tasks.size)
            assertEquals(WorkspaceFeedback.Alert(WorkspaceAlert.AGENT_NOT_CLOSABLE), tasks.last().await())
        }
    }

    @Test
    fun closeAgentTheMacCannotCloseIsAnAlert() {
        runTest {
            val mac = macWithAnAgent()
            val hub = hubOver(listOf(mac))
            assertTrue(running(hub))
            val lists = mac.workspaceListCount
            mac.setNextAgentCloseOutcome(WorkspaceControlOutcome.NOT_FOUND)

            closeAgent(mac, hub)
            val feedback = tasks.last().await()

            assertEquals(WorkspaceFeedback.Alert(WorkspaceAlert.AGENT_NOT_CLOSABLE), feedback)
            assertEquals(listOf(WorkspaceAlert.AGENT_NOT_CLOSABLE), alerts)
            assertEquals("an agent the Mac cannot close is not a workspace list gone stale", lists, mac.workspaceListCount)
            assertEquals("the agent still runs", 1, hub.liveSessions.size)
        }
    }

    @Test
    fun closeAgentTheMacRefusesSaysWhy() {
        runTest {
            val mac = macWithAnAgent()
            val hub = hubOver(listOf(mac))
            assertTrue(running(hub))
            // Remote control blocked, or the agent's tab is the last of a pinned or kept-open workspace.
            mac.setNextAgentCloseOutcome(WorkspaceControlOutcome.REFUSED)

            closeAgent(mac, hub)
            val feedback = tasks.last().await()

            assertEquals(WorkspaceFeedback.Alert(WorkspaceAlert.REFUSED_CLOSE_AGENT), feedback)
            assertEquals(listOf(WorkspaceAlert.REFUSED_CLOSE_AGENT), alerts)
            assertEquals("the agent still runs", 1, hub.liveSessions.size)
        }
    }

    @Test
    fun closeTabAsksTheMacOnce() {
        runTest {
            val mac = macWithTabs()
            val hub = hubOver(listOf(mac))
            assertTrue(waitFor { hub.machines.firstOrNull()?.state == MachineLinkState.Online && tabs(hub, mac) == listOf("t1", "t2") })
            mac.holdWorkspaceControl()

            // A long-press's Close Tab… and the menu's, on the same tab, both confirmed.
            closeTab(mac, hub, "t1")
            closeTab(mac, hub, "t1")
            assertEquals("the second close started nothing", 1, tasks.size)
            assertTrue(waitFor { terminalCloses(mac) == listOf("ws-shellx/t1") })
            // Another tab is another close.
            closeTab(mac, hub, "t2")
            assertEquals(2, tasks.size)
            mac.releaseWorkspaceControl()
            for (task in tasks.toList()) task.await()

            val calls = terminalCloses(mac)
            assertEquals(setOf("ws-shellx/t1", "ws-shellx/t2"), calls.toSet())
            assertEquals("exactly one terminal.close for t1", 1, calls.count { it == "ws-shellx/t1" })
            assertEquals(emptyList<WorkspaceAlert>(), alerts)

            // Answered: Close Tab goes out again (and the Mac says the tab is no longer there).
            val before = tasks.size
            closeTab(mac, hub, "t1")
            assertEquals(before + 1, tasks.size)
            assertEquals(WorkspaceFeedback.Alert(WorkspaceAlert.TAB_NOT_CLOSABLE), tasks.last().await())
        }
    }

    @Test
    fun closeTabTheMacCannotCloseIsAnAlert() {
        runTest {
            val mac = macWithTabs()
            val hub = hubOver(listOf(mac))
            assertTrue(waitFor { hub.machines.firstOrNull()?.state == MachineLinkState.Online && tabs(hub, mac) == listOf("t1", "t2") })
            val lists = mac.workspaceListCount
            mac.setNextTerminalCloseOutcome(WorkspaceControlOutcome.NOT_FOUND)

            closeTab(mac, hub, "t1")
            val feedback = tasks.last().await()

            assertEquals(WorkspaceFeedback.Alert(WorkspaceAlert.TAB_NOT_CLOSABLE), feedback)
            assertEquals(listOf(WorkspaceAlert.TAB_NOT_CLOSABLE), alerts)
            assertEquals("said, not refreshed quietly", lists, mac.workspaceListCount)
            assertEquals(listOf("t1", "t2"), tabs(hub, mac))
        }
    }

    @Test
    fun closeTabTheMacRefusesSaysWhy() {
        runTest {
            val mac = macWithTabs()
            val hub = hubOver(listOf(mac))
            assertTrue(waitFor { hub.machines.firstOrNull()?.state == MachineLinkState.Online && tabs(hub, mac) == listOf("t1", "t2") })
            // Remote control blocked, or the last tab of a pinned or kept-open workspace.
            mac.setNextTerminalCloseOutcome(WorkspaceControlOutcome.REFUSED)

            closeTab(mac, hub, "t1")
            val feedback = tasks.last().await()

            assertEquals(WorkspaceFeedback.Alert(WorkspaceAlert.REFUSED_CLOSE_TAB), feedback)
            assertEquals(listOf(WorkspaceAlert.REFUSED_CLOSE_TAB), alerts)
            assertEquals("the tab stays", listOf("t1", "t2"), tabs(hub, mac))
        }
    }

    @Test
    fun aMacWithoutTerminalCloseOffersNoCloseTab() {
        runTest {
            val modern = macWithTabs(name = "MacBook Pro")
            val old = macWithTabs(name = "iMac", acceptsTerminalClose = false)
            val hub = hubOver(listOf(modern, old))
            assertTrue(
                waitFor {
                    hub.machines.size == 2 && hub.machines.all { it.state == MachineLinkState.Online } &&
                        tabs(hub, old) == listOf("t1", "t2")
                },
            )

            assertTrue(WorkspaceListActions.canCloseTab(modern.machine.machineId, hub))
            assertFalse(WorkspaceListActions.canCloseTab(old.machine.machineId, hub))

            // Nothing reaches such a Mac even if a close were started: only the calls the phone made can show it.
            val before = old.phoneCallCount
            WorkspaceListActions.closeTab(old.machine.machineId, "ws-shellx", "t1", hub, alerts::add)?.let(tasks::add)
            tasks.last().await()
            assertEquals("no call is sent to a Mac from before terminal_close", before, old.phoneCallCount)
            assertTrue(old.terminalCloses.isEmpty())
            assertEquals(listOf("t1", "t2"), tabs(hub, old))
        }
    }
}
