package com.shellx.app.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.VoiceRig
import com.shellx.app.testing.WorkRig
import com.shellx.app.ui.agent.AgentView
import com.shellx.app.ui.pending.PendingFixtures
import com.shellx.app.ui.pending.PendingSheetState
import com.shellx.app.ui.pending.PlanReviewSheet
import com.shellx.app.ui.pending.QuestionAnswerSheet
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.workspaces.WorkspaceView
import com.shellx.app.voice.LocalVoice
import com.shellx.core.workspaces.WorkspaceRef
import com.shellx.core.link.SessionRef
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A phone in landscape (851 × 393 dp, the Pixel 5 turned): the work screens keep a usable chat, and both pending sheets
 * keep their text field in view with the keyboard up (Task 13's landscape finding, final review).
 *
 * Robolectric draws no system bars and shows no keyboard, so the room they take is left out of the content here: the
 * status bar (24 dp), the gesture bar (24 dp) and the demo banner (48 dp) for the screens; for the sheets, the room left
 * above a landscape keyboard (about 170 dp: 393 dp less the status bar and a 200 dp keyboard).
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE) // Real text metrics, so the bars are as tall as on a phone.
@Config(qualifiers = "w851dp-h393dp-land")
class CompactHeightTest {
    @get:Rule val compose = createComposeRule()

    private val rig = WorkRig.make()

    @After
    fun tearDown() = rig.close()

    private fun until(condition: () -> Boolean) = compose.waitUntil(10_000) {
        compose.waitForIdle()
        condition()
    }

    private fun tagged(tag: String): Boolean = compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()

    /** The screen between a status bar, the demo banner and a gesture bar. */
    @Composable
    private fun BetweenTheBars(content: @Composable () -> Unit) {
        Column(Modifier.fillMaxSize()) {
            Spacer(Modifier.height(STATUS_BAR + DEMO_BANNER))
            Box(Modifier.weight(1f).fillMaxWidth()) { content() }
            Spacer(Modifier.height(GESTURE_BAR))
        }
    }

    private fun chatHeight(): Dp = compose.onNodeWithTag("agent.chat").getBoundsInRoot().let { it.bottom - it.top }

    private fun addPending() = rig.mac.addPending(PendingFixtures.permission(workspaceId = "ws-shellx", workspaceTitle = "shellx-ios"))

    @Test
    fun aWorkspacesAgentPaneKeepsAUsableChat() {
        addPending()
        compose.setContent {
            ShellXTheme {
                BetweenTheBars { WorkspaceView(rig.scope, WorkspaceRef(rig.machineId, "ws-shellx"), open = {}, back = {}) }
            }
        }
        until { tagged("workspace.chip.t-claude") }
        compose.onNodeWithTag("workspace.chip.t-claude").performClick()
        until { tagged("agent.chat") && tagged("home.needsYou") }
        val height = chatHeight()
        assertTrue("the chat is $height tall", height >= MIN_CHAT)
    }

    @Test
    fun anAgentsScreenKeepsAUsableChat() {
        addPending()
        compose.setContent {
            ShellXTheme {
                BetweenTheBars {
                    AgentView(rig.scope, SessionRef(rig.machineId, "s1", "claude", "shellx-ios"), open = {}, back = {})
                }
            }
        }
        until { tagged("agent.chat") && tagged("home.needsYou") }
        val height = chatHeight()
        assertTrue("the chat is $height tall", height >= MIN_CHAT)
    }

    /** The field's part in view, and its whole height. */
    private fun shownOf(tag: String): Pair<Dp, Dp> {
        val node = compose.onNodeWithTag(tag)
        val shown = node.getBoundsInRoot().let { it.bottom - it.top }
        val whole = node.getUnclippedBoundsInRoot().let { it.bottom - it.top }
        return shown to whole
    }

    /** The sheet's button [tag] can be scrolled into view, whole (the keyboard is still up). */
    private fun assertReachable(tag: String) {
        try {
            compose.onNodeWithTag(tag).performScrollTo()
        } catch (e: AssertionError) {
            // Not in a scrolling part: it can be seen only where it already is.
        }
        compose.waitForIdle()
        val (shown, whole) = shownOf(tag)
        assertTrue("$tag can be reached ($shown of $whole)", shown >= 40.dp)
        assertEquals("$tag shows whole ($shown of $whole)", whole.value, shown.value, 0.5f)
    }

    /** The room above a landscape keyboard, as the bottom sheet gives it to its content. */
    @Composable
    private fun AboveTheKeyboard(content: @Composable () -> Unit) {
        CompositionLocalProvider(LocalVoice provides voice.env) {
            Box(Modifier.fillMaxWidth().height(ABOVE_KEYBOARD).testTag("sheet")) { content() }
        }
    }

    private val voice = VoiceRig.make()

    @Test
    fun theQuestionSheetsOtherFieldStaysInViewWithTheKeyboardUp() {
        val item = PendingFixtures.mac(PendingFixtures.question())
        compose.setContent {
            ShellXTheme {
                AboveTheKeyboard { QuestionAnswerSheet(item, PendingSheetState(), send = {}, close = {}, typing = setOf("db")) }
            }
        }
        compose.onNodeWithTag("pending.otherField").performSemanticsAction(SemanticsActions.RequestFocus)
        compose.waitForIdle()
        val (shown, whole) = shownOf("pending.otherField")
        assertEquals("the Other… field shows whole ($shown of $whole)", whole.value, shown.value, 0.5f)
        assertReachable("pending.next")
    }

    @Test
    fun thePlanSheetsReviseFieldStaysInViewWithTheKeyboardUp() {
        val item = PendingFixtures.mac(PendingFixtures.plan())
        compose.setContent {
            ShellXTheme {
                AboveTheKeyboard { PlanReviewSheet(item, PendingSheetState(), send = {}, close = {}, revising = true, feedback = "Thêm test cho QR") }
            }
        }
        compose.onNodeWithTag("pending.feedback").performSemanticsAction(SemanticsActions.RequestFocus)
        compose.waitForIdle()
        val (shown, whole) = shownOf("pending.feedback")
        assertEquals("the Revise field shows whole ($shown of $whole)", whole.value, shown.value, 0.5f)
        assertReachable("pending.sendFeedback")
    }

    private companion object {
        val STATUS_BAR = 24.dp
        val GESTURE_BAR = 24.dp
        val DEMO_BANNER = 48.dp

        /** 393 dp less the status bar and a 200 dp landscape keyboard. */
        val ABOVE_KEYBOARD = 170.dp

        /** About five lines of chat. */
        val MIN_CHAT = 120.dp
    }
}
