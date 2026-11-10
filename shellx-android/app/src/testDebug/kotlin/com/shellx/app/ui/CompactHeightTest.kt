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
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.pinch
import androidx.compose.ui.geometry.Offset
import androidx.activity.ComponentActivity
import android.view.View
import android.view.ViewGroup
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import kotlin.math.roundToInt
import java.util.concurrent.TimeUnit
import org.robolectric.shadows.ShadowLooper
import com.shellx.app.demo.DemoFrame
import com.shellx.app.screenshots.StillSpinner
import com.shellx.app.ui.components.LocalSpinner
import com.shellx.app.ui.terminal.LocalTerminalIme
import com.shellx.app.ui.terminal.RecordingIme
import com.shellx.app.ui.terminal.TerminalSurfaceView
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
import com.shellx.core.terminal.TerminalGeometry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
 * above a landscape keyboard (about 170 dp: 393 dp less the status bar and a 200 dp keyboard). A terminal's keyboard
 * comes as the system's inset ([keyboard]), since the terminal's screen follows it.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE) // Real text metrics, so the bars are as tall as on a phone.
@Config(qualifiers = "w851dp-h393dp-land")
class CompactHeightTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

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

    /**
     * The workspace screen under the status bar, its terminal's keyboard not drawn ([keyboard]): a real account's, or
     * the [demo]'s under its banner.
     */
    private fun showWorkspaceTerminal(demo: Boolean = false) = compose.setContent {
        ShellXTheme {
            CompositionLocalProvider(LocalSpinner provides StillSpinner, LocalTerminalIme provides RecordingIme()) {
                Column(Modifier.fillMaxSize()) {
                    Spacer(Modifier.height(STATUS_BAR))
                    Box(Modifier.fillMaxWidth().weight(1f)) {
                        DemoFrame(demo, exit = {}) {
                            WorkspaceView(rig.scope, WorkspaceRef(rig.machineId, "ws-shellx"), open = {}, back = {})
                        }
                    }
                }
            }
        }
    }

    /**
     * Checks the grid the terminal shows, and the one it asked the Mac for once the last size change went out (200 ms
     * later), against [MIN_TERMINAL_COLS] × [MIN_TERMINAL_ROWS]. A pane squeezed to nothing sends no size at all, so the
     * surface's own size counts too.
     */
    private fun assertUsableGrid() {
        idle(600)
        val asked = rig.mac.terminalViewResizes.lastOrNull() ?: rig.mac.terminalViewOpens.last()
        assertTrue("$asked", asked.cols >= MIN_TERMINAL_COLS && asked.rows >= MIN_TERMINAL_ROWS)
        val surface = terminalSurface()
        val padding = TerminalGeometry.PADDING_DP * surface.resources.displayMetrics.density
        val shown = TerminalGeometry.phoneGrid(
            surface.width.toFloat(), surface.height.toFloat(), surface.font.cellWidth, surface.font.cellHeight, padding,
        )
        assertTrue("shown $shown", shown.cols >= MIN_TERMINAL_COLS && shown.rows >= MIN_TERMINAL_ROWS)
    }

    /**
     * The soft keyboard comes up [height] tall (0: it went down, as system Back makes it), as the system tells the
     * window: through its inset, which the pane's imePadding gives to the keyboard. Coming up, the inset grows from a
     * sliver first, as the keyboard's animation makes it: a screen answers the keyboard's first frame, not its last.
     */
    private fun keyboard(height: Dp) {
        if (height > 0.dp) {
            imeInset(4.dp)
            idle(50)
        }
        imeInset(height)
    }

    private fun imeInset(height: Dp) {
        compose.runOnIdle {
            val root = compose.activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0)
            val px = (height.value * root.resources.displayMetrics.density).roundToInt()
            val insets = WindowInsetsCompat.Builder()
                .setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, px))
                .setVisible(WindowInsetsCompat.Type.ime(), px > 0)
                .build()
            ViewCompat.dispatchApplyWindowInsets(root, insets)
        }
        compose.waitForIdle()
    }

    /**
     * A workspace's shell pane with the keyboard up (plan 3G, decision 9): Gboard takes 251 dp of a Pixel 5 held sideways
     * (measured on the API 36 emulator), so while a terminal holds the keyboard the workspace's top bar steps aside, and
     * the key bar and the keyboard still leave a grid to work in; a pinch still zooms it; the bar comes back when the
     * keyboard goes down (system Back), and the key bar goes with it. Real accounts show no demo banner.
     */
    @Test
    fun aWorkspacesTerminalKeepsAUsableGridWithTheKeyBarAndTheKeyboardUp() {
        showWorkspaceTerminal()
        until { tagged("terminal.surface") && rig.mac.terminalViewOpens.isNotEmpty() }
        compose.onNodeWithTag("terminal.surface").performClick()
        until { tagged("terminal.key.escape") }
        keyboard(GBOARD)
        until { !tagged("workspace.title") }
        // The key bar took its row and the top bar gave its own.
        assertUsableGrid()
        compose.onNodeWithTag("terminal.surface").performTouchInput {
            pinch(center - Offset(40f, 0f), center - Offset(160f, 0f), center + Offset(40f, 0f), center + Offset(160f, 0f))
        }
        compose.waitForIdle()
        val viewport = terminalSurface().viewport
        assertTrue("${viewport.scale} after a pinch from ${viewport.fit}", viewport.scale > viewport.fit)
        keyboard(0.dp)
        until { tagged("workspace.title") && !tagged("terminal.key.escape") }
    }

    /**
     * The demo, the first thing a new user tries, with the keyboard up (ledger A-36): the "Demo · Exit" banner steps
     * aside with the workspace's top bar, so its terminal keeps a grid to type in too; both come back when the keyboard
     * goes down.
     */
    @Test
    fun theDemosTerminalKeepsAUsableGridWithTheKeyboardUp() {
        showWorkspaceTerminal(demo = true)
        until { tagged("demo.banner") && tagged("terminal.surface") && rig.mac.terminalViewOpens.isNotEmpty() }
        compose.onNodeWithTag("terminal.surface").performClick()
        until { tagged("terminal.key.escape") }
        keyboard(GBOARD)
        until { !tagged("workspace.title") }
        assertUsableGrid()
        assertFalse("the banner steps aside while the terminal holds the keyboard", tagged("demo.banner"))
        keyboard(0.dp)
        until { tagged("demo.banner") && tagged("workspace.title") && !tagged("terminal.key.escape") }
    }

    /**
     * With "Remove animations" on, the keyboard's inset lands whole in one frame, before the bars above step aside: the
     * demo's terminal is squeezed to nothing for that frame, and Android takes the focus off a View laid out with no
     * size (re-review A m1, seen on the API 36 emulator). The terminal keeps the keyboard, and gets its grid once the
     * bars stepped aside.
     */
    @Test
    fun aKeyboardThatLandsInOneFrameKeepsTheDemosTerminal() {
        showWorkspaceTerminal(demo = true)
        until { tagged("demo.banner") && tagged("terminal.surface") && rig.mac.terminalViewOpens.isNotEmpty() }
        compose.onNodeWithTag("terminal.surface").performClick()
        until { tagged("terminal.key.escape") }
        imeInset(GBOARD)
        until { !tagged("workspace.title") && !tagged("demo.banner") }
        assertTrue(terminalSurface().hasFocus())
        assertUsableGrid()
    }

    /**
     * A hardware keyboard (or a floating one that takes no room) shows no soft keyboard: the terminal keeps the focus and
     * the key bar, and the top bar (back, chips, ＋, ⋮) stays, since nothing takes its room (review D2 I-1).
     */
    @Test
    fun aHardwareKeyboardKeepsTheTopBarInLandscape() {
        showWorkspaceTerminal()
        until { tagged("terminal.surface") && rig.mac.terminalViewOpens.isNotEmpty() }
        compose.onNodeWithTag("terminal.surface").performClick()
        until { tagged("terminal.key.escape") }
        idle(300)
        assertTrue("the top bar stays with no soft keyboard up", tagged("workspace.title"))
        assertTrue(terminalSurface().hasFocus())
        assertTrue(tagged("terminal.key.escape"))
    }

    /** Lets [ms] of the main looper's time pass. */
    private fun idle(ms: Long) {
        repeat((ms / 10).toInt()) {
            compose.waitForIdle()
            ShadowLooper.idleMainLooper(10, TimeUnit.MILLISECONDS)
        }
        compose.waitForIdle()
    }

    private fun terminalSurface(): TerminalSurfaceView {
        fun find(view: View): TerminalSurfaceView? = when (view) {
            is TerminalSurfaceView -> view
            is ViewGroup -> (0 until view.childCount).firstNotNullOfOrNull { find(view.getChildAt(it)) }
            else -> null
        }
        return checkNotNull(find(compose.activity.window.decorView))
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

        /** Gboard as the API 36 emulator draws it on a phone in landscape: 118 dp of 393 are left under the status bar. */
        val GBOARD = 251.dp

        /** About five lines of chat. */
        val MIN_CHAT = 120.dp

        /** A terminal still worth typing into: a shell's prompt and the lines just above it, a full command's width. */
        const val MIN_TERMINAL_ROWS = 4
        const val MIN_TERMINAL_COLS = 80
    }
}
