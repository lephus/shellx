package com.shellx.app.ui.workspaces

import android.content.Context
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.testing.WorkRig
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.workspaces.WorkspaceRef
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** The workspace screen over a signed-in rig: the Mac closes the pane shown, or the whole workspace. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w400dp-h900dp")
class WorkspaceViewTest {
    @get:Rule val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val rig = WorkRig.make()
    private var backs = 0

    @After
    fun tearDown() = rig.close()

    private fun show() = compose.setContent {
        ShellXTheme { WorkspaceView(rig.scope, WorkspaceRef(rig.machineId, "ws-shellx"), open = {}, back = { backs++ }) }
    }

    private fun until(condition: () -> Boolean) = compose.waitUntil(10_000) {
        compose.waitForIdle()
        condition()
    }

    private fun shown(text: String): Boolean = compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    @Test
    fun thePaneClosedOnTheMacShowsTheNoticeThenItGoes() {
        show()
        until { shown(context.getString(R.string.workspace_shell_placeholder)) }
        rig.mac.upsertWorkspace(
            LinkWorkspace(
                "ws-shellx", "shellx-ios", 0, directory = "~/shellx/shellx-ios", branch = "feat/workspaces",
                terminals = listOf(LinkTerminal("t-claude", "claude", 0, selected = true, sessionId = "s1")),
            ),
        )
        val notice = context.getString(R.string.workspace_pane_closed_on_mac)
        until { shown(notice) }
        compose.onNodeWithTag("workspace.chip.t-claude").assertIsSelected()
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(4_100)
        assertTrue("the notice goes after 4 s", !shown(notice))
        compose.mainClock.autoAdvance = true
    }

    @Test
    fun aWorkspaceClosedOnTheMacLeavesWithTheListsNotice() {
        show()
        until { shown(context.getString(R.string.workspace_shell_placeholder)) }
        rig.mac.removeWorkspace("ws-shellx")
        until { backs == 1 }
        compose.waitForIdle()
        assertEquals(1, backs)
        assertEquals(context.getString(R.string.workspace_closed_on_mac), rig.scope.listNotice.current.value?.text)
    }
}
