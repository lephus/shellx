@file:OptIn(ExperimentalCoroutinesApi::class)

package com.shellx.app.ui.workspaces

import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.SignedInScope
import com.shellx.app.testing.RecordingNavigator
import com.shellx.app.testing.testComposition
import com.shellx.app.testing.waitFor
import com.shellx.core.demo.FakeMac
import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachineLinkState
import com.shellx.core.workspaces.WorkspaceRef
import com.shellx.core.workspaces.WorkspaceState
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import com.shellx.link.core.WorkspaceControlOutcome
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith

/**
 * The home's controls as `WorkspaceListActions.make` wires them to the signed-in scope, run one by one against fake
 * Macs (WorkspaceListActionsTests' make-based tests): each reaches the hub call it stands for and does with the answer
 * what WorkspaceFeedback says.
 */
@RunWith(AndroidJUnit4::class)
class WorkspaceListActionsTest {
    @get:Rule val folder = TemporaryFolder()

    private class Rig(
        val scope: SignedInScope,
        val nav: RecordingNavigator,
        val alerts: MutableList<WorkspaceAlert>,
        val tasks: MutableList<Deferred<WorkspaceFeedback>>,
        val creating: MutableState<Boolean>,
        val actions: WorkspaceListScreenActions,
    ) {
        val hub: MachineHub get() = scope.hub

        /** The feedback of the command the last action started. */
        suspend fun lastFeedback(): WorkspaceFeedback = tasks.last().await()
    }

    /** A signed-in scope over a hub connected to [macs], made as the app's first start makes it. */
    private suspend fun TestScope.makeRig(macs: List<FakeMac>): Rig {
        val t = testComposition(folder.root, macs = macs)
        t.composition.lifecycle.onStart()
        assertTrue(waitFor { t.composition.real.scopes.current.value != null })
        val scope = t.composition.real.scopes.current.value!!
        val nav = RecordingNavigator()
        val alerts = mutableListOf<WorkspaceAlert>()
        val tasks = mutableListOf<Deferred<WorkspaceFeedback>>()
        val creating = mutableStateOf(false)
        val actions = WorkspaceListActions.make(scope, nav, alerts::add, creating) { tasks += it }
        return Rig(scope, nav, alerts, tasks, creating, actions)
    }

    private fun workspace(name: String, order: Int = 0) = LinkWorkspace(
        workspaceId = "ws-$name", title = name, order = order,
        terminals = listOf(LinkTerminal(terminalId = "$name-t1", title = "zsh", order = 0, selected = true)),
    )

    private fun TestScope.macWithWorkspaces(names: List<String>, name: String = "MacBook Pro"): FakeMac =
        FakeMac(name, backgroundScope).apply { setWorkspaces(names.mapIndexed { i, n -> workspace(n, i) }) }

    private fun ref(mac: FakeMac, name: String) = WorkspaceRef(mac.machine.machineId, "ws-$name")

    private fun titles(rig: Rig, mac: FakeMac): List<String> = rig.hub.workspaceRows(mac.machine.machineId).map { it.title }

    private suspend fun TestScope.online(rig: Rig): Boolean =
        waitFor { rig.hub.machines.firstOrNull()?.state == MachineLinkState.Online }

    // Screens

    @Test
    fun controlsPushTheirScreens() {
        runTest {
            val mac = macWithWorkspaces(listOf("shellx"))
            val rig = makeRig(listOf(mac))
            val id = mac.machine.machineId

            rig.actions.openWorkspace(ref(mac, "shellx"))
            rig.actions.openPending()
            rig.actions.openSettings()
            rig.actions.openMachines()
            rig.actions.openOtherSessions(id)

            assertEquals(listOf("workspace:$id/ws-shellx", "pending", "settings", "machines", "sessions:other:$id"), rig.nav.calls)
        }
    }

    @Test
    fun endedFoldPushesTheEndedPage() {
        runTest {
            val rig = makeRig(listOf(macWithWorkspaces(listOf("shellx"))))

            rig.actions.openEnded()

            assertEquals(listOf("sessions:ended"), rig.nav.calls)
        }
    }

    @Test
    fun openingAWorkspaceMarksItSeen() {
        runTest {
            val mac = macWithWorkspaces(listOf("shellx"))
            val session = AgentSession("s1", "claude", "ws-shellx", "shellx", state = AgentState.WORKING)
            mac.upsertSession(session)
            val rig = makeRig(listOf(mac))
            val id = mac.machine.machineId
            assertTrue(waitFor { rig.hub.workspaceRows(id).map { it.state } == listOf(WorkspaceState.RUNNING) })

            // The agent finishes its turn: the card says so until the workspace is opened.
            mac.upsertSession(session.copy(state = AgentState.IDLE))
            assertTrue(waitFor { rig.hub.workspaceRows(id).map { it.state } == listOf(WorkspaceState.DONE) })

            rig.actions.openWorkspace(ref(mac, "shellx"))

            assertEquals(listOf(WorkspaceState.IDLE), rig.hub.workspaceRows(id).map { it.state })
        }
    }

    // Commands

    @Test
    fun createOpensTheNewWorkspace() {
        runTest {
            val mac = macWithWorkspaces(listOf("shellx"))
            val rig = makeRig(listOf(mac))
            val id = mac.machine.machineId
            assertTrue(online(rig))

            rig.actions.create(id)
            val feedback = rig.lastFeedback()

            assertEquals(WorkspaceFeedback.Open(WorkspaceRef(id, "ws-new-1")), feedback)
            assertEquals(listOf("workspace:$id/ws-new-1"), rig.nav.calls)
            assertEquals(emptyList<WorkspaceAlert>(), rig.alerts)
            assertFalse("＋ works again once the Mac answered", rig.creating.value)
            assertEquals(listOf("create"), mac.workspaceCalls)
            assertTrue(titles(rig, mac).toString(), waitFor { titles(rig, mac) == listOf("shellx", "Workspace 1") })
        }
    }

    @Test
    fun aSecondTapOnCreateWaitsForTheFirst() {
        runTest {
            val mac = macWithWorkspaces(listOf("shellx"))
            val rig = makeRig(listOf(mac))
            val id = mac.machine.machineId
            assertTrue(online(rig))
            mac.holdWorkspaceControl()

            rig.actions.create(id)
            assertTrue(rig.creating.value)
            rig.actions.create(id)
            assertEquals("the second tap started nothing", 1, rig.tasks.size)
            assertTrue(waitFor { mac.workspaceCalls == listOf("create") })
            mac.releaseWorkspaceControl()
            rig.lastFeedback()

            assertEquals(listOf("create"), mac.workspaceCalls)
            assertFalse(rig.creating.value)
        }
    }

    /** Review C m-1: a ＋ tapped after the hub's scope ended never starts, and ＋ works again all the same. */
    @Test
    fun plusWorksAgainWhenTheHubStoppedBeforeTheCreate() {
        runTest {
            val mac = macWithWorkspaces(listOf("shellx"))
            val rig = makeRig(listOf(mac))
            assertTrue(online(rig))
            rig.hub.scope.cancel()

            rig.actions.create(mac.machine.machineId)
            assertTrue(waitFor { rig.tasks.size == 1 && rig.tasks.last().isCompleted })

            assertTrue("it never ran", rig.tasks.last().isCancelled)
            assertFalse("＋ is on again", rig.creating.value)
            assertEquals(emptyList<String>(), mac.workspaceCalls)
        }
    }

    @Test
    fun renameChangesTheRowByPush() {
        runTest {
            val mac = macWithWorkspaces(listOf("shellx", "web"))
            val rig = makeRig(listOf(mac))
            assertTrue(waitFor { titles(rig, mac) == listOf("shellx", "web") })

            rig.actions.rename(ref(mac, "web"), "landing")
            val feedback = rig.lastFeedback()

            assertEquals(WorkspaceFeedback.None, feedback)
            assertEquals(listOf("rename:ws-web:landing"), mac.workspaceCalls)
            assertTrue(titles(rig, mac).toString(), waitFor { titles(rig, mac) == listOf("shellx", "landing") })
            assertEquals(emptyList<WorkspaceAlert>(), rig.alerts)
        }
    }

    @Test
    fun closeRemovesTheRowByPush() {
        runTest {
            val mac = macWithWorkspaces(listOf("shellx", "web"))
            val rig = makeRig(listOf(mac))
            assertTrue(waitFor { titles(rig, mac) == listOf("shellx", "web") })

            rig.actions.close(ref(mac, "web"))
            val feedback = rig.lastFeedback()

            assertEquals(WorkspaceFeedback.None, feedback)
            assertEquals(listOf("close:ws-web"), mac.workspaceCalls)
            assertTrue(titles(rig, mac).toString(), waitFor { titles(rig, mac) == listOf("shellx") })
        }
    }

    @Test
    fun closingTheLastWorkspaceIsAnAlert() {
        runTest {
            val mac = macWithWorkspaces(listOf("shellx"))
            val rig = makeRig(listOf(mac))
            assertTrue(waitFor { titles(rig, mac) == listOf("shellx") })

            rig.actions.close(ref(mac, "shellx"))
            val feedback = rig.lastFeedback()

            assertEquals(WorkspaceFeedback.Alert(WorkspaceAlert.REFUSED_CLOSE), feedback)
            assertEquals(listOf(WorkspaceAlert.REFUSED_CLOSE), rig.alerts)
            assertEquals("the row stays", listOf("shellx"), titles(rig, mac))
        }
    }

    @Test
    fun renameBlockedByTheMacIsAnAlert() {
        runTest {
            val mac = macWithWorkspaces(listOf("shellx"))
            val rig = makeRig(listOf(mac))
            assertTrue(waitFor { titles(rig, mac) == listOf("shellx") })
            mac.setNextWorkspaceOutcome(WorkspaceControlOutcome.REFUSED)

            rig.actions.rename(ref(mac, "shellx"), "x")
            rig.lastFeedback()

            assertEquals(listOf(WorkspaceAlert.REFUSED_CONTROL), rig.alerts)
        }
    }

    @Test
    fun aWorkspaceTheMacDoesNotHaveRefreshesTheListQuietly() {
        runTest {
            val mac = macWithWorkspaces(listOf("shellx"))
            val rig = makeRig(listOf(mac))
            assertTrue(waitFor { titles(rig, mac) == listOf("shellx") })
            val before = mac.workspaceListCount

            rig.actions.rename(WorkspaceRef(mac.machine.machineId, "ws-ghost"), "x")
            val feedback = rig.lastFeedback()

            assertEquals(WorkspaceFeedback.Refresh, feedback)
            assertEquals("no word to the user", emptyList<WorkspaceAlert>(), rig.alerts)
            assertEquals("the Mac was asked for its list again", before + 1, mac.workspaceListCount)
        }
    }

    @Test
    fun aMacThatIsNotOnlineAnswersOfflineWithAnAlert() {
        runTest {
            val mac = macWithWorkspaces(listOf("shellx"))
            val rig = makeRig(listOf(mac))

            rig.actions.create("mac-unknown")
            val feedback = rig.lastFeedback()

            assertEquals(WorkspaceFeedback.Alert(WorkspaceAlert.OFFLINE), feedback)
            assertEquals(listOf(WorkspaceAlert.OFFLINE), rig.alerts)
            assertFalse(rig.creating.value)
            assertEquals(emptyList<String>(), mac.workspaceCalls)
        }
    }

    @Test
    fun pullToRefreshAsksTheOnlineMacsAgain() {
        runTest {
            val mac = macWithWorkspaces(listOf("shellx"))
            val rig = makeRig(listOf(mac))
            assertTrue(waitFor { titles(rig, mac) == listOf("shellx") })

            rig.actions.refresh()

            assertEquals(2, mac.workspaceListCount)
        }
    }
}
