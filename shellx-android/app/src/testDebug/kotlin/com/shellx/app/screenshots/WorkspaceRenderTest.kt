package com.shellx.app.screenshots

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import android.view.View
import android.view.ViewGroup
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.WorkRig
import com.shellx.app.ui.components.LocalSpinner
import com.shellx.app.ui.terminal.TerminalPane
import com.shellx.app.ui.terminal.TerminalSurfaceView
import com.shellx.core.terminal.TerminalViewPhase
import com.shellx.core.demo.DemoTerminalScreens
import com.shellx.core.terminal.TerminalViewModel
import com.shellx.link.core.TerminalScreen
import com.shellx.app.testing.eventually
import com.shellx.app.ui.agent.AgentNotice
import com.shellx.app.ui.agent.AgentScreen
import com.shellx.app.ui.workspaces.PaneContent
import com.shellx.app.ui.workspaces.WorkspaceFixtures
import com.shellx.app.ui.workspaces.WorkspaceFixtures.NOW_MS
import com.shellx.app.ui.workspaces.WorkspaceMissingView
import com.shellx.app.ui.workspaces.WorkspaceScreen
import com.shellx.app.ui.workspaces.WorkspaceView
import com.shellx.app.ui.workspaces.WorkspaceWaitingView
import com.shellx.core.agent.AgentThreadModel
import com.shellx.core.composer.ComposerDraft
import com.shellx.core.home.AgentStatusRow
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.MachineSession
import com.shellx.core.link.SessionRef
import com.shellx.core.workspaces.WorkspacePane
import com.shellx.core.workspaces.WorkspaceRef
import com.shellx.core.workspaces.WorkspaceScreenModel
import com.shellx.link.core.AgentState
import com.shellx.link.core.PendingItem
import com.shellx.link.core.PendingKind
import kotlinx.coroutines.launch
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The workspace screen (`WorkspaceRenderTests.swift`, `WorkspaceLiveRenderTests.swift`): the chips over a pane per
 *  chip, its states while the workspace has not come or is not there, and the screen fed by a signed-in rig. */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
class WorkspaceRenderTest {
    /** The embedded agent screen for [session], as `AgentView` feeds it, from fixtures. */
    @Composable
    private fun AgentPane(session: MachineSession, pending: List<MachinePendingItem>) {
        val row = AgentStatusRow.of(session, NOW_MS)
        AgentScreen(
            ref = session.ref, place = "Claude Code · MacBook Pro", row = { row }, gone = false, offline = false, pending = pending,
            showsMachineName = false, entries = WorkspaceFixtures.chat, emptyState = null, machineName = "MacBook Pro",
            older = AgentThreadModel.Older.NONE, loadingOlder = false,
            canStop = session.session.state == AgentState.WORKING || session.session.state == AgentState.NEEDS_INPUT, notice = null,
            draft = ComposerDraft(), onDraftChange = {}, embedded = true,
        )
    }

    @Composable
    private fun Screen(
        selected: String?,
        panes: List<WorkspacePane> = WorkspaceFixtures.panes,
        title: String = "shellx-ios",
        branch: String? = "feat/workspaces",
        canControl: Boolean = true,
        notice: AgentNotice? = null,
        canCreateTerminal: Boolean = false,
        creatingTerminal: Boolean = false,
        canViewTerminals: Boolean = false,
        shownAsTerminal: Set<String> = emptySet(),
        terminal: (@Composable (WorkspacePane, Boolean) -> Unit)? = null,
    ) {
        WorkspaceScreen(
            title = title, branch = branch, panes = panes, selected = selected, nowMs = NOW_MS, canControl = canControl, notice = notice,
            canCreateTerminal = canCreateTerminal, creatingTerminal = creatingTerminal, canViewTerminals = canViewTerminals,
            shownAsTerminal = shownAsTerminal,
        ) { pane, shown ->
            if (pane.id in shownAsTerminal && terminal != null) {
                terminal(pane, shown)
            } else {
                PaneContent(pane, shown, agent = { session ->
                    AgentPane(session, if (session.session.sessionId == "s-claude") listOf(WorkspaceFixtures.request) else emptyList())
                })
            }
        }
    }

    @Test
    fun workspaceAgent() {
        val first = WorkspaceScreenModel.defaultTerminal(WorkspaceFixtures.workspace, listOf(WorkspaceFixtures.request))
        assertEquals("t-claude", first)
        assertRenders("workspace-agent") { Screen(selected = first) }
    }

    @Test
    fun workspaceShell() {
        assertRenders("workspace-shell") { Screen(selected = "t-zsh") }
    }

    @Test
    fun workspaceMacSelection() {
        val first = WorkspaceScreenModel.defaultTerminal(WorkspaceFixtures.workspace, emptyList())
        assertEquals("t-zsh", first)
        assertRenders("workspace-mac-selection") { Screen(selected = first) }
    }

    @Test
    fun workspaceShells() {
        val shells = listOf(WorkspacePane("a", "zsh"), WorkspacePane("b", "npm run dev"))
        assertRenders("workspace-shells") { Screen(selected = "b", panes = shells, title = "relay", branch = "main") }
    }

    @Test
    fun workspaceEmpty() {
        assertRenders("workspace-empty") { Screen(selected = null, panes = emptyList(), title = "notes", branch = null) }
    }

    @Test
    fun workspaceManyChips() {
        val many = (1..9).map { WorkspacePane("t$it", "terminal number $it") }
        assertRenders("workspace-many-chips") {
            Screen(
                selected = "t7", panes = many, title = "a-very-long-workspace-name-that-goes-on-and-on",
                branch = "feature/a-long-branch-name-with-many-parts",
            )
        }
    }

    @Test
    fun workspaceAx3() {
        assertRenders("workspace-ax3") { LargeText { Screen(selected = "t-zsh") } }
    }

    @Test
    fun workspaceNoControl() {
        assertRenders("workspace-no-control") { Screen(selected = "t-zsh", canControl = false) }
    }

    /** The pane shown was closed on the Mac, the next chip shows, and a short line says why. */
    @Test
    fun workspacePaneClosed() {
        assertRenders("workspace-pane-closed") {
            val text = WorkspaceView.paneClosedNotice(LocalContext.current.resources)
            Screen(selected = "t-zsh", notice = remember { AgentNotice(text) })
        }
    }

    /**
     * ＋ after the chips: a new terminal tab (2C). While one is on its way ＋ is dimmed (the iPhone's
     * `workspace-new-terminal-creating`): that frame is drawn first under the same name, compared, then drawn over.
     */
    @Test
    fun workspaceNewTerminal() {
        val dimmed = ShellXSnapshots.capture("workspace-new-terminal") {
            CompositionLocalProvider(LocalSpinner provides StillSpinner) {
                Screen(selected = "t-zsh", canCreateTerminal = true, creatingTerminal = true)
            }
        }
        val plus = assertRenders("workspace-new-terminal") { Screen(selected = "t-zsh", canCreateTerminal = true) }
        val plain = ShellXSnapshots.capture("workspace-shell") {
            CompositionLocalProvider(LocalSpinner provides StillSpinner) { Screen(selected = "t-zsh") }
        }
        fun lightEn(shots: List<Snapshot>) = shots.first { it.theme == "light" && it.language == "en" }.argb
        assertFalse("＋ shows", lightEn(plus).contentEquals(lightEn(plain)))
        assertFalse("＋ is dimmed while a new terminal is on its way", lightEn(dimmed).contentEquals(lightEn(plus)))
        assertFalse("the dimmed ＋ still shows", lightEn(dimmed).contentEquals(lightEn(plain)))
    }

    /** View as Terminal: the agent chip's page is its terminal (2C). */
    @Test
    fun workspaceAgentAsTerminal() {
        val screen = TerminalScreen().apply { apply(DemoTerminalScreens.AGENT.snapshot) }
        assertRenders("workspace-agent-as-terminal") {
            val model = remember { TerminalViewModel.fixed("t-claude", screen) }
            Screen(
                selected = "t-claude", canViewTerminals = true, shownAsTerminal = setOf("t-claude"),
                terminal = { _, shown -> TerminalPane(model, "t-claude", "claude", shown = true) },
            )
        }
    }

    @Test
    fun workspaceLoading() {
        assertRenders("workspace-loading") { WorkspaceWaitingView(back = {}) }
    }

    @Test
    fun workspaceNotFound() {
        assertRenders("workspace-not-found") { WorkspaceMissingView(back = {}) }
    }

    /** `WorkspaceView` itself over a hub connected to a fake Mac, with the real agent screen as the agent chip's pane. A
     *  request waits on the agent: its chip is the one shown, and the bar says so. */
    @Test
    fun workspaceLive() {
        val rig = WorkRig.make()
        try {
            rig.mac.addPending(
                PendingItem(
                    requestId = "p1", kind = PendingKind.PERMISSION, agent = "claude", workspaceId = "ws-shellx",
                    workspaceTitle = "shellx-ios", toolName = "Bash", toolInputPreview = """{"command":"xcodebuild test"}""",
                    createdAtMs = 1_700_000_000_000, modes = listOf("once", "always", "deny"),
                ),
            )
            assertTrue(eventually { rig.hub.pendingItems.size == 1 })
            // The agent's chat is already on the phone, so the render shows it.
            val thread = rig.scope.agentThread(SessionRef(rig.machineId, "s1", "claude", "shellx-ios"))
            val run = rig.hub.scope.launch { thread.run() }
            assertTrue(eventually { thread.thread.entries.isNotEmpty() })
            run.cancel()
            val saved = thread.close()
            assertTrue(eventually { saved.isCompleted })
            assertEquals(listOf(true, false), rig.workspaceModel().panes.map { it.isAgent })
            assertRenders("workspace-live") { WorkspaceView(rig.scope, WorkspaceRef(rig.machineId, "ws-shellx"), open = {}, back = {}) }
        } finally {
            rig.close()
        }
    }

    /**
     * `WorkspaceView` over a fake Mac whose shell is the demo's: the shell chip shows the Mac's terminal, drawn once its
     * first screen came (`WorkspaceLiveRenderTests.swift` settles a second), and the open asked for the phone's grid.
     */
    @Test
    fun workspaceLiveTerminal() {
        val rig = WorkRig.make()
        try {
            rig.mac.setTerminalFixtures(mapOf("t-zsh" to DemoTerminalScreens.SHELL))
            var window: View? = null
            assertRenders("workspace-live-terminal", ready = { window?.let(::liveTerminalIn) == true }) {
                window = LocalView.current
                WorkspaceView(rig.scope, WorkspaceRef(rig.machineId, "ws-shellx"), open = {}, back = {})
            }
            assertTrue("${rig.mac.terminalViewOpens}", rig.mac.terminalViewOpens.any { it.terminalId == "t-zsh" && it.cols >= 20 })
        } finally {
            rig.close()
        }
    }

    /** The window shows `t-zsh`'s surface, its model live with a screen. */
    private fun liveTerminalIn(window: View): Boolean {
        fun find(view: View): TerminalSurfaceView? = when (view) {
            is TerminalSurfaceView -> view
            is ViewGroup -> (0 until view.childCount).firstNotNullOfOrNull { find(view.getChildAt(it)) }
            else -> null
        }
        val surface = find(window.rootView) ?: return false
        return surface.terminalId == "t-zsh" && surface.model.phase == TerminalViewPhase.Live && surface.model.screen.cols > 0
    }

    @Test
    fun workspaceLiveWaiting() {
        val rig = WorkRig.make()
        try {
            assertEquals(WorkspaceScreenModel.Phase.WAITING, rig.workspaceModel("new").phase)
            assertRenders("workspace-live-waiting") { WorkspaceView(rig.scope, WorkspaceRef(rig.machineId, "ws-new"), open = {}, back = {}) }
        } finally {
            rig.close()
        }
    }
}
