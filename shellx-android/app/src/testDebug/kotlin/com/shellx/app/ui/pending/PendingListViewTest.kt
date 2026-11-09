package com.shellx.app.ui.pending

import android.content.Context
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.isEnabled
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.testing.WorkRig
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.demo.FakeMac
import com.shellx.core.link.MachinePendingItem
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.PermissionMode
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.launch
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** The Needs-you page over a signed-in rig: the cards decide, a workspace's page shows only its cards, the sheets
 *  open and close, and the page goes back once nothing is left. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w400dp-h1600dp")
class PendingListViewTest {
    @get:org.junit.Rule val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val rig = WorkRig.make()
    private var backs = 0
    private var holder: PendingListHolder? = null

    @After
    fun tearDown() = rig.close()

    private fun show(only: ((MachinePendingItem) -> Boolean)? = null) = compose.setContent {
        ShellXTheme {
            // The page's own holder (the same key), so a test can reach the open sheet's model.
            holder = viewModel(key = PendingListView.HOLDER_KEY)
            PendingListView(rig.hub, rig.scope.decisions, rig.scope.sheets, only = only, back = { backs++ })
        }
    }

    private fun until(condition: () -> Boolean) = compose.waitUntil(10_000) {
        compose.waitForIdle()
        condition()
    }

    private fun cards(): Int = compose.onAllNodesWithTag("pending.card").fetchSemanticsNodes().size

    private fun shown(text: String): Boolean = compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    private fun enabled(tag: String): Boolean = compose.onAllNodes(hasTestTag(tag) and isEnabled()).fetchSemanticsNodes().isNotEmpty()

    private fun pending(count: Int) = until { rig.hub.pendingItems.size == count && rig.hub.pendingItems.all { it.actionable } }

    private fun allowP1() {
        rig.mac.addPending(PendingFixtures.permission(workspaceId = "ws-shellx", workspaceTitle = "shellx-ios"))
        pending(1)
        show()
        until { cards() == 1 && enabled("pending.allow") }
        compose.onNodeWithTag("pending.allow").performClick()
    }

    @Test
    fun allowDecidesAndTheCardGoes() {
        allowP1()
        until { rig.mac.decisions == listOf(FakeMac.Decision("p1", LinkDecision.Permission(PermissionMode.ONCE))) }
        until { cards() == 0 }
    }

    @Test
    fun aWorkspacesPageShowsOnlyItsCards() {
        rig.mac.addPending(PendingFixtures.permission(workspaceId = "ws-shellx", workspaceTitle = "shellx-ios"))
        rig.mac.addPending(PendingFixtures.permission(requestId = "p2", workspaceId = "ws-web", workspaceTitle = "web"))
        pending(2)
        show(only = { it.isIn(rig.machineId, "ws-shellx") })
        until { cards() == 1 }
        compose.waitForIdle()
        assertEquals(1, cards())
    }

    @Test
    fun theLastCardHandledSaysSoThenGoesBack() {
        allowP1()
        until { shown(context.getString(R.string.pending_list_empty)) }
        assertEquals("the page waits before it goes", 0, backs)
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(800)
        assertEquals(1, backs)
        assertEquals(700.milliseconds, PendingListView.LEAVE_DELAY)
        compose.mainClock.autoAdvance = true
    }

    @Test
    fun answerOpensTheQuestionSheetAndShowMoreTheFullText() {
        rig.mac.addPending(PendingFixtures.question(workspaceId = "ws-shellx"))
        rig.mac.addPending(
            PendingFixtures.permission(
                preview = """{"command":"git add .\ngit commit -m wip\ngit push\ngh pr create"}""", requestId = "p4",
                workspaceId = "ws-shellx", workspaceTitle = "shellx-ios",
            ),
        )
        pending(2)
        show()
        until { cards() == 2 && enabled("pending.open") }
        compose.onNodeWithTag("pending.open").performClick()
        until { shown("Which database should the sync service use?") && compose.onAllNodesWithTag("pending.close").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("pending.close").performClick()
        until { holder?.route == null && compose.onAllNodesWithTag("pending.close").fetchSemanticsNodes().isEmpty() }

        until { compose.onAllNodesWithTag("pending.showMore").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("pending.showMore").performClick()
        until { holder?.route?.kind == PendingRoute.Kind.FULL_TEXT && compose.onAllNodesWithTag("pending.close").fetchSemanticsNodes().isNotEmpty() }
        until { shown("Bash") || shown(context.getString(R.string.pending_full_text_title)) }
    }

    @Test
    fun aSheetClosesOnceItsDecisionIsDone() {
        rig.mac.addPending(PendingFixtures.question(workspaceId = "ws-shellx"))
        pending(1)
        show()
        until { cards() == 1 && enabled("pending.open") }
        compose.onNodeWithTag("pending.open").performClick()
        until { shown("Which database should the sync service use?") }
        val route = requireNotNull(holder?.route)
        rig.hub.scope.launch { route.model.send(LinkDecision.Question(listOf("Postgres"))) }
        until { holder?.route == null }
        until { !shown("Which database should the sync service use?") && cards() == 0 }
    }

    /** RF 3 through the real host: the sheet lives in a bottom sheet's own window; its page and typed answer survive a
     *  rebuilt screen. */
    @Test
    fun anOpenSheetKeepsItsPageAndTypedAnswerWhenTheScreenIsRebuilt() {
        rig.mac.addPending(PendingFixtures.question(workspaceId = "ws-shellx"))
        pending(1)
        val restoration = StateRestorationTester(compose)
        restoration.setContent {
            ShellXTheme {
                holder = viewModel(key = PendingListView.HOLDER_KEY)
                PendingListView(rig.hub, rig.scope.decisions, rig.scope.sheets, only = null, back = { backs++ })
            }
        }
        until { cards() == 1 && enabled("pending.open") }
        compose.onNodeWithTag("pending.open").performClick()
        until { compose.onAllNodesWithTag("pending.option").fetchSemanticsNodes().size == 2 }
        compose.onAllNodesWithTag("pending.option")[0].performClick()
        compose.onNodeWithTag("pending.next").performClick()
        compose.onNodeWithTag("pending.other").performClick()
        compose.onNodeWithTag("pending.otherField").performTextInput("Chỉ lint")

        restoration.emulateSavedInstanceStateRestore()
        until { shown(context.getString(R.string.pending_question_page, 2, 2)) }
        compose.onNodeWithTag("pending.otherField").assertTextEquals("Chỉ lint")
    }
}
