package com.shellx.app.ui.nav

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.link.HubState
import com.shellx.core.link.MachineModel
import com.shellx.core.link.SessionRef
import com.shellx.core.link.SessionSet
import com.shellx.core.workspaces.WorkspaceRef
import com.shellx.link.account.PairedMachine
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** The contract route names (contracts §5, §20) and how their arguments are written. */
@RunWith(AndroidJUnit4::class)
class RoutesTest {
    @Test
    fun theRoutesAreTheContractNames() {
        assertEquals("launch", Routes.LAUNCH)
        assertEquals("sign_in", Routes.SIGN_IN)
        assertEquals("first_mac", Routes.FIRST_MAC)
        assertEquals("pairing", Routes.PAIRING)
        assertEquals("home", Routes.HOME)
        assertEquals("demo", Routes.DEMO)
        assertEquals("machines", Routes.MACHINES)
        assertEquals("settings", Routes.SETTINGS)
        assertEquals("workspace/{machineId}/{workspaceId}", WorkRoutes.WORKSPACE)
        assertEquals("agent/{machineId}/{sessionId}", WorkRoutes.AGENT)
        assertTrue(WorkRoutes.PENDING.startsWith("pending"))
        assertTrue(Routes.SESSIONS.startsWith("sessions/{kind}"))
        assertEquals(setOf("ended", "other"), SessionListKind.entries.map { it.wire }.toSet())
    }

    @Test
    fun everyArgumentIsEncoded() {
        assertEquals("workspace/m%2F1/ws%201%25", WorkRoutes.workspace(WorkspaceRef("m/1", "ws 1%")))
        assertEquals("agent/m1/s%201", WorkRoutes.agent(SessionRef("m1", "s 1", "claude", "x")))
        assertEquals("pending", WorkRoutes.pending())
        assertEquals("pending?machineId=m1&workspaceId=ws%2F2", WorkRoutes.pendingIn("m1", "ws/2"))
        assertEquals("sessions/ended", Routes.sessions(SessionListKind.ENDED))
        assertEquals("sessions/other?machineId=m%201", Routes.sessions(SessionListKind.OTHER, "m 1"))
    }

    @Test
    fun theAgentRouteFindsItsSessionOrKeepsTheIds() {
        val machine = PairedMachine("m1", "MacBook Pro", "slot-1", ByteArray(32))
        val session = AgentSession("s1", "claude", "ws-1", "shellx-ios", state = AgentState.WORKING)
        val state = HubState(machines = listOf(MachineModel(machine, sessions = SessionSet(1, listOf(session)))), isLoaded = true)

        val found = WorkRoutes.sessionRef(state, "m1", "s1")
        assertEquals("claude", found.agent)
        assertEquals("shellx-ios", found.workspaceTitle)

        val missing = WorkRoutes.sessionRef(state, "m1", "nope")
        assertEquals(SessionRef("m1", "nope", "", ""), missing)
        assertEquals("", missing.agent)
        assertEquals("", missing.workspaceTitle)
    }
}
