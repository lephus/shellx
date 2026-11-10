package com.shellx.app.ui.home

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.AppComposition
import com.shellx.app.LaunchMark
import com.shellx.app.SignedInScope
import com.shellx.app.testing.ManualClock
import com.shellx.app.testing.ScriptedRelay
import com.shellx.core.account.AccountVault
import com.shellx.core.demo.DemoSecretStore
import com.shellx.core.demo.FakeMacFleet
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.home.HomeFocus
import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachineSession
import com.shellx.core.platform.KeyValueStore
import com.shellx.core.platform.MemoryKeyValueStore
import com.shellx.core.storage.ConversationStore
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith

/** The Ended page's trash as the signed-in scope wires it (EndedDismissalsWiringTests): the scope keeps the dismissals
 *  in the settings it was made with, so the next launch's scope still has them. */
@RunWith(AndroidJUnit4::class)
class EndedDismissalsWiringTest {
    @get:Rule val folder = TemporaryFolder()

    private val clock = ManualClock()

    private fun TestScope.makeScope(settings: KeyValueStore): SignedInScope {
        val io = StandardTestDispatcher(testScheduler)
        val vault = AccountVault(DemoSecretStore(), io)
        val relay = ScriptedRelay()
        val latency = LatencyLog()
        val hub = MachineHub(
            vault, relay, FakeMacFleet(emptyList()) { vault.phoneKey() }, latency, settings, backgroundScope, clock,
        ) {}
        return AppComposition.makeScope(
            hub, relay, vault, ConversationStore(folder.newFolder(), io, clock), latency, LaunchMark(latency, clock),
            settings, clock, voice = null,
        )
    }

    private fun ended(id: String, endedMs: Long) = MachineSession(
        machineId = "m1", machineName = "MacBook Pro", online = true,
        session = AgentSession(
            sessionId = id, agent = "claude", workspaceId = "", workspaceTitle = "", state = AgentState.ENDED,
            stateSinceMs = endedMs, lastActivityMs = endedMs,
        ),
    )

    @Test
    fun aCardTakenOffTheEndedPageStaysOffAfterALaunch() {
        runTest {
            val settings = MemoryKeyValueStore()
            val now = clock.nowMs()
            val sessions = listOf(ended("a", now - 600_000), ended("b", now - 600_000))
            fun page(scope: SignedInScope) = HomeFocus.make(
                sessions, emptyList(), emptyMap(), dismissed = scope.endedDismissals.dismissals.value, nowMs = now,
            ).ended.map { it.session.session.sessionId }

            val scope = makeScope(settings)
            assertEquals(listOf("a", "b"), page(scope))
            scope.endedDismissals.dismiss(sessions[0])
            assertEquals(listOf("b"), page(scope))

            val relaunched = makeScope(settings)
            assertEquals("the home's fold counts one too", listOf("b"), page(relaunched))
        }
    }
}
