package com.shellx.app.ui.workspaces

import android.content.Context
import android.content.res.Resources
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.ui.theme.StatusTone
import com.shellx.app.ui.workspaces.WorkspaceFixtures.NOW_MS
import com.shellx.app.ui.workspaces.WorkspaceFixtures.claude
import com.shellx.app.ui.workspaces.WorkspaceFixtures.panes
import com.shellx.app.ui.workspaces.WorkspaceFixtures.request
import com.shellx.app.ui.workspaces.WorkspaceFixtures.session
import com.shellx.app.ui.workspaces.WorkspaceFixtures.workspace
import com.shellx.core.workspaces.WorkspacePane
import com.shellx.core.workspaces.WorkspaceScreenModel
import com.shellx.link.core.AgentState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

/** The workspace screen's words (`WorkspaceRenderTests.swift`' logic tests). */
@RunWith(AndroidJUnit4::class)
class WorkspaceTextsTest {
    private val res: Resources get() = ApplicationProvider.getApplicationContext<Context>().resources

    @Test
    fun theMenuOffersRenameCloseTabAndCloseWorkspace() {
        assertEquals("a Mac from before terminal_close", listOf(WorkspaceMenuItem.RENAME, WorkspaceMenuItem.CLOSE_WORKSPACE), WorkspaceMenuItem.items(false))
        assertEquals(
            "any tab, agent or shell: it replaces Close Agent… here",
            listOf(WorkspaceMenuItem.RENAME, WorkspaceMenuItem.CLOSE_TAB, WorkspaceMenuItem.CLOSE_WORKSPACE), WorkspaceMenuItem.items(true),
        )
        val titles = WorkspaceMenuItem.entries.map { res.getString(it.title) }
        assertEquals(
            listOf(res.getString(R.string.workspace_menu_rename), res.getString(R.string.terminal_close_menu), res.getString(R.string.workspace_menu_close)),
            titles,
        )
        assertEquals(3, titles.toSet().size)
        assertEquals(listOf(WorkspaceMenuItem.CLOSE_TAB, WorkspaceMenuItem.CLOSE_WORKSPACE), WorkspaceMenuItem.entries.filter { it.isDestructive })
    }

    @Test
    fun aChipSaysItsTabsNameOrWhatItRuns() {
        assertEquals("zsh", PaneChips.label(WorkspacePane("a", "zsh"), res))
        assertEquals("a shrunk list has no tab names", "Terminal", PaneChips.label(WorkspacePane("b", ""), res))
        assertEquals("Claude Code", PaneChips.label(WorkspacePane("c", "", claude), res))
    }

    @Test
    fun aChipsDotIsItsAgentsState() {
        val tones = panes.map { PaneChips.state(it, NOW_MS, res)?.tone }
        assertEquals("a shell has no dot", listOf(StatusTone.NEEDS_YOU, null, StatusTone.RUNNING), tones)
        val idle = WorkspacePane("i", "i", session("i", AgentState.IDLE))
        val ended = WorkspacePane("e", "e", session("e", AgentState.ENDED))
        val unknown = WorkspacePane("u", "u", session("u", AgentState("thinking")))
        assertEquals(StatusTone.DONE, PaneChips.state(idle, NOW_MS, res)?.tone)
        assertEquals(StatusTone.IDLE, PaneChips.state(ended, NOW_MS, res)?.tone)
        assertNull("a state this app does not know has no dot", PaneChips.state(unknown, NOW_MS, res))
        assertNotNull("the colour is never the only cue", PaneChips.state(panes[0], NOW_MS, res)?.text)
    }

    @Test
    fun leavingSaysWhyUnlessTheUserClosedIt() {
        assertEquals(res.getString(R.string.workspace_closed_on_mac), WorkspaceView.leavingNotice(false, res))
        assertNull(WorkspaceView.leavingNotice(true, res))
        assertEquals(res.getString(R.string.workspace_pane_closed_on_mac), WorkspaceView.paneClosedNotice(res))
    }

    /** `testAgentChipShowsChat` and `testDefaultChipFollowsMacSelection`: a request waits on the agent, so its chip is
     *  the one shown though the Mac has `zsh` selected; with nothing waiting, the Mac's selection. */
    @Test
    fun theDefaultChipIsTheOneThatWaitsElseTheMacsSelection() {
        assertEquals("t-claude", WorkspaceScreenModel.defaultTerminal(workspace, listOf(request)))
        assertEquals("an agent chip is a chat, a shell chip is not", listOf(true, false, true), panes.map { it.isAgent })
        assertEquals("t-zsh", WorkspaceScreenModel.defaultTerminal(workspace, emptyList()))
    }
}
