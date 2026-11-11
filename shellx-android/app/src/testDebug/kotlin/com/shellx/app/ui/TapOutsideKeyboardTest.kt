package com.shellx.app.ui

import android.content.Context
import android.view.View
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.SoftwareKeyboardController
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.assertIsNotFocused
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.navigation.NavHostController
import androidx.navigation.compose.rememberNavController
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.screenshots.StillSpinner
import com.shellx.app.testing.TestClock
import com.shellx.app.testing.mainComposition
import com.shellx.app.ui.components.LocalSpinner
import com.shellx.app.ui.components.LocalTerminalKeyboard
import com.shellx.app.ui.components.TerminalKeyboard
import com.shellx.app.ui.nav.Routes
import com.shellx.app.ui.nav.ShellXNavHost
import com.shellx.app.ui.nav.WorkRoutes
import com.shellx.app.ui.nav.bottomRoute
import com.shellx.app.ui.terminal.LocalTerminalIme
import com.shellx.app.ui.terminal.RecordingIme
import com.shellx.app.ui.terminal.TerminalSurfaceView
import com.shellx.app.ui.theme.AppAppearance
import com.shellx.app.ui.theme.ShellXAppTheme
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.workspaces.WorkspaceRenameSheet
import com.shellx.core.demo.FakeMac
import com.shellx.core.link.SessionRef
import com.shellx.core.workspaces.WorkspaceRef
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.ChatEntry
import com.shellx.link.core.ChatEntryKind
import com.shellx.link.core.ChatEntryRole
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.shadows.ShadowLooper

/**
 * A tap outside the text input puts the keyboard down (phone check 2026-11-11, follow-up 1), through the window's
 * NavHost as the app wires it, over a signed-in account on the main thread: the agent's composer, the terminal's
 * keyboard (the surface's own hide, as its key bar's hide key, never one the page answers by asking again) and a sheet's
 * field. Taps a control takes (the field itself, the terminal grid, a key bar key, a chip) keep the keyboard.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE) // Real text metrics: the terminal's grid is the font's.
@Config(qualifiers = "w400dp-h900dp")
class TapOutsideKeyboardTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val ime = RecordingIme()
    private val keyboard = CountingKeyboard()
    private val windowKeyboard = TerminalKeyboard()
    private lateinit var nav: NavHostController
    private val mac = macWithAWorkspace()

    @After
    fun tearDown() {
        appScope.cancel()
    }

    /** The screens' keyboard controller: counts what they ask of it. */
    private class CountingKeyboard : SoftwareKeyboardController {
        var shows = 0
        var hides = 0

        override fun show() {
            shows += 1
        }

        override fun hide() {
            hides += 1
        }
    }

    /** `ws-shellx` (Claude Code `s1`, working, and the shell `t-zsh`, selected), as WorkRig's Mac has it. */
    private fun macWithAWorkspace(): FakeMac = FakeMac("MacBook Pro", appScope).apply {
        setWorkspaces(
            listOf(
                LinkWorkspace(
                    "ws-shellx", "shellx-ios", 0, directory = "~/shellx/shellx-ios", branch = "feat/workspaces",
                    terminals = listOf(
                        LinkTerminal("t-claude", "claude", 0, selected = false, sessionId = "s1"),
                        LinkTerminal("t-zsh", "zsh", 1, selected = true),
                    ),
                ),
            ),
        )
        val now = TestClock.nowMs()
        upsertSession(
            AgentSession(
                "s1", "claude", "ws-shellx", "shellx-ios", state = AgentState.WORKING, stateSinceMs = now - 240_000,
                lastActivityMs = now,
            ),
        )
        setHistory(
            "s1",
            listOf(
                ChatEntry("e1", 1, 1, ChatEntryRole.USER, ChatEntryKind.PROSE, "thêm danh sách workspace vào màn chính", tsMs = 1_700_000_000_000),
                ChatEntry("e2", 1, 2, ChatEntryRole.AGENT, ChatEntryKind.PROSE, "Mình sẽ thêm **WorkspaceList** và sửa màn chính.", tsMs = 1_700_000_001_000),
            ),
        )
    }

    /** The window's NavHost over the signed-in account with [mac], on its home, then [route] above it. */
    private fun open(route: String) {
        val t = mainComposition(folder.root, macs = listOf(mac), appScope = appScope)
        compose.setContent {
            ShellXAppTheme(AppAppearance.SYSTEM) {
                CompositionLocalProvider(
                    LocalTerminalIme provides ime,
                    LocalSoftwareKeyboardController provides keyboard,
                    LocalTerminalKeyboard provides windowKeyboard,
                    LocalSpinner provides StillSpinner,
                ) {
                    nav = rememberNavController()
                    ShellXNavHost(t.composition, nav)
                }
            }
        }
        compose.runOnUiThread { t.composition.lifecycle.onStart() }
        until { bottomRoute(nav) == Routes.HOME }
        compose.runOnIdle { nav.navigate(route) { launchSingleTop = true } }
    }

    /** Waits on real time while the main looper's clock moves on 5 ms a round, so the models' delays come due. */
    private fun until(condition: () -> Boolean) = compose.waitUntil(10_000) {
        compose.waitForIdle()
        ShadowLooper.idleMainLooper(5, TimeUnit.MILLISECONDS)
        condition()
    }

    /** Lets [ms] of the main looper's time pass. */
    private fun idle(ms: Long) {
        repeat((ms / 10).toInt()) {
            compose.waitForIdle()
            ShadowLooper.idleMainLooper(10, TimeUnit.MILLISECONDS)
        }
        compose.waitForIdle()
    }

    private fun tagged(tag: String): Boolean = compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()

    private fun focused(tag: String): Boolean =
        compose.onAllNodesWithTag(tag).fetchSemanticsNodes().any { it.config.getOrNull(SemanticsProperties.Focused) == true }

    private fun surface(): TerminalSurfaceView {
        fun find(view: View): TerminalSurfaceView? = when (view) {
            is TerminalSurfaceView -> view
            is ViewGroup -> (0 until view.childCount).firstNotNullOfOrNull { find(view.getChildAt(it)) }
            else -> null
        }
        return checkNotNull(find(compose.activity.window.decorView))
    }

    /** The soft keyboard as the system tells the window: [height] dp of room (0: it went down). */
    private fun keyboard(height: Int) {
        compose.runOnIdle {
            val root = compose.activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0)
            val px = (height * root.resources.displayMetrics.density).toInt()
            val insets = WindowInsetsCompat.Builder()
                .setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, px))
                .setVisible(WindowInsetsCompat.Type.ime(), px > 0)
                .build()
            ViewCompat.dispatchApplyWindowInsets(root, insets)
        }
        idle(50)
    }

    /** The composer has the keyboard; a tap on the message list, above its entries, puts it down. A tap in the field keeps it. */
    @Test
    fun aTapOnTheChatHidesTheComposersKeyboard() {
        open(WorkRoutes.agent(SessionRef(mac.machine.machineId, "s1", "claude", "shellx-ios")))
        until { tagged("composer.field") && tagged("agent.chat") }
        compose.onNodeWithTag("composer.field").performClick()
        compose.onNodeWithTag("composer.field").assertIsFocused()
        val hides = keyboard.hides

        // The chat's entries sit at its bottom: nothing at its top takes a tap.
        compose.onNodeWithTag("agent.chat").performTouchInput { click(Offset(centerX, 20f)) }
        until { keyboard.hides == hides + 1 }
        compose.onNodeWithTag("composer.field").assertIsNotFocused()

        compose.onNodeWithTag("composer.field").performClick()
        compose.onNodeWithTag("composer.field").assertIsFocused()
        compose.onNodeWithTag("composer.field").performClick()
        idle(300)
        compose.onNodeWithTag("composer.field").assertIsFocused()
        assertEquals("a tap in the field hides nothing", hides + 1, keyboard.hides)
    }

    /**
     * The terminal holds the keyboard (3G contracts §28): a tap on the grid, a key bar key or the chip shown keeps it; a
     * tap on the title puts it down the surface's own way, as the key bar's hide key does, with the key bar, and the
     * keyboard then going down is the user's doing, not the system's, so the page asks for nothing.
     */
    @Test
    fun aTapOnTheWorkspacesTitleHidesTheTerminalsKeyboardAsItsOwnHideKeyDoes() {
        open(WorkRoutes.workspace(WorkspaceRef(mac.machine.machineId, "ws-shellx")))
        until { tagged("terminal.surface") && mac.terminalViewOpens.isNotEmpty() }
        compose.onNodeWithTag("terminal.surface").performClick()
        until { ime.shows == 1 && surface().hasFocus() && tagged("terminal.key.escape") }
        keyboard(300)
        until { windowKeyboard.held }

        compose.onNodeWithTag("terminal.surface").performClick()
        compose.onNodeWithTag("terminal.key.escape").performClick()
        compose.onNodeWithTag("workspace.chip.t-zsh").performClick()
        idle(300)
        assertTrue("the grid, a key and the chip shown keep the keyboard", surface().hasFocus())
        assertEquals(0, ime.hides)
        assertTrue(windowKeyboard.held)
        val shows = ime.shows

        compose.onNodeWithTag("workspace.title").performClick()
        until { !surface().hasFocus() && !tagged("terminal.key.escape") }
        assertEquals("the surface hid its keyboard itself", 1, ime.hides)
        assertFalse(windowKeyboard.held)

        keyboard(0)
        idle(300)
        assertEquals("the page asked for the keyboard again", shows, ime.shows)
        assertFalse(surface().hasFocus())
    }

    /** The rename sheet's field has the focus when shown; a tap on the sheet's own title puts it down. */
    @Test
    fun aTapOnTheRenameSheetsOwnAreaPutsTheFieldsFocusDown() {
        compose.setContent { ShellXTheme { WorkspaceRenameSheet(current = "shellx-ios", save = {}, cancel = {}) } }
        until { focused("workspace.rename.field") }
        compose.onNodeWithText(context.getString(R.string.workspaces_rename_title)).performClick()
        until { !focused("workspace.rename.field") }
    }
}
