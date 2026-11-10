package com.shellx.app.ui.workspaces

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.HomeFixtures
import com.shellx.app.testing.HomeFixtures.macbook
import com.shellx.app.testing.HomeFixtures.mini
import com.shellx.core.link.MachineLinkState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** What a Mac's group shows under its header, and what its header says (WorkspaceListRenderTests). */
@RunWith(AndroidJUnit4::class)
class WorkspaceGroupTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun rowsShowOnlyWhileTheMacIsOrWasJustOnline() {
        assertEquals(
            listOf(true, true, true, false, false, false, false),
            listOf(
                MachineLinkState.Online, MachineLinkState.Connecting, MachineLinkState.Reconnecting,
                MachineLinkState.Offline(HomeFixtures.NOW_MS), MachineLinkState.Revoked, MachineLinkState.HostKeyChanged,
                MachineLinkState.NeedsUpdate,
            ).map(WorkspaceGroup::rowsShow),
        )
    }

    @Test
    fun listingFollowsTheMac() {
        assertEquals(WorkspaceGroup.Listing.ROWS, macbook.listing)
        assertEquals("an offline Mac shows no rows", WorkspaceGroup.Listing.HIDDEN, mini.listing)
        assertEquals(listOf("shellx-ios", "relay", "web", "notes"), macbook.rows.map { it.title })
        assertFalse(macbook.showsOtherSessions)

        // ShellX 1.5.1 on the Mac: no workspaces and no workspace_control, but its agents stay reachable.
        val old = WorkspaceGroup(
            id = "m3", name = "iMac", state = MachineLinkState.Online, isDefault = false, rows = emptyList(),
            allowsControl = false, listsWorkspaces = false, otherSessionCount = 2,
        )
        assertEquals(WorkspaceGroup.Listing.UPDATE_MAC, old.listing)
        assertTrue("the old Mac's sessions stay reachable", old.showsOtherSessions)

        val empty = macbook.copy(rows = emptyList())
        assertEquals(WorkspaceGroup.Listing.EMPTY, empty.listing)
    }

    @Test
    fun otherSessionsNeedRowsAndSessions() {
        val group = macbook.copy(otherSessionCount = 3)
        val offline = mini.copy(otherSessionCount = 5)
        assertTrue(group.showsOtherSessions)
        assertFalse("an offline Mac shows no row under its header", offline.showsOtherSessions)
        assertFalse("no row when there is nothing to list", macbook.showsOtherSessions)
    }

    @Test
    fun theCaptionSaysWhyThereAreNoRows() {
        val offline = MachineGroupHeaderText.caption(MachineLinkState.Offline(HomeFixtures.eightTwelve), "Mac mini", context)
        val time = MachineGroupHeaderText.time(HomeFixtures.eightTwelve, context)
        assertTrue("$offline names the last time", offline!!.contains(time))
        assertNull(MachineGroupHeaderText.caption(MachineLinkState.Online, "Mac", context))
        for (state in listOf(
            MachineLinkState.Revoked, MachineLinkState.HostKeyChanged, MachineLinkState.NeedsUpdate,
            MachineLinkState.Connecting, MachineLinkState.Reconnecting,
        )) {
            assertFalse("$state", MachineGroupHeaderText.caption(state, "Mac", context).isNullOrEmpty())
        }
    }
}
