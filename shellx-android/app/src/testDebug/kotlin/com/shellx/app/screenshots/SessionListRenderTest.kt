package com.shellx.app.screenshots

import androidx.compose.ui.res.stringResource
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.testing.HomeFixtures.NOW_MS
import com.shellx.app.ui.home.FocusKind
import com.shellx.app.ui.home.SessionListScreen
import com.shellx.core.home.FocusItem
import com.shellx.core.home.HomeFocus
import com.shellx.core.home.SessionName
import com.shellx.core.link.MachineSession
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The two session lists (WorkspaceListRenderTests' other-sessions and Ended renders). */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
class SessionListRenderTest {
    private fun machineSession(
        id: String,
        title: String,
        state: AgentState,
        sinceMs: Long,
        machine: String = "m1",
        machineName: String = "MacBook Pro",
        workspace: String = "",
    ) = MachineSession(
        machineId = machine, machineName = machineName, online = true,
        session = AgentSession(
            sessionId = id, agent = "claude", workspaceId = if (workspace.isEmpty()) "" else "ws-$workspace",
            workspaceTitle = workspace, title = title, state = state, stateSinceMs = sinceMs, lastActivityMs = sinceMs,
        ),
    )

    @Test
    fun otherSessionsList() {
        val sessions = listOf(
            machineSession("s1", "X", AgentState.WORKING, NOW_MS - 240_000, workspace = "old-experiment"),
            machineSession("s2", "X", AgentState.IDLE, NOW_MS - 60_000, workspace = "old-experiment"),
        )
        val names = SessionName.distinct(sessions, ZoneOffset.UTC)
        assertEquals(listOf("X", "X · #2"), sessions.map { names[it.ref] })
        val items = sessions.map { FocusItem(it, names[it.ref] ?: "") }
        assertRenders("workspaces-other-sessions-list") {
            SessionListScreen(
                title = stringResource(R.string.workspaces_other_title), header = "MacBook Pro", items = items,
                kind = { if (it.session.session.state == AgentState.WORKING) FocusKind.RUNNING else FocusKind.ENDED },
                nowMs = NOW_MS, showsMachineName = false, empty = R.string.workspaces_other_empty, openAgent = {}, back = {},
            )
        }
    }

    @Test
    fun otherSessionsEmpty() {
        assertRenders("workspaces-other-sessions-empty") {
            SessionListScreen(
                title = stringResource(R.string.workspaces_other_title), header = "MacBook Pro", items = emptyList(),
                kind = { FocusKind.RUNNING }, nowMs = NOW_MS, showsMachineName = false,
                empty = R.string.workspaces_other_empty, openAgent = {}, back = {},
            )
        }
    }

    @Test
    fun endedList() {
        val sessions = listOf(
            machineSession("e1", "Release 1.5.1", AgentState.ENDED, NOW_MS - 7_200_000, workspace = "web"),
            machineSession("e2", "Fix the flaky test", AgentState.ENDED, NOW_MS - 14_400_000, workspace = "shellx"),
            machineSession(
                "e3", "Benchmark", AgentState.ENDED, NOW_MS - 30_000_000, machine = "m2", machineName = "Mac mini",
                workspace = "bench",
            ),
        )
        val focus = HomeFocus.make(sessions, emptyList(), emptyMap(), nowMs = NOW_MS)
        assertEquals(listOf("e1", "e2", "e3"), focus.ended.map { it.session.session.sessionId })
        assertRenders("ended-list") {
            SessionListScreen(
                title = stringResource(R.string.ended_title), header = null, items = focus.ended, kind = { FocusKind.ENDED },
                nowMs = NOW_MS, showsMachineName = true, empty = R.string.ended_empty, openAgent = {}, back = {},
                remove = {},
            )
        }
    }

    @Test
    fun endedEmpty() {
        assertRenders("ended-empty") {
            SessionListScreen(
                title = stringResource(R.string.ended_title), header = null, items = emptyList(), kind = { FocusKind.ENDED },
                nowMs = NOW_MS, showsMachineName = false, empty = R.string.ended_empty, openAgent = {}, back = {},
            )
        }
    }
}
