package com.shellx.app.ui.workspaces

import android.content.Context
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.workspaces.WorkspaceFixtures.NOW_MS
import com.shellx.core.workspaces.WorkspacePane
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** The workspace screen from plain values over `WorkspaceRenderTests.swift`' panes: chips and pages in step, Close Tab
 *  from a long press and from `⋮`, Close Workspace, a locked pager and an empty workspace. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w400dp-h900dp")
class WorkspaceScreenTest {
    @get:Rule val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private var selected by mutableStateOf<String?>("t-claude")
    private val closeTabs = mutableListOf<String>()
    private var closes = 0
    private var canCloseTab by mutableStateOf(false)

    private fun show(
        panes: List<WorkspacePane> = WorkspaceFixtures.panes,
        canControl: Boolean = true,
        pagingLocked: Boolean = false,
    ) = compose.setContent {
        ShellXTheme {
            WorkspaceScreen(
                title = "shellx-ios", branch = "feat/workspaces", panes = panes, selected = selected, nowMs = NOW_MS,
                canControl = canControl, canCloseTab = canCloseTab, pagingLocked = pagingLocked,
                actions = WorkspaceScreenActions(select = { selected = it }, close = { closes++ }, closeTab = { closeTabs += it }),
            ) { pane, shown ->
                PaneContent(pane, shown, agent = { s -> Text("agent ${s.session.sessionId}", Modifier.testTag("pane.${s.session.sessionId}")) })
            }
        }
    }

    private fun until(condition: () -> Boolean) = compose.waitUntil(10_000) {
        compose.waitForIdle()
        condition()
    }

    private fun text(id: Int, vararg args: Any): String = context.getString(id, *args)

    @Test
    fun tappingAChipShowsItsPage() {
        show()
        compose.onNodeWithTag("workspace.chip.t-zsh").performClick()
        assertEquals("t-zsh", selected)
        until { compose.onAllNodesWithText(text(R.string.terminal_needs_update)).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("workspace.shell.placeholder").assertIsDisplayed()
    }

    @Test
    fun swipingThePagesSelectsTheNextChip() {
        show()
        compose.onNodeWithTag("workspace.pager").performTouchInput { swipeLeft() }
        until { selected == "t-zsh" }
    }

    @Test
    fun aSelectionFromTheModelTurnsThePage() {
        show()
        selected = "t-dev"
        until {
            try {
                compose.onNodeWithTag("pane.s-dev").assertIsDisplayed()
                true
            } catch (e: AssertionError) {
                false
            }
        }
    }

    @Test
    fun aLongPressOffersCloseTabAndAsksFirst() {
        canCloseTab = true
        show()
        compose.onNodeWithTag("workspace.chip.t-zsh").performTouchInput { longClick() }
        compose.onNodeWithText(text(R.string.terminal_close_menu)).performClick()
        compose.onNodeWithText(text(R.string.terminal_close_title, "zsh")).assertExists()
        assertTrue(closeTabs.isEmpty())
        compose.onNodeWithText(text(R.string.terminal_close)).performClick()
        assertEquals(listOf("t-zsh"), closeTabs)

        // A Mac that cannot close tabs: a long press opens no menu.
        canCloseTab = false
        compose.waitForIdle()
        compose.onNodeWithTag("workspace.chip.t-zsh").performTouchInput { longClick() }
        compose.waitForIdle()
        assertTrue(compose.onAllNodesWithText(text(R.string.terminal_close_menu)).fetchSemanticsNodes().isEmpty())
    }

    @Test
    fun theMenuOffersCloseTabForTheChipShown() {
        canCloseTab = true
        show()
        compose.onNodeWithTag("workspace.menu").performClick()
        compose.onNodeWithText(text(R.string.workspace_menu_rename)).assertExists()
        compose.onNodeWithText(text(R.string.workspace_menu_close)).assertExists()
        compose.onNodeWithText(text(R.string.terminal_close_menu)).performClick()
        compose.onNodeWithText(text(R.string.terminal_close_title, "claude")).assertExists()
    }

    @Test
    fun closeWorkspaceAsksFirst() {
        var canControl by mutableStateOf(true)
        compose.setContent {
            ShellXTheme {
                WorkspaceScreen(
                    title = "shellx-ios", branch = "feat/workspaces", panes = WorkspaceFixtures.panes, selected = selected, nowMs = NOW_MS,
                    canControl = canControl, actions = WorkspaceScreenActions(select = { selected = it }, close = { closes++ }),
                ) { pane, shown -> PaneContent(pane, shown, agent = { Text("agent") }) }
            }
        }
        compose.onNodeWithTag("workspace.menu").performClick()
        compose.onNodeWithText(text(R.string.workspace_menu_close)).performClick()
        compose.onNodeWithText(text(R.string.workspaces_close_title, "shellx-ios")).assertExists()
        assertEquals(0, closes)
        compose.onNodeWithText(text(R.string.workspaces_close)).performClick()
        assertEquals(1, closes)
        canControl = false
        compose.waitForIdle()
        compose.onNodeWithTag("workspace.menu").assertIsNotEnabled()
    }

    @Test
    fun aLockedPagerIgnoresSwipes() {
        show(pagingLocked = true)
        compose.onNodeWithTag("workspace.pager").performTouchInput { swipeLeft() }
        compose.waitForIdle()
        assertEquals("t-claude", selected)
    }

    @Test
    fun aWorkspaceWithoutTerminalsSaysSo() {
        selected = null
        show(panes = emptyList())
        compose.onNodeWithTag("workspace.noTerminals").assertIsDisplayed()
    }

    private fun displayed(tag: String): Boolean = try {
        compose.onNodeWithTag(tag).assertIsDisplayed()
        true
    } catch (e: AssertionError) {
        false
    }

    /** The pane shown (the last) is closed on the Mac, and the model picks the first chip, not the page the pager
     *  falls back to: the model's pick shows. */
    @Test
    fun whenThePaneShownLeavesTheModelsPickWins() {
        var panes by mutableStateOf(WorkspaceFixtures.panes)
        selected = "t-dev"
        compose.setContent {
            ShellXTheme {
                WorkspaceScreen(
                    title = "shellx-ios", branch = "feat/workspaces", panes = panes, selected = selected, nowMs = NOW_MS,
                    canControl = true, actions = WorkspaceScreenActions(select = { selected = it }),
                ) { pane, shown ->
                    PaneContent(pane, shown, agent = { s -> Text("agent ${s.session.sessionId}", Modifier.testTag("pane.${s.session.sessionId}")) })
                }
            }
        }
        until { displayed("pane.s-dev") }
        compose.runOnIdle {
            panes = WorkspaceFixtures.panes.take(2)
            selected = "t-claude"
        }
        until { displayed("pane.s-claude") }
        compose.waitForIdle()
        assertEquals("t-claude", selected)
        assertTrue(displayed("pane.s-claude"))
    }

    /** The iPhone's `scrollTo(id, anchor: .center)`: on first show and on each pick, the chip shown sits mid-row. */
    @Test
    fun theChipShownSitsInTheMiddleOfTheRow() {
        val many = (1..24).map { WorkspacePane("t-$it", "terminal $it") }
        selected = "t-8"
        show(panes = many)
        compose.waitForIdle()
        val row = compose.onNodeWithTag("workspace.chips").getUnclippedBoundsInRoot()
        fun offCentre(id: String): Float {
            val chip = compose.onNodeWithTag("workspace.chip.$id").getUnclippedBoundsInRoot()
            return abs(((chip.left + chip.right) - (row.left + row.right)).value / 2)
        }
        assertTrue("first shown (${offCentre("t-8")} dp off)", offCentre("t-8") < 2f)
        selected = "t-14"
        until { offCentre("t-14") < 2f }
    }
}
