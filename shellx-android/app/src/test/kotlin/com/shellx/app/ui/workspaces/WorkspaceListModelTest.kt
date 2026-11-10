@file:OptIn(ExperimentalCoroutinesApi::class)

package com.shellx.app.ui.workspaces

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.testComposition
import com.shellx.app.testing.waitFor
import com.shellx.core.demo.FakeMac
import com.shellx.core.home.GoneRemovals
import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.SessionRef
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import java.io.IOException
import kotlin.time.Duration.Companion.seconds
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

/** The home's groups and which agent cards offer Close, over a hub connected to fake Macs (WorkspaceListActionsTests). */
@RunWith(AndroidJUnit4::class)
class WorkspaceListModelTest {
    @get:Rule val folder = TemporaryFolder()

    /** The real account's hub over [macs], launched as the app's first start does. */
    private suspend fun TestScope.hubOver(macs: List<FakeMac>): MachineHub {
        val t = testComposition(folder.root, macs = macs)
        t.composition.lifecycle.onStart()
        assertTrue(waitFor { t.composition.real.coordinator.hub.value != null })
        return t.composition.real.coordinator.hub.value!!
    }

    private fun workspace(name: String, order: Int = 0) = LinkWorkspace(
        workspaceId = "ws-$name", title = name, order = order,
        terminals = listOf(LinkTerminal(terminalId = "$name-t1", title = "zsh", order = 0, selected = true)),
    )

    private fun TestScope.macWithWorkspaces(names: List<String>, name: String = "MacBook Pro"): FakeMac =
        FakeMac(name, backgroundScope).apply { setWorkspaces(names.mapIndexed { i, n -> workspace(n, i) }) }

    /** A Mac with the workspace `shellx`, whose one tab runs the agent `claude` (session `s1`). */
    private fun TestScope.macWithAnAgent(name: String = "MacBook Pro", acceptsAgentClose: Boolean = true): FakeMac =
        FakeMac(name, backgroundScope, acceptsAgentClose = acceptsAgentClose).apply {
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

    private fun agentRef(mac: FakeMac) = SessionRef(mac.machine.machineId, "s1", "claude", "shellx")

    @Test
    fun groupsPutTheDefaultMacFirstAndFlagAnOldOne() {
        runTest {
            val modern = macWithWorkspaces(listOf("shellx", "web"), name = "MacBook Pro")
            val old = FakeMac("iMac", backgroundScope, servesWorkspaces = false)
            old.upsertSession(AgentSession("s1", "claude", "ws-x", "x", state = AgentState.WORKING))
            val hub = hubOver(listOf(modern, old))
            assertTrue(waitFor { hub.machines.size == 2 && hub.machines.all { it.state == MachineLinkState.Online } })
            hub.defaultMachineId = old.machine.machineId

            val groups = WorkspaceListModel.groups(hub.state.value, GoneRemovals.NONE)

            assertEquals("the default Mac is first", listOf("iMac", "MacBook Pro"), groups.map { it.name })
            assertEquals(listOf(true, false), groups.map { it.isDefault })
            assertEquals("an old Mac cannot list workspaces", listOf(false, true), groups.map { it.listsWorkspaces })
            assertEquals(listOf(false, true), groups.map { it.allowsControl })
            assertEquals(listOf(false, true), groups.map { it.canControl })
            assertEquals(listOf("shellx", "web"), groups[1].rows.map { it.title })
            assertEquals("the old Mac's sessions are all 'other'", listOf(1, 0), groups.map { it.otherSessionCount })
        }
    }

    @Test
    fun aMacNotOnlineYetIsNotCalledOld() {
        runTest {
            val mac = macWithWorkspaces(listOf("shellx"))
            // The Mac cannot be reached yet (review C m-2: read it before it is online, or the check never runs).
            mac.failNextConnects(IOException("offline"), 1000)
            val hub = hubOver(listOf(mac))
            assertTrue(waitFor { hub.machines.isNotEmpty() })
            // Before the first connection finishes, the Mac has not said what it lists.
            val before = WorkspaceListModel.groups(hub.state.value, GoneRemovals.NONE).single()
            assertTrue("not online yet: ${before.state}", before.state != MachineLinkState.Online)
            assertTrue("a Mac not online yet is not called old", before.listsWorkspaces)

            mac.failNextConnects(IOException("offline"), 0)
            assertTrue(waitFor(60.seconds) { hub.machines.firstOrNull()?.state == MachineLinkState.Online })
            assertEquals(true, WorkspaceListModel.groups(hub.state.value, GoneRemovals.NONE).first().listsWorkspaces)
        }
    }

    @Test
    fun onlyAnOnlineMacThatTakesAgentCloseOffersIt() {
        runTest {
            val modern = macWithAnAgent(name = "MacBook Pro")
            val old = macWithAnAgent(name = "iMac", acceptsAgentClose = false)
            val hub = hubOver(listOf(modern, old))
            assertTrue(waitFor { hub.machines.size == 2 && hub.machines.all { it.state == MachineLinkState.Online } })
            assertTrue(waitFor { hub.liveSessions.size == 2 && hub.workspaceRows(modern.machine.machineId).size == 1 })

            assertEquals(setOf(agentRef(modern)), WorkspaceListModel.closableAgents(hub))

            // The modern Mac goes away and does not come back.
            val id = modern.machine.machineId
            modern.failNextConnects(IOException("offline"), 1000)
            modern.dropLiveSessions()
            assertTrue(waitFor { hub.machines.first { it.id == id }.state != MachineLinkState.Online })
            assertTrue("it took agent.close when it was last online", hub.supportsAgentClose(id))
            assertEquals("no Close while the Mac is away", emptySet<SessionRef>(), WorkspaceListModel.closableAgents(hub))
        }
    }

    @Test
    fun onlyAnAgentWithAListedTabOffersClose() {
        runTest {
            val mac = FakeMac("MacBook Pro", backgroundScope)
            mac.setWorkspaces(
                listOf(
                    LinkWorkspace(
                        "ws-shellx", "shellx", 0,
                        terminals = listOf(
                            LinkTerminal("t1", "claude", 0, selected = true, sessionId = "s1"),
                            LinkTerminal("t2", "zsh", 1, selected = false, sessionId = "s3"),
                        ),
                    ),
                ),
            )
            // `s1` runs in a listed tab; `s2` over SSH, which no listed tab names; `s3` ended in its tab.
            mac.upsertSession(AgentSession("s1", "claude", "ws-shellx", "shellx", state = AgentState.WORKING))
            mac.upsertSession(AgentSession("s2", "claude", "", "", state = AgentState.WORKING))
            mac.upsertSession(AgentSession("s3", "claude", "ws-shellx", "shellx", state = AgentState.ENDED))
            val hub = hubOver(listOf(mac))
            val id = mac.machine.machineId
            assertTrue(
                waitFor {
                    hub.machines.firstOrNull()?.state == MachineLinkState.Online && hub.reachableSessions.size == 3 &&
                        hub.workspaceRows(id).size == 1
                },
            )
            val sessions = hub.reachableSessions.associateBy { it.session.sessionId }

            assertTrue(WorkspaceListActions.canClose(sessions.getValue("s1"), hub))
            assertFalse(
                "no listed tab names it: the Mac would answer not_found",
                WorkspaceListActions.canClose(sessions.getValue("s2"), hub),
            )
            assertFalse("its tab runs the shell now", WorkspaceListActions.canClose(sessions.getValue("s3"), hub))
            assertEquals(listOf("s2"), hub.otherSessions(id).map { it.session.sessionId })
            assertFalse(
                "no agent outside workspaces offers Close",
                hub.otherSessions(id).any { WorkspaceListActions.canClose(it, hub) },
            )
            // The home's swipe goes by the same rule.
            assertEquals(setOf(sessions.getValue("s1").ref), WorkspaceListModel.closableAgents(hub))
        }
    }
}
