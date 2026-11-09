@file:OptIn(ExperimentalCoroutinesApi::class)

package com.shellx.app.ui.workspaces

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.WorkRig
import com.shellx.app.testing.eventually
import com.shellx.core.link.MachineLinkState
import com.shellx.core.workspaces.WorkspaceScreenModel
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import com.shellx.link.core.WorkspaceControlOutcome
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The workspace screen's controls as [WorkspaceScreenActions.make] wires them to the signed-in scope, against a fake Mac
 * (`WorkspaceViewTests.swift`): each reaches the hub call it stands for and does with the answer what
 * [WorkspaceFeedback] says.
 */
@RunWith(AndroidJUnit4::class)
class WorkspaceActionsTest {
    private var rig: WorkRig = WorkRig.make()
    private val model: WorkspaceScreenModel by lazy { rig.workspaceModel() }
    private val alerts = mutableListOf<WorkspaceAlert>()
    private var closings = 0
    private val tasks = mutableListOf<Deferred<WorkspaceFeedback>>()
    private var following: Job? = null

    private val actions: WorkspaceScreenActions by lazy {
        WorkspaceScreenActions.make(rig.scope, model, alert = { alerts += it }, closing = { closings++ }, done = { tasks += it })
    }

    @After
    fun tearDown() {
        following?.cancel()
        rig.close()
    }

    /** The feedback of the command the last action started. */
    private fun lastFeedback(): WorkspaceFeedback {
        assertTrue("the command ended", eventually { tasks.last().isCompleted })
        return tasks.last().getCompleted()
    }

    /** Follows the hub as the screen does while it is shown. */
    private fun follow() {
        following = rig.hub.scope.launch { model.run() }
        assertTrue(eventually { model.phase == WorkspaceScreenModel.Phase.SHOWING })
    }

    private fun terminalCloses(): List<String> = rig.mac.terminalCloses.map { "${it.workspaceId}/${it.terminalId}" }

    @Test
    fun selectingAChipShowsIt() {
        follow()
        assertEquals("the Mac's selection", "t-zsh", model.selectedTerminalId)
        actions.select("t-claude")
        assertEquals("t-claude", model.selectedTerminalId)
        assertTrue("swiping asks the Mac for nothing", tasks.isEmpty())
    }

    @Test
    fun renameReachesTheMacAndTheNameArrivesByPush() {
        follow()
        actions.rename("Docs")
        assertEquals(WorkspaceFeedback.None, lastFeedback())
        assertEquals(listOf("rename:ws-shellx:Docs"), rig.mac.workspaceCalls)
        assertTrue(eventually { model.workspace?.title == "Docs" })
        assertTrue(alerts.isEmpty())
    }

    @Test
    fun closeReachesTheMacAndTheScreenLeavesByPush() {
        follow()
        actions.close()
        assertEquals(WorkspaceFeedback.None, lastFeedback())
        assertEquals("the screen is told the user closed it", 1, closings)
        assertEquals(listOf("close:ws-shellx"), rig.mac.workspaceCalls)
        assertTrue("${model.phase}", eventually { model.phase == WorkspaceScreenModel.Phase.DISMISSED })
    }

    @Test
    fun aRefusedCloseIsAnAlertAndTheWorkspaceStays() {
        follow()
        rig.mac.setNextWorkspaceOutcome(WorkspaceControlOutcome.REFUSED)
        actions.close()
        assertEquals(WorkspaceFeedback.Alert(WorkspaceAlert.REFUSED_CLOSE), lastFeedback())
        assertEquals(listOf(WorkspaceAlert.REFUSED_CLOSE), alerts)
        assertEquals(WorkspaceScreenModel.Phase.SHOWING, model.phase)
    }

    @Test
    fun aWorkspaceTheMacDoesNotHaveRefreshesTheList() {
        follow()
        rig.mac.setNextWorkspaceOutcome(WorkspaceControlOutcome.NOT_FOUND)
        val before = rig.mac.workspaceListCount
        actions.rename("x")
        assertEquals(WorkspaceFeedback.Refresh, lastFeedback())
        assertTrue("the list was asked for again, with no word to the user", eventually { rig.mac.workspaceListCount == before + 1 })
        assertTrue(alerts.isEmpty())
    }

    @Test
    fun closeTabClosesTheShellShownAndTheNextChipShowsWithoutAWord() {
        follow()
        assertTrue(WorkspaceListActions.canCloseTab(model.ref.machineId, rig.hub))
        assertEquals("a shell: any tab closes, not only an agent's", "t-zsh", model.selectedTerminalId)
        actions.closeTab("t-zsh")
        assertEquals("the tab leaves by the Mac's push", WorkspaceFeedback.None, lastFeedback())
        assertEquals(listOf("ws-shellx/t-zsh"), terminalCloses())
        assertTrue(eventually { model.panes.map { it.id } == listOf("t-claude") })
        assertEquals("the chip left, the only one there", "t-claude", model.selectedTerminalId)
        assertEquals("closed from this phone: no 'closed on the Mac'", 0, model.shownPaneClosed)
        assertEquals(WorkspaceScreenModel.Phase.SHOWING, model.phase)
        assertTrue(alerts.isEmpty())
        assertEquals("closing a tab is not closing the workspace", 0, closings)
    }

    @Test
    fun closingTheLastTabLeavesWithoutSayingTheMacClosedIt() {
        follow()
        actions.select("t-claude")
        // A long press on the shell's chip, which is not the one shown: the agent stays on screen.
        actions.closeTab("t-zsh")
        lastFeedback()
        assertTrue(eventually { model.panes.map { it.id } == listOf("t-claude") })
        assertEquals("t-claude", model.selectedTerminalId)
        // The agent's tab, now the workspace's last: the Mac closes the workspace with it.
        actions.closeTab("t-claude")
        assertEquals(WorkspaceFeedback.None, lastFeedback())
        assertEquals(listOf("ws-shellx/t-zsh", "ws-shellx/t-claude"), terminalCloses())
        assertEquals("an agent's tab closes as a tab: the Mac checks for no live agent", emptyList<String>(), rig.mac.agentCloses)
        assertTrue("${model.phase}", eventually { model.phase == WorkspaceScreenModel.Phase.DISMISSED })
        assertTrue("the screen leaves without 'Workspace closed on the Mac'", model.lastTabClosedHere)
        assertEquals(0, model.shownPaneClosed)
        assertTrue(alerts.isEmpty())
    }

    @Test
    fun aRefusedCloseTabIsAnAlertAndTheTabStays() {
        follow()
        rig.mac.setNextTerminalCloseOutcome(WorkspaceControlOutcome.REFUSED)
        actions.closeTab("t-zsh")
        assertEquals(WorkspaceFeedback.Alert(WorkspaceAlert.REFUSED_CLOSE_TAB), lastFeedback())
        assertEquals(listOf(WorkspaceAlert.REFUSED_CLOSE_TAB), alerts)
        assertEquals(listOf("t-claude", "t-zsh"), model.panes.map { it.id })
        assertEquals("t-zsh", model.selectedTerminalId)
        // Closed later on the Mac itself: that one the screen does explain.
        rig.mac.upsertWorkspace(
            LinkWorkspace(
                "ws-shellx", "shellx-ios", 0, directory = "~/shellx/shellx-ios", branch = "feat/workspaces",
                terminals = listOf(LinkTerminal("t-claude", "claude", 0, selected = true, sessionId = "s1")),
            ),
        )
        assertTrue(eventually { model.selectedTerminalId == "t-claude" })
        assertEquals(1, model.shownPaneClosed)
    }

    @Test
    fun closeTabWhileTheSameTabsCloseWaitsSendsNothing() {
        follow()
        rig.mac.holdWorkspaceControl()
        // The menu's Close Tab… and a long press on the same chip, both confirmed.
        actions.closeTab("t-zsh")
        actions.closeTab("t-zsh")
        assertEquals("the second close waits for the first", 1, tasks.size)
        assertTrue(eventually { terminalCloses() == listOf("ws-shellx/t-zsh") })
        rig.mac.releaseWorkspaceControl()
        lastFeedback()
        assertEquals(listOf("ws-shellx/t-zsh"), terminalCloses())
    }

    @Test
    fun aMacWithoutTerminalCloseOffersNoCloseTab() {
        rig.close()
        rig = WorkRig.make(acceptsTerminalClose = false)
        assertFalse(WorkspaceListActions.canCloseTab(model.ref.machineId, rig.hub))
    }

    /** The Swift test stops the hub; here the hub's scope ends with a stop, so the Mac is made unreachable instead (the
     *  app's background time ran out): the command answers Offline. */
    @Test
    fun commandsToAMacThatIsAwayAreAnAlert() {
        rig.hub.backgroundTimeExpired()
        assertTrue(eventually { rig.hub.machines.first().state != MachineLinkState.Online })
        actions.rename("x")
        assertEquals(WorkspaceFeedback.Alert(WorkspaceAlert.OFFLINE), lastFeedback())
        assertEquals(listOf(WorkspaceAlert.OFFLINE), alerts)
    }
}
