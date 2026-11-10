package com.shellx.app.ui.home

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.testing.HomeFixtures
import com.shellx.app.testing.HomeFixtures.NOW_MS
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.home.FocusItem
import com.shellx.core.link.SessionRef
import com.shellx.link.core.AgentState
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** The session lists from plain values: Ended's trash and swipe, a gone session's swipe, the empty line, a card's tap. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w400dp-h1600dp")
class SessionListScreenTest {
    @get:Rule val rule = createComposeRule()
    private val context: Context = ApplicationProvider.getApplicationContext()

    private val e1 = HomeFixtures.item(HomeFixtures.session("e1", "Release 1.5.1", AgentState.ENDED, 120.0, workspace = "web"))
    private val e2 = HomeFixtures.item(HomeFixtures.session("e2", "Fix the flaky test", AgentState.ENDED, 240.0))
    private val s1 = HomeFixtures.item(HomeFixtures.session("s1", "Over SSH", AgentState.WORKING, 4.0, workspace = ""))
    private val s2 = HomeFixtures.item(HomeFixtures.session("s2", "A ghost", AgentState.WORKING, 3120.0, workspace = ""))

    private val opened = mutableListOf<SessionRef>()
    private val removed = mutableListOf<FocusItem>()
    private val removedGone = mutableListOf<FocusItem>()

    @Composable
    private fun Ended(items: List<FocusItem>) {
        ShellXTheme {
            SessionListScreen(
                title = context.getString(R.string.ended_title), header = null, items = items, kind = { FocusKind.ENDED },
                nowMs = NOW_MS, showsMachineName = false, empty = R.string.ended_empty, openAgent = { opened += it },
                back = {}, remove = { removed += it },
            )
        }
    }

    @Composable
    private fun Other(items: List<FocusItem>, removableGone: Set<SessionRef>) {
        ShellXTheme {
            SessionListScreen(
                title = context.getString(R.string.workspaces_other_title), header = "MacBook Pro", items = items,
                kind = { FocusKind.RUNNING }, nowMs = NOW_MS, showsMachineName = false, empty = R.string.workspaces_other_empty,
                openAgent = { opened += it }, back = {}, removableGone = removableGone, removeGone = { removedGone += it },
            )
        }
    }

    private fun swipe(tag: String) {
        rule.onNodeWithTag(tag).performTouchInput { swipeLeft() }
        rule.waitForIdle()
    }

    @Test
    fun theTrashAndTheSwipeTakeAnEndedCardOff() {
        rule.setContent { Ended(listOf(e1, e2)) }

        rule.onNodeWithTag("sessionList.remove.e1").performClick()
        rule.waitForIdle()
        assertEquals(listOf(e1), removed)

        swipe("sessionList.row.e2")
        assertEquals(listOf(e1, e2), removed)
        assertEquals("neither opened its agent", emptyList<SessionRef>(), opened)
    }

    @Test
    fun aGoneSessionSwipesToRemoveFromThisPhone() {
        rule.setContent { Other(listOf(s1, s2), removableGone = setOf(s2.id)) }

        swipe("sessionList.row.s2")
        assertEquals(listOf(s2), removedGone)

        swipe("sessionList.row.s1")
        assertEquals("a live session has no swipe", listOf(s2), removedGone)
        rule.onNodeWithTag("sessionList.remove.s1").assertDoesNotExist()
    }

    @Test
    fun anEmptyListSaysSo() {
        rule.setContent { Ended(emptyList()) }

        rule.onNodeWithTag("sessionList.empty").assertIsDisplayed()
            .assertTextEquals(context.getString(R.string.ended_empty))
    }

    @Test
    fun aCardOpensItsAgent() {
        rule.setContent { Other(listOf(s1, s2), removableGone = emptySet()) }

        rule.onNodeWithTag("sessionList.row.s1").performClick()
        rule.waitForIdle()

        assertEquals(listOf(s1.id), opened)
    }
}
