package com.shellx.core.link

import com.shellx.core.demo.FakeMac
import com.shellx.core.testing.ManualClock
import com.shellx.core.testing.ManualSleeper
import com.shellx.core.testing.agentSession
import com.shellx.core.testing.eventually
import com.shellx.core.testing.hubRig
import com.shellx.core.testing.instantSleep
import com.shellx.core.testing.linkTerminal
import com.shellx.core.testing.linkWorkspace
import com.shellx.core.testing.pendingItem
import com.shellx.core.workspaces.WorkspaceCommandResult
import com.shellx.core.workspaces.WorkspaceRef
import com.shellx.core.workspaces.WorkspaceState
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.LinkWorkspace
import com.shellx.link.core.WorkspaceControlOutcome
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.async
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest

/** The hub's workspace list, rows and control calls, against a FakeMac (MachineHubWorkspaceTests.swift). */
class MachineHubWorkspaceTest {
    private suspend fun TestScope.makeHub(
        mac: FakeMac,
        sleep: suspend (Duration) -> Unit = instantSleep,
        clock: ManualClock = ManualClock(),
    ): MachineHub = makeHub(listOf(mac), sleep, clock)

    private suspend fun TestScope.makeHub(
        macs: List<FakeMac>,
        sleep: suspend (Duration) -> Unit = instantSleep,
        clock: ManualClock = ManualClock(),
    ): MachineHub = hubRig(macs, sleep = sleep, clock = clock, start = true).hub

    private fun ref(mac: FakeMac, workspace: String = "shellx"): WorkspaceRef = WorkspaceRef(mac.machine.machineId, "ws-$workspace")

    private fun isOnline(hub: MachineHub): Boolean = hub.machines.firstOrNull()?.state == MachineLinkState.Online

    private fun isOffline(hub: MachineHub): Boolean = hub.machines.firstOrNull()?.state is MachineLinkState.Offline

    // The list

    @Test fun listArrivesAfterConnect() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(
            listOf(
                linkWorkspace("web", order = 1),
                linkWorkspace("shellx", order = 0, terminals = listOf(linkTerminal("t1")), directory = "~/code/shellx", branch = "main"),
            ),
        )
        val hub = makeHub(mac)
        val id = mac.machine.machineId

        val arrived = eventually { hub.workspaceRows(id).size == 2 }

        assertTrue(arrived)
        val rows = hub.workspaceRows(id)
        assertEquals(listOf("shellx", "web"), rows.map { it.title })
        assertEquals("~/code/shellx", rows[0].directory)
        assertEquals("main", rows[0].branch)
        assertEquals(listOf("t1"), rows[0].terminals.map { it.terminalId })
        assertEquals(listOf(WorkspaceState.IDLE, WorkspaceState.IDLE), rows.map { it.state })
        assertEquals(true, hub.machines.firstOrNull()?.workspacesSupported)
        assertTrue(hub.supportsWorkspaceControl(id))
        assertEquals(1, mac.workspaceListCount)
    } }

    @Test fun oldMacWithoutFeatureIsUnsupported() { runTest {
        val mac = FakeMac("Old Mac", backgroundScope, servesWorkspaces = false)
        mac.upsertSession(agentSession("s1"))
        val hub = makeHub(mac)
        val id = mac.machine.machineId

        val ready = eventually { isOnline(hub) && hub.liveSessions.size == 1 }

        assertTrue(ready)
        assertEquals(false, hub.machines.firstOrNull()?.workspacesSupported)
        assertEquals(emptyList(), hub.workspaceRows(id))
        assertFalse(hub.supportsWorkspaceControl(id))
        // With no list every session is one a terminal does not name.
        assertEquals(listOf("s1"), hub.otherSessions(id).map { it.session.sessionId })
    } }

    /** What LAUNCH_TO_WORKSPACE_LIST waits for: the default Mac answered with its list. An old Mac never does. */
    @Test fun theDefaultMacHasListedItsWorkspacesOnceItsListArrived() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        val hub = makeHub(mac)
        assertTrue(eventually { hub.defaultMachineListedWorkspaces })
        assertEquals(1, hub.workspaceRows(mac.machine.machineId).size, "the list is there")

        val old = FakeMac("Old Mac", backgroundScope, servesWorkspaces = false)
        val oldHub = makeHub(old)
        assertTrue(eventually { isOnline(oldHub) })
        assertFalse(oldHub.defaultMachineListedWorkspaces)
    } }

    @Test fun listThatDoesNotFitLeavesTheSessionOnlineAndUnsupported() { runTest {
        // One workspace too big for a frame: the list answers `too_large`. That must not cost the phone the Mac (the
        // pending requests ride the same session).
        val huge = LinkWorkspace(workspaceId = "ws-huge", title = "w".repeat(70_000), order = 0, terminals = emptyList())
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(huge))
        mac.addPending(pendingItem("r1", createdAtMs = 10))
        val hub = makeHub(mac)
        val id = mac.machine.machineId

        assertTrue(eventually { isOnline(hub) && hub.pendingItems.size == 1 }, "${hub.machines.firstOrNull()?.state}")
        assertEquals(false, hub.machines.firstOrNull()?.workspacesSupported)
        assertEquals(emptyList(), hub.workspaceRows(id))
        assertEquals(1, mac.workspaceListCount, "the list was asked for once and refused")

        // The Mac still pushes its changes (the small ones fit a frame). With no list to apply them to, they are left
        // alone: no refetch, no dropped session, no partial list.
        mac.upsertWorkspace(linkWorkspace("web", order = 1))
        mac.upsertWorkspace(linkWorkspace("docs", order = 2))
        mac.addPending(pendingItem("r2", createdAtMs = 20))
        assertTrue(eventually { hub.pendingItems.size == 2 })
        val reacted = eventually(timeout = 300.milliseconds) { mac.workspaceListCount > 1 || mac.connectCount > 1 }
        assertFalse(reacted, "a change of a list the phone cannot read does not end the session")
        assertTrue(isOnline(hub))
        assertEquals(listOf(true, true), hub.pendingItems.map { it.actionable })
        assertEquals(false, hub.machines.firstOrNull()?.workspacesSupported)
        assertEquals(emptyList(), hub.workspaceRows(id))
    } }

    @Test fun changesArriveAsTheyHappen() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        val hub = makeHub(mac)
        val id = mac.machine.machineId
        eventually { hub.workspaceRows(id).size == 1 }

        mac.upsertWorkspace(linkWorkspace("web", order = 1))
        mac.upsertWorkspace(linkWorkspace("shellx", order = 0, terminals = listOf(linkTerminal("t9"))))
        mac.removeWorkspace("ws-web")

        val applied = eventually {
            val rows = hub.workspaceRows(id)
            rows.map { it.title } == listOf("shellx") && rows[0].terminals.map { it.terminalId } == listOf("t9")
        }
        assertTrue(applied, "${hub.workspaceRows(id)}")
        assertEquals(1, mac.workspaceListCount, "every change applied on its own, no refetch")
    } }

    @Test fun gapRefetchesList() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        val hub = makeHub(mac)
        val id = mac.machine.machineId
        eventually { hub.workspaceRows(id).size == 1 }

        mac.skipNextWorkspaceRevision()
        mac.upsertWorkspace(linkWorkspace("web", order = 1))

        val resynced = eventually { hub.workspaceRows(id).map { it.title } == listOf("shellx", "web") }
        assertTrue(resynced, "${hub.workspaceRows(id)}")
        assertEquals(2, mac.workspaceListCount, "a gap asks for the list again")
        assertEquals(1, mac.connectCount, "inside the live session")
        assertTrue(isOnline(hub))
    } }

    @Test fun reconnectReplacesList() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("old-a"), linkWorkspace("old-b", order = 1)))
        val sleeper = ManualSleeper()
        val hub = makeHub(mac, sleep = sleeper.sleep)
        val id = mac.machine.machineId
        assertTrue(eventually { hub.workspaceRows(id).size == 2 })

        mac.dropLiveSessions()
        val waiting = eventually { hub.machines.firstOrNull()?.state == MachineLinkState.Reconnecting && sleeper.waiting.size == 1 }
        assertTrue(waiting, "${hub.machines.firstOrNull()?.state}")
        mac.setWorkspaces(listOf(linkWorkspace("new", order = 0)))
        // The last known list stays while the Mac is out of reach, as the sessions do.
        assertEquals(listOf("old-a", "old-b"), hub.workspaceRows(id).map { it.title })

        sleeper.release()

        val replaced = eventually { isOnline(hub) && hub.workspaceRows(id).map { it.title } == listOf("new") }
        assertTrue(replaced, "${hub.workspaceRows(id).map { it.title }}")
        assertEquals(2, mac.connectCount)
    } }

    // Refresh

    @Test fun refreshAsksTheMacAgainAndTakesItsRevision() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        val hub = makeHub(mac)
        val id = mac.machine.machineId
        eventually { hub.workspaceRows(id).size == 1 }

        // The Mac's list moved on without telling the phone.
        mac.skipNextWorkspaceRevision()
        hub.refreshWorkspaces()

        assertEquals(2, mac.workspaceListCount, "the refresh asked for the list")
        // The next change is the revision after the refreshed list: applied on its own, no gap.
        mac.upsertWorkspace(linkWorkspace("web", order = 1))
        assertTrue(eventually { hub.workspaceRows(id).map { it.title } == listOf("shellx", "web") })
        assertEquals(2, mac.workspaceListCount, "no second refetch for a gap")
    } }

    @Test fun refreshLeavesAMacThatIsNotOnlineAlone() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        val sleeper = ManualSleeper()
        val hub = makeHub(mac, sleep = sleeper.sleep)
        val id = mac.machine.machineId
        eventually { hub.workspaceRows(id).size == 1 }
        mac.dropLiveSessions()
        assertTrue(eventually { hub.machines.firstOrNull()?.state == MachineLinkState.Reconnecting })

        hub.refreshWorkspaces()
        hub.refreshWorkspaces("mac-unknown")

        assertEquals(1, mac.workspaceListCount, "nothing is asked of a Mac that is out of reach")
        assertEquals(listOf("shellx"), hub.workspaceRows(id).map { it.title })
    } }

    // Control

    @Test fun createRenameCloseCallMac() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        val hub = makeHub(mac)
        val id = mac.machine.machineId
        eventually { hub.workspaceRows(id).size == 1 }

        val created = hub.createWorkspace(id)
        val newId = assertNotNull((created as? WorkspaceCommandResult.Ok)?.workspaceId, "$created")
        assertTrue(eventually { hub.workspaceRows(id).any { it.id.workspaceId == newId } })

        val newRef = WorkspaceRef(id, newId)
        assertEquals(WorkspaceCommandResult.Ok(null), hub.renameWorkspace(newRef, "Docs"))
        assertTrue(eventually { hub.workspaceRows(id).firstOrNull { it.id == newRef }?.title == "Docs" })

        assertEquals(WorkspaceCommandResult.Ok(null), hub.closeWorkspace(newRef))
        assertTrue(eventually { hub.workspaceRows(id).map { it.id.workspaceId } == listOf("ws-shellx") })

        assertEquals(listOf("create", "rename:$newId:Docs", "close:$newId"), mac.workspaceCalls)
    } }

    @Test fun refusedCloseKeepsRow() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        val hub = makeHub(mac)
        val id = mac.machine.machineId
        eventually { hub.workspaceRows(id).size == 1 }

        mac.setNextWorkspaceOutcome(WorkspaceControlOutcome.REFUSED)
        assertEquals(WorkspaceCommandResult.Refused, hub.closeWorkspace(ref(mac)))

        // A later change arrives after any wrong removal would have: the row is still there.
        mac.upsertWorkspace(linkWorkspace("web", order = 1))
        assertTrue(eventually { hub.workspaceRows(id).size == 2 })
        assertEquals(listOf("shellx", "web"), hub.workspaceRows(id).map { it.title })

        // The outcome was for one call: the next close is the Mac's own answer.
        assertEquals(WorkspaceCommandResult.Ok(null), hub.closeWorkspace(ref(mac)))
        assertTrue(eventually { hub.workspaceRows(id).map { it.title } == listOf("web") })
    } }

    @Test fun outcomesMapToResults() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        val hub = makeHub(mac)
        val id = mac.machine.machineId
        eventually { hub.workspaceRows(id).size == 1 }

        val expected = listOf(
            WorkspaceControlOutcome.NOT_FOUND to WorkspaceCommandResult.NotFound,
            WorkspaceControlOutcome.REFUSED to WorkspaceCommandResult.Refused,
            WorkspaceControlOutcome.FAILED to WorkspaceCommandResult.Failed,
            // An outcome from a newer Mac: it answered, but what it did is not known.
            WorkspaceControlOutcome("queued") to WorkspaceCommandResult.Unknown,
        )
        for ((outcome, result) in expected) {
            mac.setNextWorkspaceOutcome(outcome)
            assertEquals(result, hub.createWorkspace(id), "create $outcome")
            mac.setNextWorkspaceOutcome(outcome)
            assertEquals(result, hub.renameWorkspace(ref(mac), "x"), "rename $outcome")
            mac.setNextWorkspaceOutcome(outcome)
            assertEquals(result, hub.closeWorkspace(ref(mac)), "close $outcome")
        }
        assertEquals(listOf("shellx"), hub.workspaceRows(id).map { it.title })
    } }

    @Test fun realNotFoundForAnIdTheMacDoesNotHave() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val hub = makeHub(mac)
        val id = mac.machine.machineId
        eventually { isOnline(hub) }

        val renamed = hub.renameWorkspace(WorkspaceRef(id, "ws-gone"), "x")
        val closed = hub.closeWorkspace(WorkspaceRef(id, "ws-gone"))

        assertEquals(listOf(WorkspaceCommandResult.NotFound, WorkspaceCommandResult.NotFound), listOf(renamed, closed))
    } }

    @Test fun macThatIsNotOnlineAnswersOfflineWithoutCalling() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.failNextConnects(IOException("offline"), 1000)
        val sleeper = ManualSleeper()
        val hub = makeHub(mac, sleep = sleeper.sleep)
        val id = mac.machine.machineId
        assertTrue(eventually { isOffline(hub) })

        val created = hub.createWorkspace(id)
        val renamed = hub.renameWorkspace(ref(mac), "x")
        val closed = hub.closeWorkspace(ref(mac))
        val unknownMac = hub.createWorkspace("mac-nobody")

        assertEquals(List(4) { WorkspaceCommandResult.Offline }, listOf(created, renamed, closed, unknownMac))
        assertEquals(emptyList(), mac.workspaceCalls)
    } }

    @Test fun connectionLostWhileWaitingIsUnknownAndNotSentAgain() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val sleeper = ManualSleeper()
        val hub = makeHub(mac, sleep = sleeper.sleep)
        val id = mac.machine.machineId
        eventually { isOnline(hub) }
        mac.holdWorkspaceControl()

        val call = backgroundScope.async { hub.createWorkspace(id) }
        assertTrue(eventually { mac.workspaceCalls == listOf("create") })
        // The link drops while the Mac still holds the call.
        mac.dropLiveSessions()
        val result = call.await()
        mac.releaseWorkspaceControl()

        assertEquals(WorkspaceCommandResult.Unknown, result)
        // The Mac did act (it made the workspace); the phone finds out from the list, not by retrying.
        assertTrue(eventually { sleeper.waiting.size == 1 })
        sleeper.release()
        val back = eventually { isOnline(hub) && hub.workspaceRows(id).size == 1 }
        assertTrue(back, "${hub.workspaceRows(id)}")
        assertEquals(listOf("create"), mac.workspaceCalls)
    } }

    @Test fun supportsWorkspaceControlFollowsTheFeature() { runTest {
        val withControl = FakeMac("New Mac", backgroundScope)
        val readOnly = FakeMac("Read-only Mac", backgroundScope, acceptsWorkspaceControl = false)
        readOnly.setWorkspaces(listOf(linkWorkspace("shellx")))

        val hubA = makeHub(withControl)
        val hubB = makeHub(readOnly)

        // Unknown until the Mac was online once.
        val a = eventually { isOnline(hubA) }
        val b = eventually { isOnline(hubB) && hubB.workspaceRows(readOnly.machine.machineId).size == 1 }
        assertTrue(a && b)
        assertTrue(hubA.supportsWorkspaceControl(withControl.machine.machineId))
        assertFalse(hubB.supportsWorkspaceControl(readOnly.machine.machineId))
        assertFalse(hubA.supportsWorkspaceControl("mac-nobody"))
        assertEquals(WorkspaceCommandResult.Failed, hubB.createWorkspace(readOnly.machine.machineId), "nothing is sent to a Mac that takes no control")
        assertEquals(emptyList(), readOnly.workspaceCalls)
    } }

    // Closing an agent

    private fun sessionRef(mac: FakeMac, sessionId: String = "s1"): SessionRef =
        SessionRef(mac.machine.machineId, sessionId, "claude", "shellx")

    private fun sessionState(hub: MachineHub, sessionId: String): AgentState? =
        hub.reachableSessions.firstOrNull { it.session.sessionId == sessionId }?.session?.state

    /**
     * The Swift test reads HomeFocus (`running`, `ended`), which is Task 22. Until then it checks the same facts on the
     * hub: a running session is a live one that works, an ended one is reachable and ENDED but no longer live.
     */
    @Test fun closeAgentCallsTheMacAndTheSessionEnds() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        mac.upsertSession(agentSession("s1", state = AgentState.WORKING))
        val hub = makeHub(mac)
        val running = eventually {
            isOnline(hub) && hub.liveSessions.map { it.session.sessionId } == listOf("s1") &&
                sessionState(hub, "s1") == AgentState.WORKING
        }
        assertTrue(running)

        val closed = hub.closeAgent(sessionRef(mac))

        assertEquals(WorkspaceCommandResult.Ok(null), closed)
        assertEquals(listOf("s1"), mac.agentCloses)
        // The Mac reports the session ended, the way its liveness sweep does: it leaves Running for Ended.
        assertTrue(eventually { sessionState(hub, "s1") == AgentState.ENDED }, "${sessionState(hub, "s1")}")
        assertEquals(emptyList(), hub.liveSessions.map { it.session.sessionId })
        assertEquals(
            listOf("s1"),
            hub.reachableSessions.filter { it.session.state == AgentState.ENDED }.map { it.session.sessionId },
        )
    } }

    @Test fun closeAgentOutcomesMapToResults() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        mac.upsertSession(agentSession("s1", state = AgentState.WORKING))
        val hub = makeHub(mac)
        assertTrue(eventually { isOnline(hub) && sessionState(hub, "s1") == AgentState.WORKING })

        val expected = listOf(
            WorkspaceControlOutcome.NOT_FOUND to WorkspaceCommandResult.NotFound,
            WorkspaceControlOutcome.REFUSED to WorkspaceCommandResult.Refused,
            WorkspaceControlOutcome.FAILED to WorkspaceCommandResult.Failed,
            // An outcome from a newer Mac: it answered, but what it did is not known.
            WorkspaceControlOutcome("queued") to WorkspaceCommandResult.Unknown,
        )
        for ((outcome, result) in expected) {
            mac.setNextAgentCloseOutcome(outcome)
            assertEquals(result, hub.closeAgent(sessionRef(mac)), "close $outcome")
        }

        assertEquals(listOf("s1", "s1", "s1", "s1"), mac.agentCloses)
        // None of them was an `ok`: the session still runs.
        assertEquals(AgentState.WORKING, sessionState(hub, "s1"))
    } }

    @Test fun realNotFoundForASessionTheMacDoesNotHave() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.upsertSession(agentSession("s1", state = AgentState.ENDED))
        val hub = makeHub(mac)
        assertTrue(eventually { isOnline(hub) && sessionState(hub, "s1") == AgentState.ENDED })

        val unknown = hub.closeAgent(sessionRef(mac, "s-gone"))
        val ended = hub.closeAgent(sessionRef(mac))

        assertEquals(listOf(WorkspaceCommandResult.NotFound, WorkspaceCommandResult.NotFound), listOf(unknown, ended))
    } }

    @Test fun closeAgentWithoutTheFeatureIsFailedWithoutCalling() { runTest {
        val mac = FakeMac("Old Mac", backgroundScope, acceptsAgentClose = false)
        mac.upsertSession(agentSession("s1", state = AgentState.WORKING))
        val hub = makeHub(mac)
        assertTrue(eventually { isOnline(hub) && sessionState(hub, "s1") == AgentState.WORKING })

        // Such a Mac has no agent control to count a call, and it would answer an agent close with an `unsupported`
        // error, which the hub also maps to Failed: only the calls the phone made show that nothing went out.
        val before = mac.phoneCallCount
        val closed = hub.closeAgent(sessionRef(mac))
        val after = mac.phoneCallCount

        assertEquals(WorkspaceCommandResult.Failed, closed)
        assertEquals(before, after, "nothing is sent to a Mac that takes no agent control")
        assertEquals(emptyList(), mac.agentCloses)
        assertEquals(AgentState.WORKING, sessionState(hub, "s1"))

        // The count does see a call that is sent: the Mac does take workspace control.
        val created = hub.createWorkspace(mac.machine.machineId)
        assertTrue(created is WorkspaceCommandResult.Ok, "$created")
        assertTrue(mac.phoneCallCount > after)
    } }

    @Test fun closeAgentOfflineMacIsOffline() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.failNextConnects(IOException("offline"), 1000)
        val sleeper = ManualSleeper()
        val hub = makeHub(mac, sleep = sleeper.sleep)
        assertTrue(eventually { isOffline(hub) })

        val closed = hub.closeAgent(sessionRef(mac))
        val unknownMac = hub.closeAgent(SessionRef("mac-nobody", "s1", "claude", "shellx"))

        assertEquals(listOf(WorkspaceCommandResult.Offline, WorkspaceCommandResult.Offline), listOf(closed, unknownMac))
        assertEquals(emptyList(), mac.agentCloses)
    } }

    @Test fun closeAgentIsSentOnce() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.upsertSession(agentSession("s1", state = AgentState.WORKING))
        val sleeper = ManualSleeper()
        val hub = makeHub(mac, sleep = sleeper.sleep)
        assertTrue(eventually { isOnline(hub) && sessionState(hub, "s1") == AgentState.WORKING })
        mac.holdWorkspaceControl()

        val call = backgroundScope.async { hub.closeAgent(sessionRef(mac)) }
        assertTrue(eventually { mac.agentCloses == listOf("s1") })
        // The link drops while the Mac still holds the call.
        mac.dropLiveSessions()
        val result = call.await()
        mac.releaseWorkspaceControl()

        assertEquals(WorkspaceCommandResult.Unknown, result)
        // The Mac did act (the session ended); the phone finds out from the list, not by retrying.
        assertTrue(eventually { sleeper.waiting.size == 1 })
        sleeper.release()
        assertTrue(eventually { isOnline(hub) && sessionState(hub, "s1") == AgentState.ENDED }, "${sessionState(hub, "s1")}")
        assertEquals(1, mac.agentCloses.size)
    } }

    @Test fun supportsAgentCloseFollowsTheFeature() { runTest {
        val withClose = FakeMac("New Mac", backgroundScope)
        val without = FakeMac("Old Mac", backgroundScope, acceptsAgentClose = false)

        val hubA = makeHub(withClose)
        val hubB = makeHub(without)
        val aUp = eventually { isOnline(hubA) }
        val bUp = eventually { isOnline(hubB) }
        assertTrue(aUp && bUp)

        assertTrue(hubA.supportsAgentClose(withClose.machine.machineId))
        assertFalse(hubB.supportsAgentClose(without.machine.machineId))
        assertFalse(hubA.supportsAgentClose("mac-nobody"))
        // The two features are separate: the old Mac still takes workspace control.
        assertTrue(hubB.supportsWorkspaceControl(without.machine.machineId))
    } }

    // Closing a terminal tab

    private fun terminalIds(hub: MachineHub, mac: FakeMac, workspace: String = "shellx"): List<String>? =
        hub.workspaceRows(mac.machine.machineId).firstOrNull { it.id.workspaceId == "ws-$workspace" }?.terminals?.map { it.terminalId }

    /** Every terminal close the Mac received, as `<workspaceId>/<terminalId>`. */
    private fun terminalCloseCalls(mac: FakeMac): List<String> = mac.terminalCloses.map { "${it.workspaceId}/${it.terminalId}" }

    @Test fun closeTerminalCallsTheMacAndTheTabGoes() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(
            listOf(
                linkWorkspace("shellx", order = 0, terminals = listOf(linkTerminal("t1", order = 0), linkTerminal("t2", order = 1))),
                linkWorkspace("web", order = 1, terminals = listOf(linkTerminal("w1"))),
            ),
        )
        val hub = makeHub(mac)
        val id = mac.machine.machineId
        assertTrue(eventually { isOnline(hub) && terminalIds(hub, mac) == listOf("t1", "t2") })

        val closed = hub.closeTerminal(id, "ws-shellx", "t1")

        assertEquals(WorkspaceCommandResult.Ok(null), closed)
        assertEquals(listOf("ws-shellx/t1"), terminalCloseCalls(mac))
        // The Mac's list change takes the tab away; the other workspace is not touched.
        assertTrue(eventually { terminalIds(hub, mac) == listOf("t2") }, "${terminalIds(hub, mac)}")
        assertEquals(listOf("w1"), terminalIds(hub, mac, "web"))

        // The last tab closes its workspace, the way the Mac does by default.
        assertEquals(WorkspaceCommandResult.Ok(null), hub.closeTerminal(id, "ws-shellx", "t2"))
        assertTrue(eventually { hub.workspaceRows(id).map { it.title } == listOf("web") }, "${hub.workspaceRows(id).map { it.title }}")
    } }

    @Test fun closeTerminalOutcomesMapToResults() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(
            listOf(
                linkWorkspace("shellx", order = 0, terminals = listOf(linkTerminal("t1", order = 0), linkTerminal("t2", order = 1))),
                linkWorkspace("web", order = 1, terminals = listOf(linkTerminal("w1"))),
            ),
        )
        val hub = makeHub(mac)
        val id = mac.machine.machineId
        assertTrue(eventually { isOnline(hub) && terminalIds(hub, mac) == listOf("t1", "t2") })

        val expected = listOf(
            WorkspaceControlOutcome.NOT_FOUND to WorkspaceCommandResult.NotFound,
            WorkspaceControlOutcome.REFUSED to WorkspaceCommandResult.Refused,
            WorkspaceControlOutcome.FAILED to WorkspaceCommandResult.Failed,
            // An outcome from a newer Mac: it answered, but what it did is not known.
            WorkspaceControlOutcome("queued") to WorkspaceCommandResult.Unknown,
        )
        for ((outcome, result) in expected) {
            mac.setNextTerminalCloseOutcome(outcome)
            assertEquals(result, hub.closeTerminal(id, "ws-shellx", "t1"), "close $outcome")
        }

        // Without a forced outcome the Mac answers for what it lists: a terminal of another workspace, a terminal that
        // is not there and a workspace that is not there are all NOT_FOUND.
        val elsewhere = hub.closeTerminal(id, "ws-shellx", "w1")
        val missing = hub.closeTerminal(id, "ws-shellx", "t-gone")
        val noWorkspace = hub.closeTerminal(id, "ws-gone", "t1")
        assertEquals(List(3) { WorkspaceCommandResult.NotFound }, listOf(elsewhere, missing, noWorkspace))

        assertEquals(List(4) { "ws-shellx/t1" } + listOf("ws-shellx/w1", "ws-shellx/t-gone", "ws-gone/t1"), terminalCloseCalls(mac))
        // None of them was an `ok`: every tab is still there.
        assertEquals(listOf("t1", "t2"), terminalIds(hub, mac))
        assertEquals(listOf("w1"), terminalIds(hub, mac, "web"))
    } }

    @Test fun closeTerminalWithoutTheFeatureSendsNothing() { runTest {
        val mac = FakeMac("Old Mac", backgroundScope, acceptsTerminalClose = false)
        mac.setWorkspaces(listOf(linkWorkspace("shellx", terminals = listOf(linkTerminal("t1")))))
        val hub = makeHub(mac)
        val id = mac.machine.machineId
        assertTrue(eventually { isOnline(hub) && terminalIds(hub, mac) == listOf("t1") })

        // Such a Mac has no terminal control to count a call, and it would answer a terminal close with an `unsupported`
        // error, which the hub also maps to Failed: only the calls the phone made show that nothing went out.
        val before = mac.phoneCallCount
        val closed = hub.closeTerminal(id, "ws-shellx", "t1")
        val after = mac.phoneCallCount

        assertEquals(WorkspaceCommandResult.Failed, closed)
        assertEquals(before, after, "nothing is sent to a Mac that takes no terminal control")
        assertEquals(emptyList(), terminalCloseCalls(mac))
        assertEquals(listOf("t1"), terminalIds(hub, mac))

        // The count does see a call that is sent: the Mac does take workspace control.
        val created = hub.createWorkspace(id)
        assertTrue(created is WorkspaceCommandResult.Ok, "$created")
        assertTrue(mac.phoneCallCount > after)
    } }

    @Test fun closeTerminalOfflineMacIsOffline() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.failNextConnects(IOException("offline"), 1000)
        val sleeper = ManualSleeper()
        val hub = makeHub(mac, sleep = sleeper.sleep)
        assertTrue(eventually { isOffline(hub) })

        val closed = hub.closeTerminal(mac.machine.machineId, "ws-shellx", "t1")
        val unknownMac = hub.closeTerminal("mac-nobody", "ws-shellx", "t1")

        assertEquals(listOf(WorkspaceCommandResult.Offline, WorkspaceCommandResult.Offline), listOf(closed, unknownMac))
        assertEquals(emptyList(), terminalCloseCalls(mac))
    } }

    @Test fun closeTerminalIsSentOnce() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(
            listOf(linkWorkspace("shellx", order = 0, terminals = listOf(linkTerminal("t1", order = 0), linkTerminal("t2", order = 1)))),
        )
        val sleeper = ManualSleeper()
        val hub = makeHub(mac, sleep = sleeper.sleep)
        val id = mac.machine.machineId
        assertTrue(eventually { isOnline(hub) && terminalIds(hub, mac) == listOf("t1", "t2") })
        mac.holdWorkspaceControl()

        val call = backgroundScope.async { hub.closeTerminal(id, "ws-shellx", "t1") }
        assertTrue(eventually { mac.terminalCloses.size == 1 })
        // The link drops while the Mac still holds the call.
        mac.dropLiveSessions()
        val result = call.await()
        mac.releaseWorkspaceControl()

        assertEquals(WorkspaceCommandResult.Unknown, result)
        // The Mac did act (the tab is gone); the phone finds out from the list, not by retrying.
        assertTrue(eventually { sleeper.waiting.size == 1 })
        sleeper.release()
        assertTrue(eventually { isOnline(hub) && terminalIds(hub, mac) == listOf("t2") }, "${terminalIds(hub, mac)}")
        assertEquals(listOf("ws-shellx/t1"), terminalCloseCalls(mac))
    } }

    @Test fun supportsTerminalCloseFollowsTheFeature() { runTest {
        val withClose = FakeMac("New Mac", backgroundScope)
        val without = FakeMac("Old Mac", backgroundScope, acceptsTerminalClose = false)

        val hubA = makeHub(withClose)
        val hubB = makeHub(without)
        val aUp = eventually { isOnline(hubA) }
        val bUp = eventually { isOnline(hubB) }
        assertTrue(aUp && bUp)

        assertTrue(hubA.supportsTerminalClose(withClose.machine.machineId))
        assertFalse(hubB.supportsTerminalClose(without.machine.machineId))
        assertFalse(hubA.supportsTerminalClose("mac-nobody"))
        // The features are separate: the Mac without terminal control still takes workspace control and agent closes.
        assertTrue(hubB.supportsWorkspaceControl(without.machine.machineId))
        assertTrue(hubB.supportsAgentClose(without.machine.machineId))
    } }

    // Sessions no terminal names

    @Test fun otherSessionsExcludeChippedOnes() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(
            listOf(
                linkWorkspace("shellx", terminals = listOf(linkTerminal("t1", sessionId = "s1"), linkTerminal("t2"))),
                linkWorkspace("web", order = 1, terminals = listOf(linkTerminal("t3", sessionId = "s3"))),
            ),
        )
        mac.upsertSession(agentSession("s1", lastActivityMs = 500))
        // In a listed workspace, but in no terminal.
        mac.upsertSession(agentSession("s2", lastActivityMs = 400))
        mac.upsertSession(agentSession("s3", state = AgentState.IDLE, lastActivityMs = 300, workspace = "web"))
        // Ended, and its workspace is not on the list any more: left out of the others.
        mac.upsertSession(
            AgentSession(
                sessionId = "s4", agent = "claude", workspaceId = "ws-closed", workspaceTitle = "closed", state = AgentState.ENDED,
                stateSinceMs = 1, lastActivityMs = 200,
            ),
        )
        // No workspace at all.
        mac.upsertSession(
            AgentSession(
                sessionId = "s5", agent = "claude", workspaceId = "", workspaceTitle = "", state = AgentState.IDLE,
                stateSinceMs = 1, lastActivityMs = 100,
            ),
        )
        val hub = makeHub(mac)
        val id = mac.machine.machineId

        val ready = eventually {
            hub.workspaceRows(id).size == 2 && hub.otherSessions(id).size == 2 && hub.machines.firstOrNull()?.sessions?.sessions?.size == 5
        }

        assertTrue(ready, "${hub.otherSessions(id).map { it.session.sessionId }}")
        val others = hub.otherSessions(id)
        assertEquals(listOf("s2", "s5"), others.map { it.session.sessionId })
        assertEquals(listOf(id, id), others.map { it.machineId })
        assertEquals(listOf("MacBook Pro", "MacBook Pro"), others.map { it.machineName })
        assertEquals(listOf(true, true), others.map { it.online })
        assertEquals(emptyList(), hub.otherSessions("mac-nobody"))
        // A listed terminal names `s1` and `s3`: none of the others, nor the ended `s4` of a closed workspace.
        val named = { machineId: String, sessionId: String -> hub.hasListedTerminal(SessionRef(machineId, sessionId, "claude", "")) }
        assertEquals(listOf("s1", "s3"), listOf("s1", "s2", "s3", "s4", "s5").filter { named(id, it) })
        assertFalse(named("mac-nobody", "s1"))
    } }

    // Finish times

    private val start = 1_800_000_000_000L

    @Test fun aFinishIsTimedWhenThePhoneSawIt() { runTest {
        val clock = ManualClock(start)
        val (mac, hub, id) = finishedRig(clock)

        mac.upsertSession(agentSession("s1", state = AgentState.IDLE, lastActivityMs = 2, stateSinceMs = 2))

        assertTrue(eventually { hub.finishedSessionIds(id) == setOf("s1") })
        assertEquals(start, hub.finishTimes[id]?.get("s1"))
    } }

    @Test fun aFinishKeepsItsFirstTime() { runTest {
        val clock = ManualClock(start)
        val (mac, hub, id) = finishedRig(clock)
        mac.upsertSession(agentSession("s1", state = AgentState.IDLE, lastActivityMs = 2, stateSinceMs = 2))
        assertTrue(eventually { hub.finishedSessionIds(id) == setOf("s1") })

        clock.wallMs = start + 600_000
        mac.upsertSession(agentSession("s2", state = AgentState.IDLE, lastActivityMs = 3, stateSinceMs = 3, workspace = "web"))

        assertTrue(eventually { hub.finishedSessionIds(id) == setOf("s1", "s2") })
        assertEquals(mapOf("s1" to start, "s2" to start + 600_000), hub.finishTimes[id])
    } }

    @Test fun markSeenOfASessionClearsOnlyIt() { runTest {
        val (mac, hub, id) = finishedRig()
        mac.upsertSession(agentSession("s1", state = AgentState.IDLE, lastActivityMs = 2, stateSinceMs = 2))
        mac.upsertSession(agentSession("s2", state = AgentState.IDLE, lastActivityMs = 2, stateSinceMs = 2, workspace = "web"))
        assertTrue(eventually { hub.finishedSessionIds(id) == setOf("s1", "s2") })

        hub.markSeen(SessionRef(id, "s1", "claude", "shellx"))

        assertEquals(setOf("s2"), hub.finishedSessionIds(id))
        assertEquals(listOf("s2"), hub.finishTimes[id]?.keys?.sorted())
    } }

    @Test fun otherSessionsLeaveOutEndedOnes() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        mac.upsertSession(agentSession("s1", state = AgentState.ENDED))
        val hub = makeHub(mac)
        val id = mac.machine.machineId

        val listed = eventually { isOnline(hub) && hub.machines.firstOrNull()?.sessions?.sessions?.size == 1 }

        assertTrue(listed)
        assertEquals(emptyList(), hub.otherSessions(id))
    } }

    @Test fun reachableSessionsHoldEveryStateOfAReachableMac() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        mac.upsertSession(agentSession("s1", state = AgentState.WORKING, lastActivityMs = 2, stateSinceMs = 1))
        mac.upsertSession(agentSession("s2", state = AgentState.ENDED, lastActivityMs = 1, stateSinceMs = 1))
        val hub = makeHub(mac)

        val listed = eventually { isOnline(hub) && hub.reachableSessions.size == 2 }

        assertTrue(listed, "${hub.reachableSessions.map { it.session.sessionId }}")
        assertEquals(listOf("s1", "s2"), hub.reachableSessions.map { it.session.sessionId })
        assertEquals(listOf(true, true), hub.reachableSessions.map { it.online })
    } }

    @Test fun reachableSessionsKeepAReconnectingMacsSessionsAsNotOnline() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.upsertSession(agentSession("s1", state = AgentState.WORKING, lastActivityMs = 1, stateSinceMs = 1))
        val sleeper = ManualSleeper()
        val hub = makeHub(mac, sleep = sleeper.sleep)
        assertTrue(eventually { isOnline(hub) && hub.reachableSessions.size == 1 })

        mac.dropLiveSessions()
        val down = eventually { hub.machines.firstOrNull()?.state == MachineLinkState.Reconnecting && sleeper.waiting.size == 1 }

        assertTrue(down, "${hub.machines.firstOrNull()?.state}")
        assertEquals(listOf("s1"), hub.reachableSessions.map { it.session.sessionId })
        assertEquals(listOf(false), hub.reachableSessions.map { it.online })
    } }

    @Test fun reachableSessionsLeaveOutAnOfflineMac() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val b = FakeMac("Mac mini", backgroundScope)
        a.upsertSession(agentSession("a1", state = AgentState.WORKING, lastActivityMs = 1, stateSinceMs = 1))
        b.upsertSession(agentSession("b1", state = AgentState.WORKING, lastActivityMs = 2, stateSinceMs = 1))
        b.failNextConnects(IOException("offline"), 1)
        val sleeper = ManualSleeper()
        val hub = makeHub(listOf(a, b), sleep = sleeper.sleep)

        val settled = eventually {
            hub.machines.firstOrNull { it.id == b.machine.machineId }?.state is MachineLinkState.Offline &&
                hub.machines.firstOrNull { it.id == a.machine.machineId }?.state == MachineLinkState.Online &&
                hub.reachableSessions.size == 1
        }

        assertTrue(settled, "${hub.machines.map { it.state }}")
        assertEquals(listOf("a1"), hub.reachableSessions.map { it.session.sessionId })
    } }

    // Done

    private suspend fun TestScope.finishedRig(clock: ManualClock = ManualClock()): Triple<FakeMac, MachineHub, String> {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(
            listOf(linkWorkspace("shellx", terminals = listOf(linkTerminal("t1", sessionId = "s1"))), linkWorkspace("web", order = 1)),
        )
        mac.upsertSession(agentSession("s1", state = AgentState.WORKING, lastActivityMs = 1, stateSinceMs = 1))
        mac.upsertSession(agentSession("s2", state = AgentState.WORKING, lastActivityMs = 1, stateSinceMs = 1, workspace = "web"))
        val hub = makeHub(mac, clock = clock)
        val id = mac.machine.machineId
        val running = eventually { hub.workspaceRows(id).map { it.state } == listOf(WorkspaceState.RUNNING, WorkspaceState.RUNNING) }
        assertTrue(running, "${hub.workspaceRows(id).map { it.state }}")
        return Triple(mac, hub, id)
    }

    @Test fun doneFromFinishedSession() { runTest {
        val (mac, hub, id) = finishedRig()
        assertEquals(emptySet(), hub.finishedSessionIds(id))

        mac.upsertSession(agentSession("s1", state = AgentState.IDLE, lastActivityMs = 2, stateSinceMs = 2))

        val done = eventually { hub.workspaceRows(id).map { it.state } == listOf(WorkspaceState.DONE, WorkspaceState.RUNNING) }
        assertTrue(done, "${hub.workspaceRows(id).map { it.state }}")
        assertEquals(setOf("s1"), hub.finishedSessionIds(id))
        assertEquals(emptySet(), hub.finishedSessionIds("mac-nobody"))
    } }

    @Test fun doneClearsAfterMarkSeen() { runTest {
        val (mac, hub, id) = finishedRig()
        mac.upsertSession(agentSession("s1", state = AgentState.IDLE, lastActivityMs = 2, stateSinceMs = 2))
        mac.upsertSession(agentSession("s2", state = AgentState.IDLE, lastActivityMs = 2, stateSinceMs = 2, workspace = "web"))
        val both = eventually { hub.workspaceRows(id).map { it.state } == listOf(WorkspaceState.DONE, WorkspaceState.DONE) }
        assertTrue(both, "${hub.workspaceRows(id).map { it.state }}")

        hub.markSeen(ref(mac))

        assertEquals(listOf(WorkspaceState.IDLE, WorkspaceState.DONE), hub.workspaceRows(id).map { it.state }, "only the opened workspace")
        assertEquals(setOf("s2"), hub.finishedSessionIds(id))
        // The same finish replayed (a resync, a nudge) is not a new one.
        mac.upsertSession(agentSession("s1", state = AgentState.IDLE, lastActivityMs = 3, stateSinceMs = 2))
        val replayed = eventually { hub.liveSessions.firstOrNull { it.session.sessionId == "s1" }?.session?.lastActivityMs == 3L }
        assertTrue(replayed)
        assertEquals(listOf(WorkspaceState.IDLE, WorkspaceState.DONE), hub.workspaceRows(id).map { it.state })
    } }

    @Test fun doneEndsWhenTheAgentWorksAgain() { runTest {
        val (mac, hub, id) = finishedRig()
        mac.upsertSession(agentSession("s1", state = AgentState.IDLE, lastActivityMs = 2, stateSinceMs = 2))
        assertTrue(eventually { hub.finishedSessionIds(id) == setOf("s1") })

        mac.upsertSession(agentSession("s1", state = AgentState.WORKING, lastActivityMs = 3, stateSinceMs = 3))
        assertTrue(eventually { hub.workspaceRows(id).map { it.state } == listOf(WorkspaceState.RUNNING, WorkspaceState.RUNNING) })
        assertEquals(emptySet(), hub.finishedSessionIds(id))

        // The next finish is a new one, and it shows.
        mac.upsertSession(agentSession("s1", state = AgentState.IDLE, lastActivityMs = 4, stateSinceMs = 4))
        assertTrue(eventually { hub.workspaceRows(id).map { it.state } == listOf(WorkspaceState.DONE, WorkspaceState.RUNNING) })
    } }

    @Test fun idleFromTheStartIsNotDone() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        mac.upsertSession(agentSession("s1", state = AgentState.IDLE))
        val hub = makeHub(mac)
        val id = mac.machine.machineId

        val ready = eventually { isOnline(hub) && hub.liveSessions.size == 1 }

        assertTrue(ready)
        assertEquals(listOf(WorkspaceState.IDLE), hub.workspaceRows(id).map { it.state })
        assertEquals(emptySet(), hub.finishedSessionIds(id))
    } }

    @Test fun finishWhileDisconnectedIsDoneOnReconnect() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx")))
        mac.upsertSession(agentSession("s1", state = AgentState.WORKING, lastActivityMs = 1, stateSinceMs = 1))
        val sleeper = ManualSleeper()
        val hub = makeHub(mac, sleep = sleeper.sleep)
        val id = mac.machine.machineId
        assertTrue(eventually { hub.workspaceRows(id).map { it.state } == listOf(WorkspaceState.RUNNING) })

        mac.dropLiveSessions()
        assertTrue(eventually { hub.machines.firstOrNull()?.state == MachineLinkState.Reconnecting && sleeper.waiting.size == 1 })
        mac.upsertSession(agentSession("s1", state = AgentState.IDLE, lastActivityMs = 2, stateSinceMs = 2))
        sleeper.release()

        val done = eventually { hub.workspaceRows(id).map { it.state } == listOf(WorkspaceState.DONE) }
        assertTrue(done, "${hub.workspaceRows(id).map { it.state }}")
    } }

    @Test fun pendingMakesTheRowNeedYou() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx"), linkWorkspace("web", order = 1)))
        mac.upsertSession(agentSession("s1", state = AgentState.WORKING))
        mac.addPending(pendingItem("r1", workspace = "shellx"))
        val hub = makeHub(mac)
        val id = mac.machine.machineId

        val ready = eventually { hub.workspaceRows(id).map { it.state } == listOf(WorkspaceState.NEEDS_YOU, WorkspaceState.IDLE) }

        assertTrue(ready, "${hub.workspaceRows(id).map { it.state }}")
        assertEquals("ls", hub.workspaceRows(id).firstOrNull()?.question)
    } }
}
