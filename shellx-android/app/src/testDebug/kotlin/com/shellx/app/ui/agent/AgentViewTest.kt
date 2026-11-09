package com.shellx.app.ui.agent

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.testing.WorkRig
import com.shellx.app.ui.nav.WorkRoutes
import com.shellx.app.ui.pending.PendingFixtures
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.demo.FakeMac
import com.shellx.core.link.SessionRef
import com.shellx.link.core.ChatSendOutcome
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** The agent screen over a signed-in rig (`s1`, Claude Code in `shellx-ios`): sends, the draft across a recreated
 *  screen, Close Agent, Remove from This Phone and the workspace's own "Needs you" page. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w400dp-h1200dp")
class AgentViewTest {
    @get:Rule val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val rig = WorkRig.make()
    private val opened = mutableListOf<String>()
    private var backs = 0
    private var shown by mutableStateOf(true)

    @After
    fun tearDown() = rig.close()

    private fun show() = compose.setContent {
        ShellXTheme {
            if (shown) {
                AgentView(rig.scope, SessionRef(rig.machineId, "s1", "claude", "shellx-ios"), open = { opened += it }, back = { backs++ })
            }
        }
    }

    private fun until(condition: () -> Boolean) = compose.waitUntil(10_000) {
        compose.waitForIdle()
        condition()
    }

    private fun exists(tag: String): Boolean = compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()

    private fun send(text: String) {
        compose.onNodeWithTag("composer.field").performTextInput(text)
        compose.onNodeWithTag("composer.send").performClick()
    }

    @Test
    fun aSentMessageSaysSentForFourSeconds() {
        show()
        until { exists("composer.field") }
        send("chạy test")
        until { rig.mac.sentTexts == listOf(FakeMac.SentText("s1", "chạy test")) }
        until { exists("agent.notice") }
        compose.onNodeWithTag("agent.notice").assertTextEquals(context.getString(R.string.agent_sent))
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(4_100)
        assertTrue("the notice goes after 4 s", !exists("agent.notice"))
        compose.mainClock.autoAdvance = true
    }

    /** RF 3: the draft lives in the screen's holder, so a screen built again keeps it. */
    @Test
    fun theDraftLivesInTheScreenHolder() {
        show()
        until { exists("composer.field") }
        compose.onNodeWithTag("composer.field").performTextInput("đang gõ")
        shown = false
        until { !exists("composer.field") }
        shown = true
        until { exists("composer.field") }
        compose.onNodeWithTag("composer.field").assertTextEquals("đang gõ")
    }

    @Test
    fun closeAgentFromTheMenuReachesTheMac() {
        show()
        until { exists("agent.menu") }
        compose.onNodeWithTag("agent.menu").performClick()
        compose.onNodeWithText(context.getString(R.string.agent_close_menu)).performClick()
        compose.onNodeWithText(context.getString(R.string.agent_close)).performClick()
        until { rig.mac.agentCloses == listOf("s1") }
    }

    @Test
    fun aSessionTheMacLostCanBeRemovedFromThisPhone() {
        rig.mac.setSendOutcome(ChatSendOutcome.NOT_FOUND)
        show()
        until { exists("composer.field") }
        val session = rig.hub.liveSessions.first { it.session.sessionId == "s1" }
        send("x")
        until { exists("agent.removeFromPhone") }
        compose.onNodeWithTag("agent.removeFromPhone").performClick()
        until { backs == 1 }
        assertTrue(rig.scope.goneRemovals.removals.hides(session))
        assertEquals(1, backs)
    }

    @Test
    fun theWorkspacesRequestsOpenTheirOwnPage() {
        rig.mac.addPending(PendingFixtures.permission(workspaceId = "ws-shellx", workspaceTitle = "shellx-ios"))
        show()
        until { exists("home.needsYou") }
        compose.onNodeWithTag("home.needsYou").performClick()
        assertEquals(listOf(WorkRoutes.pendingIn(rig.machineId, "ws-shellx")), opened)
    }
}
