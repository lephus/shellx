package com.shellx.app.screenshots

import androidx.compose.runtime.Composable
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.HomeFixtures
import com.shellx.app.testing.HomeFixtures.NOW_MS
import com.shellx.app.testing.HomeFixtures.item
import com.shellx.app.testing.HomeFixtures.macbook
import com.shellx.app.testing.HomeFixtures.mini
import com.shellx.app.testing.HomeFixtures.mockup
import com.shellx.app.testing.HomeFixtures.session
import com.shellx.app.ui.workspaces.WorkspaceGroup
import com.shellx.app.ui.workspaces.WorkspaceListScreen
import com.shellx.app.ui.workspaces.WorkspaceRenameContent
import com.shellx.core.home.HomeFocus
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.MachinePendingItem
import com.shellx.link.core.AgentState
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The home (WorkspaceListRenderTests' screens): mockup A, a quiet home, old Macs, two Macs, every group state. */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
class HomeRenderTest {
    @Composable
    private fun List(
        groups: List<WorkspaceGroup>,
        focus: HomeFocus = HomeFocus.EMPTY,
        pending: List<MachinePendingItem> = emptyList(),
        showsMachineNames: Boolean = false,
    ) {
        WorkspaceListScreen(groups = groups, focus = focus, pending = pending, nowMs = NOW_MS, showsMachineNames = showsMachineNames)
    }

    private val oldMac = WorkspaceGroup(
        id = "m1", name = "MacBook Pro", state = MachineLinkState.Online, isDefault = true, rows = emptyList(),
        allowsControl = false, listsWorkspaces = false, otherSessionCount = 3,
    )

    @Test
    fun homeFocus() {
        assertRenders("home-focus") { List(listOf(macbook), mockup) }
    }

    @Test
    fun homeFocusLargeText() {
        assertRenders("home-focus-large-text") { LargeText { List(listOf(macbook), mockup) } }
    }

    @Test
    fun homeQuiet() {
        assertRenders("home-quiet") { List(listOf(macbook)) }
    }

    @Test
    fun homeOldMac() {
        // ShellX 1.5.1 on the Mac: no workspaces and no workspace_control, but its agents still sort.
        val focus = HomeFocus.EMPTY.copy(
            running = listOf(
                item(session("s1", "Viết test SessionSet", AgentState.WORKING, 8.0)),
                item(session("s2", "Dọn README", AgentState.WORKING, 1.0, agent = "codex")),
            ),
        )
        assertEquals(WorkspaceGroup.Listing.UPDATE_MAC, oldMac.listing)
        assertRenders("home-old-mac") { List(listOf(oldMac), focus) }
    }

    @Test
    fun homeTwoMacs() {
        // The Mac mini is coming back: its card is its last known one, faded.
        val reconnecting = mini.copy(state = MachineLinkState.Reconnecting)
        val focus = mockup.copy(
            running = mockup.running + item(
                session(
                    "s9", "Chạy benchmark", AgentState.WORKING, 30.0, workspace = "bench", machine = "m2",
                    machineName = "Mac mini", online = false,
                ),
            ),
        )
        assertRenders("home-two-macs") { List(listOf(macbook, reconnecting), focus, showsMachineNames = true) }
    }

    @Test
    fun workspaces() {
        assertRenders("workspaces") { List(listOf(macbook, mini), pending = HomeFixtures.pending) }
    }

    @Test
    fun workspacesError() {
        val group = macbook.copy(rows = macbook.rows + HomeFixtures.broken)
        assertRenders("workspaces-error") { List(listOf(group)) }
    }

    @Test
    fun workspacesLargeText() {
        val group = macbook.copy(rows = macbook.rows + HomeFixtures.broken)
        assertRenders("workspaces-large-text") { LargeText { List(listOf(group), pending = HomeFixtures.pending) } }
    }

    @Test
    fun workspacesOldMac() {
        val old = WorkspaceGroup(
            id = "m3", name = "iMac", state = MachineLinkState.Online, isDefault = false, rows = emptyList(),
            allowsControl = false, listsWorkspaces = false, otherSessionCount = 2,
        )
        assertRenders("workspaces-old-mac") { List(listOf(macbook, old)) }
    }

    @Test
    fun workspacesOtherSessions() {
        assertRenders("workspaces-other-sessions") {
            List(listOf(macbook.copy(otherSessionCount = 3), mini.copy(otherSessionCount = 5)))
        }
    }

    @Test
    fun workspacesEmpty() {
        assertRenders("workspaces-empty") { List(listOf(macbook.copy(rows = emptyList()))) }
    }

    @Test
    fun workspacesOffline() {
        assertRenders("workspaces-offline") { List(listOf(mini)) }
    }

    @Test
    fun workspacesRename() {
        assertRenders("workspaces-rename") { WorkspaceRenameContent("shellx-ios", save = {}, cancel = {}) }
    }
}
