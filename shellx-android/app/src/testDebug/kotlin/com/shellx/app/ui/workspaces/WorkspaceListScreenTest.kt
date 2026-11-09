package com.shellx.app.ui.workspaces

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.text.AnnotatedString
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.testing.HomeFixtures
import com.shellx.app.testing.HomeFixtures.NOW_MS
import com.shellx.app.testing.HomeFixtures.macbook
import com.shellx.app.testing.HomeFixtures.mini
import com.shellx.app.testing.HomeFixtures.mockup
import com.shellx.app.testing.HomeFixtures.ref
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.home.HomeFocus
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.MachineSession
import com.shellx.core.link.SessionRef
import com.shellx.core.workspaces.WorkspaceRef
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** The home from plain values (HomeFixtures): its cards, rows, headers, folds, toolbar and dialogs. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w400dp-h1600dp")
class WorkspaceListScreenTest {
    @get:Rule val rule = createComposeRule()
    private val context: Context = ApplicationProvider.getApplicationContext()

    private class Calls {
        val opened = mutableListOf<WorkspaceRef>()
        val created = mutableListOf<String>()
        val renamed = mutableListOf<Pair<WorkspaceRef, String>>()
        val closed = mutableListOf<WorkspaceRef>()
        val closedAgents = mutableListOf<SessionRef>()
        val removed = mutableListOf<MachineSession>()
        val openedAgents = mutableListOf<SessionRef>()
        val other = mutableListOf<String>()
        var machines = 0
        var ended = 0
        var alertsDismissed = 0

        val actions = WorkspaceListScreenActions(
            openWorkspace = { opened += it },
            create = { created += it },
            rename = { r, t -> renamed += r to t },
            close = { closed += it },
            closeAgent = { closedAgents += it },
            removeFromPhone = { removed += it },
            openAgent = { openedAgents += it },
            openMachines = { machines++ },
            openOtherSessions = { other += it },
            openEnded = { ended++ },
        )
    }

    private val calls = Calls()

    @Composable
    private fun Screen(
        groups: List<WorkspaceGroup> = listOf(macbook),
        focus: HomeFocus = HomeFocus.EMPTY,
        pending: List<MachinePendingItem> = emptyList(),
        creating: Boolean = false,
        closable: Set<SessionRef> = emptySet(),
        removable: Set<SessionRef> = emptySet(),
        alert: WorkspaceAlert? = null,
    ) {
        ShellXTheme {
            WorkspaceListScreen(
                groups = groups, focus = focus, pending = pending, nowMs = NOW_MS, creating = creating,
                closableAgents = closable, removableAgents = removable, actions = calls.actions, alert = alert,
                onAlertDismissed = { calls.alertsDismissed++ },
            )
        }
    }

    private fun dialogButton(label: String) = rule.onNode(hasText(label) and hasClickAction())

    private fun swipe(tag: String) {
        rule.onNodeWithTag(tag).performTouchInput { swipeLeft() }
        rule.waitForIdle()
    }

    @Test
    fun aWorkspaceCardOpensItsWorkspace() {
        rule.setContent { Screen() }

        rule.onNodeWithTag("workspace.row.ws-relay").performClick()

        assertEquals(listOf(ref("ws-relay")), calls.opened)
    }

    @Test
    fun swipingAWorkspaceAsksBeforeClosingIt() {
        rule.setContent { Screen() }

        swipe("workspace.row.ws-web")
        rule.onNodeWithText("Close “web”?").assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.workspaces_close_confirm)).assertIsDisplayed()
        dialogButton("Cancel").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Close “web”?").assertDoesNotExist()
        assertEquals(emptyList<WorkspaceRef>(), calls.closed)

        swipe("workspace.row.ws-web")
        dialogButton("Close").performClick()
        rule.waitForIdle()
        assertEquals(listOf(ref("ws-web")), calls.closed)
        rule.onNodeWithText("Close “web”?").assertDoesNotExist()
    }

    @Test
    fun renameFromTheLongPressMenu() {
        rule.setContent { Screen() }

        rule.onNodeWithTag("workspace.row.ws-web").performTouchInput { longClick() }
        rule.onNodeWithText("Rename Workspace").performClick()
        rule.waitForIdle()
        val field = rule.onNodeWithTag("workspace.rename.field")
        field.assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString("web")))

        field.performTextReplacement("   ")
        rule.onNodeWithTag("workspace.rename.save").assertIsNotEnabled()

        field.performTextReplacement("  landing  ")
        rule.onNodeWithTag("workspace.rename.save").assertIsEnabled().performClick()
        rule.waitForIdle()
        assertEquals(listOf(ref("ws-web") to "landing"), calls.renamed)
        rule.onNodeWithTag("workspace.rename.field").assertDoesNotExist()
    }

    @Test
    fun aMacThatCannotTakeCommandsOffersNoRowActions() {
        rule.setContent { Screen(groups = listOf(macbook.copy(allowsControl = false))) }

        swipe("workspace.row.ws-web")
        rule.onNodeWithText("Close “web”?").assertDoesNotExist()
        rule.onNodeWithTag("workspace.row.ws-web").performTouchInput { longClick() }
        rule.waitForIdle()
        rule.onNodeWithText("Rename Workspace").assertDoesNotExist()
        rule.onNodeWithText("Close Workspace…").assertDoesNotExist()
        assertEquals(emptyList<WorkspaceRef>(), calls.closed)
    }

    @Test
    fun anAgentCardSwipesToCloseAndAsks() {
        val target = mockup.running[0]
        rule.setContent { Screen(focus = mockup, closable = setOf(target.id)) }

        swipe("home.agent.m1.s2")
        rule.onNodeWithText("Close Viết test SessionSet?").assertIsDisplayed()
        dialogButton("Close").performClick()
        rule.waitForIdle()

        assertEquals(listOf(target.id), calls.closedAgents)
        assertEquals(emptyList<MachineSession>(), calls.removed)
    }

    @Test
    fun aGoneAgentSwipesToRemoveWithoutAQuestion() {
        val target = mockup.running[1]
        rule.setContent { Screen(focus = mockup, removable = setOf(target.id)) }

        swipe("home.agent.m1.s3")

        assertEquals(listOf(target.session), calls.removed)
        rule.onNodeWithText("Close Dọn README?").assertDoesNotExist()
        assertEquals(emptyList<SessionRef>(), calls.closedAgents)
    }

    @Test
    fun theBellSaysHowManyWait() {
        var pending: List<MachinePendingItem> by mutableStateOf(HomeFixtures.pending)
        rule.setContent { Screen(pending = pending) }

        rule.onNodeWithTag("workspaces.bell")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Needs you · 2")))

        pending = emptyList()
        rule.waitForIdle()
        rule.onNodeWithTag("workspaces.bell")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Needs you")))
    }

    @Test
    fun plusPicksTheMacWhenSeveralTakeCommands() {
        val onlineMini = mini.copy(state = MachineLinkState.Online, allowsControl = true)
        var groups by mutableStateOf(listOf(macbook, onlineMini))
        var creating by mutableStateOf(false)
        rule.setContent { Screen(groups = groups, creating = creating) }

        rule.onNodeWithTag("workspaces.create").performClick()
        rule.onNodeWithText("MacBook Pro").assertIsDisplayed()
        rule.onNodeWithText("Mac mini").assertIsDisplayed()
        rule.onNodeWithText("Mac mini").performClick()
        rule.waitForIdle()
        assertEquals(listOf("m2"), calls.created)

        groups = listOf(macbook)
        rule.waitForIdle()
        rule.onNodeWithTag("workspaces.create").performClick()
        assertEquals(listOf("m2", "m1"), calls.created)

        groups = listOf(macbook.copy(allowsControl = false))
        rule.waitForIdle()
        rule.onNodeWithTag("workspaces.create").assertIsNotEnabled()

        groups = listOf(macbook)
        creating = true
        rule.waitForIdle()
        rule.onNodeWithTag("workspaces.create").assertIsNotEnabled()
    }

    @Test
    fun headersFoldsAndRowsOpenTheirPages() {
        rule.setContent { Screen(groups = listOf(macbook.copy(otherSessionCount = 3)), focus = mockup) }

        rule.onNodeWithTag("workspace.group.m1").performClick()
        rule.onNodeWithTag("workspace.otherSessions.m1").performClick()
        rule.onNodeWithTag("home.ended").performClick()
        rule.onNodeWithTag("home.agent.m1.s1").performClick()

        assertEquals(1, calls.machines)
        assertEquals(listOf("m1"), calls.other)
        assertEquals(1, calls.ended)
        assertEquals(listOf(mockup.needsYou[0].id), calls.openedAgents)
    }

    @Test
    fun anAlertIsShownUntilDismissed() {
        rule.setContent { Screen(alert = WorkspaceAlert.OFFLINE) }

        rule.onNodeWithText(context.getString(R.string.workspaces_alert_offline)).assertIsDisplayed()
        dialogButton("OK").performClick()

        assertEquals(1, calls.alertsDismissed)
    }

    @Test
    fun anOpenConfirmationSurvivesRecreation() {
        val restoration = StateRestorationTester(rule)
        restoration.setContent { Screen() }

        swipe("workspace.row.ws-web")
        rule.onNodeWithText("Close “web”?").assertIsDisplayed()

        restoration.emulateSavedInstanceStateRestore()
        rule.onNodeWithText("Close “web”?").assertIsDisplayed()
    }
}
