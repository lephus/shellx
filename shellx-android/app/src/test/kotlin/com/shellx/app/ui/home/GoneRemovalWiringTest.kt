package com.shellx.app.ui.home

import androidx.compose.runtime.mutableStateOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.AppComposition
import com.shellx.app.LaunchMark
import com.shellx.app.SignedInScope
import com.shellx.app.testing.RecordingNavigator
import com.shellx.app.testing.TestComposition
import com.shellx.app.testing.testComposition
import com.shellx.app.testing.waitFor
import com.shellx.app.ui.workspaces.OtherSessionsModel
import com.shellx.app.ui.workspaces.WorkspaceListActions
import com.shellx.app.ui.workspaces.WorkspaceListModel
import com.shellx.app.ui.workspaces.WorkspaceListScreenActions
import com.shellx.core.demo.FakeMac
import com.shellx.core.home.HomeFocus
import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.MachineSession
import com.shellx.core.link.SessionRef
import com.shellx.core.storage.ConversationStore
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import kotlinx.coroutines.test.StandardTestDispatcher
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
 * "Remove from This Phone" as the signed-in scope wires it (GoneRemovalWiringTests), against a fake Mac that lists two
 * ghosts beside two live agents. The agent screen is plan 3E's: `scope.goneRemovals.noteGone(session)` stands in for
 * the iPhone's `AgentView.noteGone` (an agent screen heard its Mac answer `not_found`). Removing a ghost takes it off
 * every list and count, also after a launch, until its Mac reports a change.
 */
@RunWith(AndroidJUnit4::class)
class GoneRemovalWiringTest {
    @get:Rule val folder = TemporaryFolder()

    private class Rig(val t: TestComposition, val scope: SignedInScope, val mac: FakeMac, val actions: WorkspaceListScreenActions) {
        val hub: MachineHub get() = scope.hub
        val id: String get() = mac.machine.machineId
        val nowMs: Long get() = t.clock.nowMs()

        fun session(sessionId: String): MachineSession = hub.reachableSessions.first { it.session.sessionId == sessionId }
    }

    private fun session(id: String, workspace: String, sinceMs: Long, activityMs: Long) = AgentSession(
        sessionId = id, agent = "claude", workspaceId = if (workspace.isEmpty()) "" else "ws-$workspace",
        workspaceTitle = workspace, state = AgentState.WORKING, stateSinceMs = sinceMs, lastActivityMs = activityMs,
    )

    /** `ws-shellx` names `live` and `ghost` (working for 52 hours) in its tabs; outside workspaces run `outsideLive`
     *  and `outsideGhost`. */
    private suspend fun TestScope.makeRig(): Rig {
        val mac = FakeMac("Richard's Mac mini (2)", backgroundScope)
        val t = testComposition(folder.root, macs = listOf(mac))
        val now = t.clock.nowMs()
        val fiftyTwoHoursAgo = now - 52 * 3_600_000L
        mac.setWorkspaces(
            listOf(
                LinkWorkspace(
                    "ws-shellx", "shellx", 0,
                    terminals = listOf(
                        LinkTerminal("t1", "claude", 0, selected = true, sessionId = "live"),
                        LinkTerminal("t2", "claude", 1, selected = false, sessionId = "ghost"),
                    ),
                ),
            ),
        )
        mac.upsertSession(session("live", "shellx", now - 60_000, now))
        mac.upsertSession(session("ghost", "shellx", fiftyTwoHoursAgo, fiftyTwoHoursAgo))
        mac.upsertSession(session("outsideLive", "", now - 120_000, now - 1))
        mac.upsertSession(session("outsideGhost", "", fiftyTwoHoursAgo, fiftyTwoHoursAgo - 1))

        t.composition.lifecycle.onStart()
        val id = mac.machine.machineId
        assertTrue(
            waitFor {
                val scope = t.composition.real.scopes.current.value ?: return@waitFor false
                scope.hub.machines.firstOrNull()?.state == MachineLinkState.Online &&
                    scope.hub.reachableSessions.size == 4 && scope.hub.workspaceRows(id).size == 1
            },
        )
        val scope = t.composition.real.scopes.current.value!!
        val actions = WorkspaceListActions.make(scope, RecordingNavigator(), {}, mutableStateOf(false))
        return Rig(t, scope, mac, actions)
    }

    /** The scope the next launch makes: the same settings, nothing in memory. */
    private fun TestScope.relaunchedScope(rig: Rig): SignedInScope {
        val io = StandardTestDispatcher(testScheduler)
        val real = rig.t.composition.real
        return AppComposition.makeScope(
            rig.hub, real.relay, real.vault, ConversationStore(folder.newFolder(), io, rig.t.clock), rig.scope.latency,
            LaunchMark(rig.scope.latency, rig.t.clock), rig.t.settings, rig.t.clock, voice = null,
        )
    }

    /** What the agent screen tells the scope when its Mac answers `not_found` (3E's AgentView). */
    private fun openGone(rig: Rig, sessionId: String) = rig.scope.goneRemovals.noteGone(rig.session(sessionId))

    private fun running(rig: Rig, scope: SignedInScope = rig.scope): List<String> = homeFocus(rig, scope).running.map { it.session.session.sessionId }

    private fun homeFocus(rig: Rig, scope: SignedInScope = rig.scope) = HomeFocus.make(
        rig.hub.reachableSessions, emptyList(), rig.hub.finishTimes, scope.endedDismissals.dismissals.value,
        scope.goneRemovals.removals, rig.nowMs,
    )

    private fun outside(rig: Rig, scope: SignedInScope = rig.scope): List<String> =
        OtherSessionsModel.sessions(rig.hub.state.value, rig.id, scope.goneRemovals.removals).map { it.session.sessionId }

    private fun otherCount(rig: Rig): Int? =
        WorkspaceListModel.groups(rig.hub.state.value, rig.scope.goneRemovals.removals).firstOrNull()?.otherSessionCount

    @Test
    fun aRemovedGhostLeavesEveryListAndCountAndStaysOffAfterALaunch() {
        runTest {
            val rig = makeRig()
            assertEquals(listOf("live", "outsideLive", "ghost", "outsideGhost"), running(rig))
            assertEquals(2, otherCount(rig))
            openGone(rig, "ghost")
            openGone(rig, "outsideGhost")
            assertEquals(
                "the outside list's swipe is offered for the outside ghost only",
                setOf(rig.session("outsideGhost").ref),
                rig.scope.goneRemovals.removable(OtherSessionsModel.sessions(rig.hub.state.value, rig.id, rig.scope.goneRemovals.removals)),
            )

            // The home's swipe, then the outside-workspace list's.
            rig.actions.removeFromPhone(rig.session("ghost"))
            rig.scope.goneRemovals.remove(rig.session("outsideGhost"))

            val focus = homeFocus(rig)
            assertEquals(listOf("live", "outsideLive"), running(rig))
            assertTrue(focus.needsYou.isEmpty() && focus.justDone.isEmpty() && focus.ended.isEmpty())
            assertEquals(listOf("outsideLive"), outside(rig))
            assertEquals("\"Agents outside workspaces · N\" counts one", 1, otherCount(rig))
            assertEquals("nothing was asked of the Mac", 4, rig.hub.reachableSessions.size)

            val relaunched = relaunchedScope(rig)
            assertEquals(listOf("live", "outsideLive"), running(rig, relaunched))
            assertEquals(listOf("outsideLive"), outside(rig, relaunched))
            assertEquals(
                "known gone is this run's only; removals stay",
                emptySet<SessionRef>(), WorkspaceListModel.removableAgents(rig.hub.state.value, relaunched.goneRemovals),
            )
        }
    }

    @Test
    fun aRemovedGhostComesBackWhenItsMacReportsAChange() {
        runTest {
            val rig = makeRig()
            openGone(rig, "ghost")
            rig.actions.removeFromPhone(rig.session("ghost"))
            assertFalse("ghost" in running(rig))

            val fiftyTwoHoursAgo = rig.nowMs - 52 * 3_600_000L
            rig.mac.upsertSession(session("ghost", "shellx", fiftyTwoHoursAgo, rig.nowMs + 1_000))

            assertTrue("a newer last activity shows it again", waitFor { "ghost" in running(rig) })
            assertEquals(
                "it changed since the phone saw it gone: no swipe",
                emptySet<SessionRef>(), WorkspaceListModel.removableAgents(rig.hub.state.value, rig.scope.goneRemovals),
            )
        }
    }
}
