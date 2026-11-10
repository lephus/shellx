@file:OptIn(ExperimentalCoroutinesApi::class)

package com.shellx.app.ui.workspaces

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.WorkRig
import com.shellx.app.testing.eventually
import com.shellx.core.link.MachineLinkState
import com.shellx.core.workspaces.WorkspaceCommandResult
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

    // Terminals (2C's additions to `WorkspaceViewTests.swift`)

    @Test
    fun aNewTerminalReachesTheMacAndItsChipShows() {
        follow()
        assertTrue(rig.hub.supportsTerminalCreate(model.ref.machineId))
        actions.createTerminal()
        assertEquals(WorkspaceFeedback.None, lastFeedback())
        assertEquals(listOf("ws-shellx"), rig.mac.terminalCreates)
        assertTrue("${model.selectedTerminalId}", eventually { model.selectedTerminalId?.startsWith("ws-shellx-new-") == true })
        assertTrue(alerts.isEmpty())
    }

    @Test
    fun aRefusedNewTerminalIsAnAlert() {
        follow()
        rig.mac.setNextTerminalCreateOutcome(WorkspaceControlOutcome.REFUSED)
        actions.createTerminal()
        assertEquals(WorkspaceFeedback.Alert(WorkspaceAlert.REFUSED_CONTROL), lastFeedback())
        assertEquals(listOf(WorkspaceAlert.REFUSED_CONTROL), alerts)
        assertEquals("t-zsh", model.selectedTerminalId)
        assertFalse("a refused ＋ is not dimmed any more", model.creatingTerminal)
    }

    /** ＋ to a Mac that cannot be reached is an alert, and ＋ is not left dimmed (review D2 m1). */
    @Test
    fun aNewTerminalToAnUnreachableMacLeavesPlusEnabled() {
        follow()
        rig.hub.backgroundTimeExpired()
        assertTrue(eventually { rig.hub.machines.first().state != MachineLinkState.Online })
        actions.createTerminal()
        assertEquals(WorkspaceFeedback.Alert(WorkspaceAlert.OFFLINE), lastFeedback())
        assertEquals(listOf(WorkspaceAlert.OFFLINE), alerts)
        assertFalse(model.creatingTerminal)
        assertTrue(rig.mac.terminalCreates.isEmpty())
    }

    @Test
    fun viewAsTerminalSwitchesTheAgentChipsPage() {
        follow()
        actions.select("t-claude")
        assertEquals("an agent chip shows its chat", null, model.terminalShown)
        actions.showAsTerminal("t-claude", true)
        assertEquals("t-claude", model.terminalShown)
        actions.showAsTerminal("t-claude", false)
        assertEquals(null, model.terminalShown)
        assertTrue("switching the page asks the Mac for nothing", tasks.isEmpty())
    }

    @Test
    fun aNewTerminalsAnswers() {
        val m = "m1"
        assertEquals(WorkspaceFeedback.None, WorkspaceFeedback.of(WorkspaceCommandResult.Ok(null), WorkspaceCommand.CREATE_TERMINAL, m))
        assertEquals(WorkspaceFeedback.None, WorkspaceFeedback.of(WorkspaceCommandResult.Ok("ws"), WorkspaceCommand.CREATE_TERMINAL, m))
        assertEquals(WorkspaceFeedback.Refresh, WorkspaceFeedback.of(WorkspaceCommandResult.NotFound, WorkspaceCommand.CREATE_TERMINAL, m))
        assertEquals(
            WorkspaceFeedback.Alert(WorkspaceAlert.REFUSED_CONTROL),
            WorkspaceFeedback.of(WorkspaceCommandResult.Refused, WorkspaceCommand.CREATE_TERMINAL, m),
        )
        assertEquals(WorkspaceFeedback.Alert(WorkspaceAlert.FAILED), WorkspaceFeedback.of(WorkspaceCommandResult.Failed, WorkspaceCommand.CREATE_TERMINAL, m))
        assertEquals(WorkspaceFeedback.Alert(WorkspaceAlert.OFFLINE), WorkspaceFeedback.of(WorkspaceCommandResult.Offline, WorkspaceCommand.CREATE_TERMINAL, m))
        assertEquals(WorkspaceFeedback.Alert(WorkspaceAlert.UNKNOWN), WorkspaceFeedback.of(WorkspaceCommandResult.Unknown, WorkspaceCommand.CREATE_TERMINAL, m))
    }

    /**
     * Runs [taps] in one main-thread turn that started in the hub's scope, as the Swift tests' Task does: a command the
     * actions start meanwhile waits for the turn to end, so the fake Mac (which answers at once) answers after [taps].
     */
    private fun inOneTurn(taps: () -> Unit) {
        val turn = rig.hub.scope.launch { taps() }
        assertTrue(eventually { turn.isCompleted })
    }

    /** ＋ again while a new terminal is on its way does nothing, and a chip the user picks before the Mac answers stays
     *  shown when the new tab arrives (the iPhone's final review, app M6). */
    @Test
    fun aPickWhileANewTerminalIsOnItsWayWins() {
        follow()
        inOneTurn {
            actions.createTerminal()
            actions.createTerminal()
            actions.select("t-claude")
        }
        assertTrue(eventually { tasks.all { it.isCompleted } })
        assertEquals("one create while one is on its way", listOf("ws-shellx"), rig.mac.terminalCreates)
        assertTrue(eventually { model.panes.any { it.id.startsWith("ws-shellx-new-") } })
        eventually(timeoutMs = 100) { false }
        assertEquals("the user's pick wins over the new tab", "t-claude", model.selectedTerminalId)
    }

    /** ＋ is dimmed from the tap until the Mac answers (the iPhone's final review, app M6). */
    @Test
    fun plusIsDimmedWhileANewTerminalIsOnItsWay() {
        follow()
        var dimmed = false
        inOneTurn {
            actions.createTerminal()
            dimmed = model.creatingTerminal
        }
        assertTrue(dimmed)
        lastFeedback()
        assertFalse(model.creatingTerminal)
        actions.createTerminal()
        lastFeedback()
        assertEquals("once answered, ＋ works again", listOf("ws-shellx", "ws-shellx"), rig.mac.terminalCreates)
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
