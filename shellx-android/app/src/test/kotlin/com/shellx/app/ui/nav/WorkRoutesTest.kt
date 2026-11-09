package com.shellx.app.ui.nav

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.WorkRig
import com.shellx.core.link.SessionRef
import com.shellx.core.workspaces.WorkspaceRef
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/** The three work routes (contracts §20) and the agent route's ref. */
@RunWith(AndroidJUnit4::class)
class WorkRoutesTest {
    @Test
    fun routesEncodeTheirIds() {
        assertEquals("workspace/m1/ws-1", WorkRoutes.workspace(WorkspaceRef("m1", "ws-1")))
        assertEquals("agent/m1/s%201", WorkRoutes.agent(SessionRef("m1", "s 1", "claude", "x")))
        assertEquals("pending?machineId=m1&workspaceId=ws%2F2", WorkRoutes.pendingIn("m1", "ws/2"))
    }

    @Test
    fun theAgentRouteFindsItsSessionOrKeepsTheIds() {
        val rig = WorkRig.make()
        try {
            val state = rig.hub.state.value
            val found = WorkRoutes.sessionRef(state, rig.machineId, "s1")
            assertEquals("claude", found.agent)
            assertEquals("shellx-ios", found.workspaceTitle)
            assertEquals(SessionRef(rig.machineId, "nope", "", ""), WorkRoutes.sessionRef(state, rig.machineId, "nope"))
        } finally {
            rig.close()
        }
    }
}
