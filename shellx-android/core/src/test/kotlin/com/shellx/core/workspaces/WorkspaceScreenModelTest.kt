package com.shellx.core.workspaces

import com.shellx.core.demo.FakeMac
import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.MachineModel
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.testing.HubRig
import com.shellx.core.testing.ManualSleeper
import com.shellx.core.testing.agentSession
import com.shellx.core.testing.eventually
import com.shellx.core.testing.hubRig
import com.shellx.core.testing.linkWorkspace
import com.shellx.core.testing.pendingItem
import com.shellx.link.account.RelayApiException
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest

/**
 * The workspace screen's model: which chip shows first, what happens when the workspace or the chip being viewed
 * leaves the Mac's list, the wait for a workspace the Mac has not listed yet, and the terminal shown
 * (WorkspaceScreenModelTests.swift).
 */
class WorkspaceScreenModelTest {
    private fun ref(mac: FakeMac, workspace: String = "shellx") = WorkspaceRef(mac.machine.machineId, "ws-$workspace")

    /** Whether the hub's list for [mac] has the workspace `ws-<name>`. */
    private fun listed(name: String, hub: MachineHub, mac: FakeMac): Boolean =
        hub.workspaceRows(mac.machine.machineId).any { it.id.workspaceId == "ws-$name" }

    private fun terminals(vararg ids: String, agent: Map<String, String> = emptyMap(), selected: String? = null): List<LinkTerminal> =
        ids.mapIndexed { index, id -> LinkTerminal(id, id, index, id == selected, agent[id]) }

    private fun pending(workspace: String = "shellx", machine: String = "m1") =
        MachinePendingItem(machine, "Mac", pendingItem("r1", workspace = workspace), true)

    private class Screen(val model: WorkspaceScreenModel, val rig: HubRig, val run: Job) {
        val hub: MachineHub get() = rig.hub
    }

    /** A model over a hub that is online with [mac]'s workspaces in; PATIENCE is the model's own wait on [sleeper]. */
    private suspend fun TestScope.makeModel(
        mac: FakeMac,
        workspace: String = "shellx",
        sleeper: ManualSleeper = ManualSleeper(),
        sessions: Int = 0,
    ): Screen {
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions))
        assertTrue(eventually { rig.hub.machines.firstOrNull()?.workspacesSupported == true })
        val model = WorkspaceScreenModel(ref(mac, workspace), rig.hub, sleeper.sleep)
        val run = backgroundScope.launch { model.run() }
        return Screen(model, rig, run)
    }

    /** A hub online with [mac], its workspaces listed, and a model that runs. */
    private suspend fun TestScope.runningModel(mac: FakeMac, sessions: Int = 0): Pair<WorkspaceScreenModel, HubRig> {
        val rig = hubRig(listOf(mac), start = true)
        rig.online(sessions)
        eventually { rig.hub.machines.firstOrNull()?.workspacesSupported == true }
        val model = WorkspaceScreenModel(ref(mac), rig.hub, ManualSleeper().sleep)
        backgroundScope.launch { model.run() }
        return model to rig
    }

    // The chip shown first

    @Test fun defaultTerminalPrefersPending() {
        val workspace = linkWorkspace(terminals = terminals("shell", "claude", "dev", agent = mapOf("claude" to "s1"), selected = "shell"))

        assertEquals(
            "claude", WorkspaceScreenModel.defaultTerminal(workspace, listOf(pending())),
            "a request waits on the agent: its chip, whatever the Mac has selected",
        )
        assertEquals("shell", WorkspaceScreenModel.defaultTerminal(workspace, emptyList()), "nothing waits: the chip the Mac has selected")
        assertEquals(
            "shell", WorkspaceScreenModel.defaultTerminal(workspace, listOf(pending(workspace = "other"))),
            "a request of another workspace does not count",
        )
    }

    @Test fun defaultTerminalFallsBackToTheFirstChip() {
        // Chips go by `order`, not by the order they came in.
        val unsorted = linkWorkspace(terminals = listOf(LinkTerminal("b", "b", 1, false), LinkTerminal("a", "a", 0, false)))
        assertEquals("a", WorkspaceScreenModel.defaultTerminal(unsorted, emptyList()))
        assertNull(WorkspaceScreenModel.defaultTerminal(linkWorkspace(terminals = emptyList()), emptyList()))

        // A request waits but no chip runs an agent: the Mac's selection decides.
        val shells = linkWorkspace(terminals = terminals("one", "two", selected = "two"))
        assertEquals("two", WorkspaceScreenModel.defaultTerminal(shells, listOf(pending())))
    }

    @Test fun defaultTerminalSkipsAnAgentTheHubNoLongerLists() {
        val workspace = linkWorkspace(
            terminals = terminals("gone", "live", "shell", agent = mapOf("gone" to "s-gone", "live" to "s-live"), selected = "shell"),
        )

        assertEquals("live", WorkspaceScreenModel.defaultTerminal(workspace, listOf(pending()), listOf(agentSession("s-live"))))
        assertEquals(
            "shell", WorkspaceScreenModel.defaultTerminal(workspace, listOf(pending()), emptyList()),
            "no chip is an agent any more",
        )
    }

    @Test fun anAgentThatNeedsInputComesFirstThenTheAskingAgentThenTheMacsSelection() {
        val workspace = linkWorkspace(
            terminals = terminals("shell", "c1", "c2", "x1", agent = mapOf("c1" to "s-c1", "c2" to "s-c2", "x1" to "s-x1"), selected = "shell"),
        )
        fun session(id: String, state: AgentState, agent: String = "claude"): AgentSession =
            agentSession(id, state = state).copy(agent = agent)

        assertEquals(
            "c2",
            WorkspaceScreenModel.defaultTerminal(
                workspace, listOf(pending()),
                listOf(session("s-c1", AgentState.WORKING), session("s-c2", AgentState.NEEDS_INPUT), session("s-x1", AgentState.WORKING)),
            ),
            "the one agent that needs input",
        )
        assertEquals(
            "c2",
            WorkspaceScreenModel.defaultTerminal(
                workspace, emptyList(), listOf(session("s-c1", AgentState.WORKING), session("s-c2", AgentState.NEEDS_INPUT)),
            ),
            "it waits for the user even before its request is listed",
        )
        assertEquals(
            "c2",
            WorkspaceScreenModel.defaultTerminal(
                workspace, listOf(pending()),
                listOf(
                    session("s-c1", AgentState.WORKING), session("s-c2", AgentState.NEEDS_INPUT),
                    session("s-x1", AgentState.NEEDS_INPUT, agent = "codex"),
                ),
            ),
            "several need input: the one whose agent asks (the request is Claude's)",
        )
        assertEquals(
            "c1",
            WorkspaceScreenModel.defaultTerminal(
                workspace, listOf(pending()), listOf(session("s-c1", AgentState.NEEDS_INPUT), session("s-c2", AgentState.NEEDS_INPUT)),
            ),
            "the same agent asks in both: the first, the Mac selecting neither",
        )
        val macSelectsC2 = linkWorkspace(terminals = terminals("c1", "c2", agent = mapOf("c1" to "s-c1", "c2" to "s-c2"), selected = "c2"))
        assertEquals(
            "c2",
            WorkspaceScreenModel.defaultTerminal(
                macSelectsC2, listOf(pending()), listOf(session("s-c1", AgentState.NEEDS_INPUT), session("s-c2", AgentState.NEEDS_INPUT)),
            ),
            "then the one the Mac has selected",
        )
        assertEquals(
            "shell",
            WorkspaceScreenModel.defaultTerminal(
                workspace, emptyList(), listOf(session("s-c1", AgentState.WORKING), session("s-c2", AgentState.IDLE)),
            ),
            "nothing waits: the Mac's selection",
        )
    }

    @Test fun pendingChoosesTheAgentThatIsSelectedWhenThereAreSeveral() {
        val workspace = linkWorkspace(terminals = terminals("a1", "a2", agent = mapOf("a1" to "s1", "a2" to "s2"), selected = "a2"))
        assertEquals("a2", WorkspaceScreenModel.defaultTerminal(workspace, listOf(pending())))
    }

    // Panes

    @Test fun aChipWhoseSessionTheHubDoesNotListIsAShellChip() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("t1", "t2", "t3", agent = mapOf("t1" to "s-live", "t2" to "s-gone")))))
        mac.upsertSession(agentSession("s-live"))
        val model = makeModel(mac, sessions = 1).model

        assertEquals(listOf("t1", "t2", "t3"), model.panes.map { it.id })
        assertEquals(listOf(true, false, false), model.panes.map { it.isAgent })
        assertEquals("s-live", model.panes.firstOrNull()?.session?.session?.sessionId)
        assertEquals("MacBook Pro", model.panes.firstOrNull()?.session?.machineName)
    } }

    @Test fun panesGoByOrder() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(
            listOf(
                linkWorkspace(
                    terminals = listOf(
                        LinkTerminal("late", "late", 2, false), LinkTerminal("first", "first", 0, false), LinkTerminal("mid", "mid", 1, true),
                    ),
                ),
            ),
        )
        val model = makeModel(mac).model

        assertEquals(listOf("first", "mid", "late"), model.panes.map { it.id })
        assertEquals("mid", model.selectedTerminalId, "the Mac's selection shows first")
    } }

    @Test fun theModelStartsOnTheDefaultChipBeforeItRuns() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("t1", "t2", agent = mapOf("t2" to "s1"), selected = "t1"))))
        mac.upsertSession(agentSession("s1", state = AgentState.NEEDS_INPUT))
        mac.addPending(pendingItem("r1"))
        val rig = hubRig(listOf(mac), start = true)
        rig.online(1)
        eventually { rig.hub.pendingItems.size == 1 && rig.hub.machines.firstOrNull()?.workspacesSupported == true }

        val model = WorkspaceScreenModel(ref(mac), rig.hub, ManualSleeper().sleep)

        assertEquals(WorkspaceScreenModel.Phase.SHOWING, model.phase, "the first frame already has a workspace")
        assertEquals("t2", model.selectedTerminalId, "the agent that waits for the user")
    } }

    /** Spec section 6.2: the screen opens on the pane waiting for the user. With two Claude agents, the one whose
     *  session needs input, not the one the Mac has selected. */
    @Test fun theAgentThatNeedsInputIsTheDefaultOverTheMacsSelection() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("a1", "a2", agent = mapOf("a1" to "s1", "a2" to "s2"), selected = "a1"))))
        mac.upsertSession(agentSession("s1", state = AgentState.WORKING))
        mac.upsertSession(agentSession("s2", state = AgentState.NEEDS_INPUT))
        mac.addPending(pendingItem("r1"))
        val rig = hubRig(listOf(mac), start = true)
        rig.online(2)
        eventually { rig.hub.pendingItems.size == 1 && rig.hub.machines.firstOrNull()?.workspacesSupported == true }

        val model = WorkspaceScreenModel(ref(mac), rig.hub, ManualSleeper().sleep)

        assertEquals("a2", model.selectedTerminalId, "the agent that asks, not the Mac's selection")
    } }

    /** The list can come before the sessions and the request it names: until the user picks a chip, the chip shown
     *  follows what the screen learns. */
    @Test fun theDefaultChipIsChosenAgainWhenTheSessionsArriveAfterTheList() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("zsh", "claude", agent = mapOf("claude" to "s1"), selected = "zsh"))))
        val screen = makeModel(mac)
        val model = screen.model
        assertEquals("zsh", model.selectedTerminalId, "no session listed yet: the Mac's selection")

        mac.upsertSession(agentSession("s1", state = AgentState.NEEDS_INPUT))
        mac.addPending(pendingItem("r1"))
        assertTrue(eventually { model.selectedTerminalId == "claude" }, "${model.selectedTerminalId}")

        // Once the user picked a chip, what arrives later does not move it.
        model.select("zsh")
        mac.upsertSession(agentSession("s1", state = AgentState.WORKING))
        mac.upsertSession(agentSession("s1", state = AgentState.NEEDS_INPUT))
        mac.addPending(pendingItem("r2"))
        assertTrue(eventually { screen.hub.pendingItems.size == 2 })
        assertEquals("zsh", model.selectedTerminalId)
    } }

    // Swiping and a chip that goes

    @Test fun selectingAChipSticksWhileTheMacChangesItsOwnSelection() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("t1", "t2", "t3", selected = "t1"))))
        val model = makeModel(mac).model
        assertEquals("t1", model.selectedTerminalId)

        model.select("t2")
        model.select("nope")
        assertEquals("t2", model.selectedTerminalId, "an id the workspace does not have is ignored")

        mac.upsertWorkspace(linkWorkspace(terminals = terminals("t1", "t2", "t3", selected = "t3")))
        // A later change that the model has surely seen: the extra chip.
        mac.upsertWorkspace(linkWorkspace(terminals = terminals("t1", "t2", "t3", "t4", selected = "t3")))
        assertTrue(eventually { model.panes.size == 4 })
        assertEquals("t2", model.selectedTerminalId, "the phone's chip does not follow the Mac's")
    } }

    @Test fun theChipBeingViewedGoingAwayMovesOnToTheNextOne() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("t1", "t2", "t3", "t4"))))
        val model = makeModel(mac).model

        model.select("t2")
        mac.upsertWorkspace(linkWorkspace(terminals = terminals("t1", "t3", "t4")))
        assertTrue(eventually { model.selectedTerminalId == "t3" }, "the chip after it: ${model.selectedTerminalId}")

        model.select("t4")
        mac.upsertWorkspace(linkWorkspace(terminals = terminals("t1", "t3")))
        assertTrue(eventually { model.selectedTerminalId == "t3" }, "the last chip went: the one before it, ${model.selectedTerminalId}")
        assertEquals(WorkspaceScreenModel.Phase.SHOWING, model.phase)
        assertEquals(2, model.shownPaneClosed, "each time, the screen says the pane was closed on the Mac")
    } }

    @Test fun aChipThatIsNotBeingViewedGoingAwayChangesNothing() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("t1", "t2", "t3"))))
        val model = makeModel(mac).model
        model.select("t1")

        mac.upsertWorkspace(linkWorkspace(terminals = terminals("t1", "t3")))
        val gone = eventually { model.panes.map { it.id } == listOf("t1", "t3") }

        assertTrue(gone)
        assertEquals("t1", model.selectedTerminalId)
        assertEquals(0, model.shownPaneClosed, "the pane shown is still there: nothing to say")
    } }

    @Test fun theLastChipGoingAwayLeavesNoSelection() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("t1"))))
        val model = makeModel(mac).model

        mac.upsertWorkspace(linkWorkspace(terminals = emptyList()))
        val empty = eventually { model.panes.isEmpty() }

        assertTrue(empty)
        assertNull(model.selectedTerminalId)
        assertEquals(WorkspaceScreenModel.Phase.SHOWING, model.phase, "a workspace with no terminal is still a workspace")

        mac.upsertWorkspace(linkWorkspace(terminals = terminals("t9")))
        assertTrue(eventually { model.selectedTerminalId == "t9" }, "a chip came: it shows")
    } }

    @Test fun aTabClosedFromThisIPhoneGoesWithoutAWord() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("t1", "t2", "t3"))))
        val model = makeModel(mac).model
        model.select("t2")

        model.closesHere("t2")
        mac.upsertWorkspace(linkWorkspace(terminals = terminals("t1", "t3")))
        assertTrue(eventually { model.selectedTerminalId == "t3" }, "the next chip shows: ${model.selectedTerminalId}")
        assertEquals(0, model.shownPaneClosed, "the user closed it here: nothing to explain")

        // A close the Mac did not carry out: when the tab goes later, the Mac closed it.
        model.closesHere("t3")
        model.keeps("t3")
        mac.upsertWorkspace(linkWorkspace(terminals = terminals("t1")))
        assertTrue(eventually { model.selectedTerminalId == "t1" })
        assertEquals(1, model.shownPaneClosed, "closed on the Mac: the screen says so")
        assertEquals(WorkspaceScreenModel.Phase.SHOWING, model.phase)
        assertFalse(model.lastTabClosedHere)
    } }

    @Test fun theWorkspaceGoingWithTheLastTabClosedHereIsNotClosedOnTheMac() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("t1", "t2")), linkWorkspace("web", order = 1, terminals = terminals("w1"))))
        val model = makeModel(mac).model

        model.closesHere("t1")
        mac.upsertWorkspace(linkWorkspace(terminals = terminals("t2")))
        assertTrue(eventually { model.panes.map { it.id } == listOf("t2") })
        model.closesHere("t2")
        // The Mac may list the workspace with no tab for a moment before it goes.
        mac.upsertWorkspace(linkWorkspace(terminals = emptyList()))
        assertTrue(eventually { model.panes.isEmpty() })
        mac.removeWorkspace("ws-shellx")
        val dismissed = eventually { model.phase == WorkspaceScreenModel.Phase.DISMISSED }

        assertTrue(dismissed, "${model.phase}")
        assertTrue(model.lastTabClosedHere, "the screen leaves without 'Workspace closed on the Mac'")
        assertEquals(0, model.shownPaneClosed)
    } }

    @Test fun theWorkspaceGoingWithATabNotClosedHereIsClosedOnTheMac() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("t1", "t2")), linkWorkspace("web", order = 1, terminals = terminals("w1"))))
        val model = makeModel(mac).model

        // Only one of its two tabs was closed here when the Mac closed the whole workspace.
        model.closesHere("t1")
        mac.removeWorkspace("ws-shellx")
        val dismissed = eventually { model.phase == WorkspaceScreenModel.Phase.DISMISSED }

        assertTrue(dismissed, "${model.phase}")
        assertFalse(model.lastTabClosedHere)
    } }

    // The workspace leaves, or has not come

    @Test fun closedWorkspaceDismisses() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx"), linkWorkspace("web", order = 1)))
        val model = makeModel(mac).model
        assertEquals(WorkspaceScreenModel.Phase.SHOWING, model.phase)

        mac.removeWorkspace("ws-web")
        // The other workspace leaving is not this one's business.
        assertTrue(eventually { model.workspace != null })
        assertEquals(WorkspaceScreenModel.Phase.SHOWING, model.phase)

        mac.removeWorkspace("ws-shellx")
        assertTrue(eventually { model.phase == WorkspaceScreenModel.Phase.DISMISSED }, "${model.phase}")
        assertFalse(model.lastTabClosedHere, "closed on the Mac: the list says so")
    } }

    @Test fun dismissedStaysDismissedWhenTheWorkspaceListsAgain() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx"), linkWorkspace("web", order = 1)))
        val screen = makeModel(mac)
        val model = screen.model

        mac.removeWorkspace("ws-shellx")
        eventually { model.phase == WorkspaceScreenModel.Phase.DISMISSED }
        mac.upsertWorkspace(linkWorkspace("shellx"))
        mac.upsertWorkspace(linkWorkspace("docs", order = 5))
        assertTrue(eventually { listed("docs", screen.hub, mac) })

        assertEquals(WorkspaceScreenModel.Phase.DISMISSED, model.phase, "the screen is already on its way out")
    } }

    @Test fun unseenWorkspaceWaits() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        val sleeper = ManualSleeper()
        val screen = makeModel(mac, workspace = "new", sleeper = sleeper)
        val model = screen.model

        // `workspace.create.result` came before the push that lists the workspace: wait, do not leave.
        assertEquals(WorkspaceScreenModel.Phase.WAITING, model.phase)
        assertNull(model.workspace)
        assertTrue(eventually { sleeper.waiting == listOf(5.seconds) }, "${sleeper.requested}")
        assertEquals(1, mac.workspaceListCount)

        // Other changes, even a removal, say nothing about a workspace never seen.
        mac.upsertWorkspace(linkWorkspace("web", order = 1))
        mac.removeWorkspace("ws-web")
        assertTrue(eventually { !listed("web", screen.hub, mac) })
        assertEquals(WorkspaceScreenModel.Phase.WAITING, model.phase)

        // The push arrives within the wait: the screen shows, and the wait ends without asking again.
        mac.upsertWorkspace(linkWorkspace("new", order = 2, terminals = terminals("t1")))
        assertTrue(eventually { model.phase == WorkspaceScreenModel.Phase.SHOWING })
        assertEquals("t1", model.selectedTerminalId)
        sleeper.release()
        eventually(200.milliseconds) { false }
        assertEquals(1, mac.workspaceListCount, "it arrived: no refresh was needed")
        assertEquals(WorkspaceScreenModel.Phase.SHOWING, model.phase)
    } }

    @Test fun unseenWorkspaceAsksTheMacOnceThenGivesUp() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        val sleeper = ManualSleeper()
        val model = makeModel(mac, workspace = "ghost", sleeper = sleeper).model
        assertEquals(WorkspaceScreenModel.Phase.WAITING, model.phase)
        assertTrue(eventually { sleeper.waiting == listOf(5.seconds) })

        sleeper.release()

        assertTrue(eventually { model.phase == WorkspaceScreenModel.Phase.NOT_FOUND }, "${model.phase}")
        assertEquals(2, mac.workspaceListCount, "the list was asked for once more, not again and again")
        assertEquals(listOf(5.seconds), sleeper.requested)

        // A late push still shows the workspace.
        mac.upsertWorkspace(linkWorkspace("ghost", order = 3, terminals = terminals("t1")))
        assertTrue(eventually { model.phase == WorkspaceScreenModel.Phase.SHOWING })
    } }

    @Test fun theRefreshCanFindTheWorkspaceItself() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        val sleeper = ManualSleeper()
        val model = makeModel(mac, workspace = "missed", sleeper = sleeper).model
        assertTrue(eventually { sleeper.waiting == listOf(5.seconds) })

        // The push was lost: the Mac's list moved on without telling the phone.
        mac.skipNextWorkspaceRevision()
        mac.upsertWorkspace(linkWorkspace("missed", order = 1, terminals = terminals("t1")))
        sleeper.release()

        assertTrue(eventually { model.phase == WorkspaceScreenModel.Phase.SHOWING }, "${model.phase}")
    } }

    @Test fun workspaceOfAnUnknownMacNeverDismissesFromNothing() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        val rig = hubRig(listOf(mac), start = true)
        rig.online(0)
        val sleeper = ManualSleeper()
        val model = WorkspaceScreenModel(WorkspaceRef("mac-nobody", "ws-shellx"), rig.hub, sleeper.sleep)
        backgroundScope.launch { model.run() }

        assertEquals(WorkspaceScreenModel.Phase.WAITING, model.phase)
        assertTrue(model.panes.isEmpty())
    } }

    // The Mac goes away

    @Test fun theLastKnownChipsStayWhileTheMacIsOffline() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("t1", "t2", agent = mapOf("t1" to "s1")))))
        mac.upsertSession(agentSession("s1"))
        val (model, rig) = runningModel(mac, sessions = 1)
        model.select("t2")

        mac.dropLiveSessions()
        assertTrue(eventually { rig.hub.machines.firstOrNull()?.state != MachineLinkState.Online })

        assertEquals(WorkspaceScreenModel.Phase.SHOWING, model.phase)
        assertEquals(listOf("t1", "t2"), model.panes.map { it.id })
        assertEquals(listOf(true, false), model.panes.map { it.isAgent }, "the agent pane stays; its screen says the Mac is away")
        assertEquals("t2", model.selectedTerminalId)
    } }

    /** The relay no longer grants the Mac (MachineHub.revoke): the hub empties the Mac's list, but nothing was closed
     *  on the Mac. The screen keeps its last chips; it does not leave saying the workspace was closed. */
    @Test fun theChipsStayWhenTheRelayNoLongerGrantsTheMac() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("t1", "t2"))))
        val screen = makeModel(mac)
        val model = screen.model
        assertEquals(WorkspaceScreenModel.Phase.SHOWING, model.phase)

        // The relay grants nothing (the Swift rig's relay never had a grant): the Mac is revoked.
        screen.rig.relay.setGrants(emptyList())
        screen.hub.refreshGrants()
        assertTrue(eventually { screen.hub.machines.firstOrNull()?.state == MachineLinkState.Revoked })
        assertTrue(screen.hub.workspaceRows(mac.machine.machineId).isEmpty(), "the hub forgot the list")
        // Whatever the model would do with that, it has had the time to.
        eventually(200.milliseconds) { false }

        assertEquals(WorkspaceScreenModel.Phase.SHOWING, model.phase, "nothing was closed on the Mac")
        assertEquals(listOf("t1", "t2"), model.panes.map { it.id }, "the last chips stay")
    } }

    /** The Mac removed this phone (the connection stops for good, Revoked): the same, through the connection's own
     *  stop. */
    @Test fun theChipsStayWhenTheMacRemovesThisIPhone() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("t1", "t2"))))
        val (model, rig) = runningModel(mac)
        assertEquals(WorkspaceScreenModel.Phase.SHOWING, model.phase)

        mac.failNextConnects(RelayApiException.Http(403, "not_granted"), 5)
        mac.dropLiveSessions()
        assertTrue(eventually { rig.backoff.waiting.size == 1 })
        rig.backoff.release()
        assertTrue(eventually { rig.hub.machines.firstOrNull()?.state == MachineLinkState.Revoked })
        assertTrue(eventually { rig.hub.workspaceRows(mac.machine.machineId).isEmpty() })
        eventually(200.milliseconds) { false }

        assertEquals(WorkspaceScreenModel.Phase.SHOWING, model.phase, "nothing was closed on the Mac")
        assertEquals(listOf("t1", "t2"), model.panes.map { it.id }, "the last chips stay")
    } }

    /** Back online, the Mac's list no longer fits a frame (`too_large`): the hub has no list to give, but the Mac closed
     *  nothing. The chips stay. */
    @Test fun theChipsStayWhenTheListCannotBeReadOnReconnect() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("t1", "t2"))))
        val (model, rig) = runningModel(mac)

        mac.dropLiveSessions()
        assertTrue(eventually { rig.hub.machines.firstOrNull()?.state != MachineLinkState.Online && rig.backoff.waiting.size == 1 })
        mac.upsertWorkspace(LinkWorkspace(workspaceId = "ws-huge", title = "w".repeat(70_000), order = 1, terminals = emptyList()))
        rig.backoff.release()
        assertTrue(
            eventually {
                rig.hub.machines.firstOrNull()?.state == MachineLinkState.Online &&
                    rig.hub.machines.firstOrNull()?.workspacesSupported == false
            },
        )
        eventually(200.milliseconds) { false }

        assertEquals(WorkspaceScreenModel.Phase.SHOWING, model.phase, "nothing was closed on the Mac")
        assertEquals(listOf("t1", "t2"), model.panes.map { it.id }, "the last chips stay")
    } }

    @Test fun removingTheMacLeavesWithoutSayingTheWorkspaceClosed() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("t1"))))
        val screen = makeModel(mac)

        screen.hub.unpair(mac.machine.machineId)

        assertTrue(eventually { screen.model.phase == WorkspaceScreenModel.Phase.MACHINE_REMOVED }, "${screen.model.phase}")
    } }

    /** Closed on the Mac while the phone was away: once the Mac is back with its list, the screen leaves. */
    @Test fun aWorkspaceClosedWhileTheMacWasAwayLeavesWhenItIsBack() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx", terminals = terminals("t1")), linkWorkspace("web", order = 1)))
        val (model, rig) = runningModel(mac)

        mac.dropLiveSessions()
        assertTrue(eventually { rig.hub.machines.firstOrNull()?.state != MachineLinkState.Online && rig.backoff.waiting.size == 1 })
        mac.removeWorkspace("ws-shellx")
        assertEquals(WorkspaceScreenModel.Phase.SHOWING, model.phase, "the phone does not know yet")

        rig.backoff.release()
        assertTrue(eventually { model.phase == WorkspaceScreenModel.Phase.DISMISSED }, "${model.phase}")
    } }

    @Test fun onlyAnOnlineMacThatListsItsWorkspacesSaysOneWasClosed() { runTest {
        var model = MachineModel(FakeMac("MacBook Pro", backgroundScope).machine)
        assertEquals(WorkspaceScreenModel.Absence.MACHINE_REMOVED, WorkspaceScreenModel.absence(null))
        assertEquals(WorkspaceScreenModel.Absence.UNKNOWN, WorkspaceScreenModel.absence(model), "connecting, nothing listed yet")
        model = model.copy(state = MachineLinkState.Online)
        assertEquals(WorkspaceScreenModel.Absence.UNKNOWN, WorkspaceScreenModel.absence(model), "online, but its list could not be read")
        model = model.copy(workspacesSupported = true)
        assertEquals(WorkspaceScreenModel.Absence.CLOSED, WorkspaceScreenModel.absence(model))
        for (state in listOf(MachineLinkState.Reconnecting, MachineLinkState.Revoked, MachineLinkState.HostKeyChanged, MachineLinkState.NeedsUpdate)) {
            model = model.copy(state = state)
            assertEquals(WorkspaceScreenModel.Absence.UNKNOWN, WorkspaceScreenModel.absence(model), "$state")
        }
    } }

    // Seen

    @Test fun runningMarksTheWorkspaceSeen() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("t1", agent = mapOf("t1" to "s1")))))
        mac.upsertSession(agentSession("s1", state = AgentState.WORKING))
        val rig = hubRig(listOf(mac), start = true)
        rig.online(1)
        eventually { rig.hub.machines.firstOrNull()?.workspacesSupported == true }
        // The turn ends while the user is on the list: the workspace is "done".
        mac.upsertSession(agentSession("s1", state = AgentState.IDLE))
        val id = mac.machine.machineId
        assertTrue(eventually { rig.hub.workspaceRows(id).firstOrNull()?.state == WorkspaceState.DONE })

        val model = WorkspaceScreenModel(ref(mac), rig.hub, ManualSleeper().sleep)
        backgroundScope.launch { model.run() }

        assertTrue(
            eventually { rig.hub.workspaceRows(id).firstOrNull()?.state == WorkspaceState.IDLE },
            "opening the screen means the user looked",
        )
    } }

    @Test fun runStopsWhenCancelled() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        val sleeper = ManualSleeper()
        val run = makeModel(mac, workspace = "ghost", sleeper = sleeper).run
        assertTrue(eventually { sleeper.waiting.size == 1 })

        run.cancelAndJoin()

        assertEquals(1, sleeper.cancelled, "the wait for the workspace ended with the screen")
    } }

    // The terminal shown (plan 2C, plan 3G Task 11)

    @Test fun theTerminalShownIsTheShellOrAnAgentShownAsTerminal() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("claude", "zsh", agent = mapOf("claude" to "s1"), selected = "zsh"))))
        mac.upsertSession(agentSession("s1"))
        val model = makeModel(mac, sessions = 1).model
        assertEquals("zsh", model.terminalShown)
        model.select("claude")
        assertNull(model.terminalShown, "an agent's chip shows its chat")
        model.showAsTerminal("claude", true)
        assertEquals(setOf("claude"), model.shownAsTerminal)
        assertEquals("claude", model.terminalShown)
        model.showAsTerminal("claude", false)
        assertNull(model.terminalShown)
        model.showAsTerminal("nope", true)
        assertEquals(emptySet(), model.shownAsTerminal)
    } }

    @Test fun anExpectedTerminalShowsOnceTheListHasIt() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("zsh", selected = "zsh"))))
        val model = makeModel(mac).model
        model.expect("t-new")
        assertEquals("zsh", model.selectedTerminalId)
        mac.upsertWorkspace(linkWorkspace(terminals = terminals("zsh", "t-new", selected = "zsh")))
        assertTrue(eventually { model.selectedTerminalId == "t-new" })
        assertEquals(0, model.shownPaneClosed)
    } }

    @Test fun anExpectedTerminalAlreadyListedShowsAtOnce() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("zsh", "t-new", selected = "zsh"))))
        val model = makeModel(mac).model
        assertEquals("zsh", model.selectedTerminalId)
        model.expect("t-new")
        assertEquals("t-new", model.selectedTerminalId)
    } }

    @Test fun pickingAChipDropsTheExpectedOne() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("zsh", "other", selected = "zsh"))))
        val model = makeModel(mac).model
        model.expect("t-new")
        model.select("other")
        mac.upsertWorkspace(linkWorkspace(terminals = terminals("zsh", "other", "t-new", selected = "zsh")))
        assertTrue(eventually { model.panes.any { it.id == "t-new" } })
        delay(50.milliseconds)
        assertEquals("other", model.selectedTerminalId)
    } }

    /** The user typing into the shell shown settles the screen on it, like a pick: an agent that starts asking later does
     *  not move it (the iPhone's final review, app I2). */
    @Test fun typingIntoTheChipShownKeepsItWhenAnAgentAsks() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("zsh", "claude", agent = mapOf("claude" to "s1"), selected = "zsh"))))
        val screen = makeModel(mac)
        val model = screen.model
        assertEquals("zsh", model.selectedTerminalId)

        model.settle()
        mac.upsertSession(agentSession("s1", state = AgentState.NEEDS_INPUT))
        mac.addPending(pendingItem("r1"))
        assertTrue(eventually { screen.hub.pendingItems.size == 1 })
        delay(50.milliseconds)
        assertEquals("zsh", model.selectedTerminalId)
    } }

    /**
     * ＋ while a new terminal is on its way is refused, and a chip the user picks before the Mac answers stays shown when
     * the new tab arrives; once answered, ＋ works again, and its tab shows (the model's half of the iPhone's
     * `testAPickWhileANewTerminalIsOnItsWayWins` and `testPlusIsDimmedWhileANewTerminalIsOnItsWay`).
     */
    @Test fun aPickWhileANewTerminalIsOnItsWayWins() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace(terminals = terminals("zsh", "other", selected = "zsh"))))
        val model = makeModel(mac).model
        assertTrue(model.startCreatingTerminal())
        assertFalse(model.startCreatingTerminal(), "one create at a time")
        assertTrue(model.creatingTerminal); assertTrue(model.state.value.creatingTerminal)
        model.select("other")
        model.finishCreatingTerminal("t-new")
        assertFalse(model.creatingTerminal)
        mac.upsertWorkspace(linkWorkspace(terminals = terminals("zsh", "other", "t-new", selected = "zsh")))
        assertTrue(eventually { model.panes.any { it.id == "t-new" } })
        delay(50.milliseconds)
        assertEquals("other", model.selectedTerminalId, "the user's pick wins over the new tab")

        assertTrue(model.startCreatingTerminal(), "once answered, ＋ works again")
        model.finishCreatingTerminal(null)
        assertFalse(model.creatingTerminal)
        assertTrue(model.startCreatingTerminal())
        mac.upsertWorkspace(linkWorkspace(terminals = terminals("zsh", "other", "t-new", "t-2", selected = "zsh")))
        assertTrue(eventually { model.panes.any { it.id == "t-2" } })
        model.finishCreatingTerminal("t-2")
        assertEquals("t-2", model.selectedTerminalId, "answered with its tab listed already: it shows at once")
    } }
}
