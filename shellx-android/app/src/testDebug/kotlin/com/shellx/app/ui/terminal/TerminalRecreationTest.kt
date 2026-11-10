package com.shellx.app.ui.terminal

import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.screenshots.StillSpinner
import com.shellx.app.testing.WorkRig
import com.shellx.app.ui.components.LocalSpinner
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.workspaces.WorkspaceScreenHolder
import com.shellx.app.ui.workspaces.WorkspaceView
import com.shellx.core.terminal.TerminalViewPhase
import com.shellx.core.workspaces.WorkspaceRef
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.android.controller.ActivityController
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.shadows.ShadowLooper

/** A window that shows [content], made again on a configuration change as MainActivity is. */
class TerminalHostActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { content() }
    }

    companion object {
        var content: @Composable () -> Unit = {}
    }
}

/**
 * The terminal's keyboard across a window made again (a rotation) and across a page that leaves and comes back (a
 * navigation push and Back), with the workspace screen's real models (review D1 M10, re-review B m-2, and the API 36
 * emulator, where a rotation lost the keyboard): a rotation keeps the keyboard and the key bar, as the iPhone does; a
 * page that comes back after a push does not take it again, as the iPhone's does not; a keyboard the user hid stays hidden.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w400dp-h900dp")
class TerminalRecreationTest {
    /** No window of its own: it keeps the windows this test makes in step with Compose, as a compose test's own window. */
    @get:Rule val compose = createEmptyComposeRule()

    private val rig = WorkRig.make()
    private val ime = RecordingIme()
    private var shown by mutableStateOf(true)
    private var lastController: ActivityController<TerminalHostActivity>? = null

    @After
    fun tearDown() {
        // The window goes as an app's does, so no composition of it outlives the test.
        lastController?.pause()?.stop()?.destroy()
        TerminalHostActivity.content = {}
        rig.close()
    }

    /** The workspace screen of `ws-shellx` (its shell `t-zsh` shown), in a page a SaveableStateHolder keeps, as NavHost does. */
    private fun host(): ActivityController<TerminalHostActivity> {
        TerminalHostActivity.content = {
            ShellXTheme {
                CompositionLocalProvider(LocalTerminalIme provides ime, LocalSpinner provides StillSpinner) {
                    val pages = rememberSaveableStateHolder()
                    if (shown) {
                        pages.SaveableStateProvider("workspace") {
                            WorkspaceView(rig.scope, WorkspaceRef(rig.machineId, "ws-shellx"), open = {}, back = {})
                        }
                    } else {
                        Text("another screen")
                    }
                }
            }
        }
        return Robolectric.buildActivity(TerminalHostActivity::class.java).setup().also(::focusWindow).also { lastController = it }
    }

    /** The window has the focus, as the system gives it to the window in front (Robolectric gives none). */
    private fun focusWindow(controller: ActivityController<TerminalHostActivity>) {
        val viewRoot = View::class.java.getMethod("getViewRootImpl").invoke(controller.get().window.decorView)
        viewRoot.javaClass.getMethod("windowFocusChanged", Boolean::class.javaPrimitiveType).invoke(viewRoot, true)
        idle(50)
    }

    private fun idle(ms: Long) = repeat((ms / 10).toInt()) {
        compose.waitForIdle()
        ShadowLooper.idleMainLooper(10, TimeUnit.MILLISECONDS)
    }

    /** Waits up to 10 s of real time (the rig's stores work off the main thread), the main looper's clock moving on. */
    private fun until(what: String, condition: () -> Boolean) {
        try {
            compose.waitUntil(10_000) {
                compose.waitForIdle()
                ShadowLooper.idleMainLooper(10, TimeUnit.MILLISECONDS)
                condition()
            }
        } catch (e: ComposeTimeoutException) {
            fail("not within 10 s: $what (${diagnose()})")
        }
    }

    /** What the window shows, for a failure's message. */
    private fun diagnose(): String {
        val controller = lastController ?: return "no window"
        val activity = controller.get()
        val surface = surfaceIn(controller)
        val holder = runCatching {
            ViewModelProvider(activity)["workspace/${rig.machineId}/ws-shellx", WorkspaceScreenHolder::class.java]
        }.getOrNull()
        fun views(v: View): List<String> =
            listOf("${v.javaClass.simpleName}(${v.width}x${v.height})") +
                if (v is ViewGroup) (0 until v.childCount).flatMap { views(v.getChildAt(it)) } else emptyList()
        return "surface ${surface != null}, phase ${surface?.model?.phase}, machines ${rig.hub.machines.map { it.state }}, " +
            "lifecycle ${activity.lifecycle.currentState}, workspace ${holder?.model?.phase} selected ${holder?.model?.selectedTerminalId} " +
            "shown ${holder?.model?.terminalShown} terminal ${holder?.terminal?.phase}/${holder?.terminal?.terminalId}, " +
            "views ${views(activity.window.decorView).take(12)}"
    }

    private fun surfaceIn(controller: ActivityController<TerminalHostActivity>): TerminalSurfaceView? {
        fun find(view: View): TerminalSurfaceView? = when (view) {
            is TerminalSurfaceView -> view
            is ViewGroup -> (0 until view.childCount).firstNotNullOfOrNull { find(view.getChildAt(it)) }
            else -> null
        }
        return find(controller.get().window.decorView)
    }

    private fun liveSurface(controller: ActivityController<TerminalHostActivity>): TerminalSurfaceView {
        until("a live terminal") { surfaceIn(controller)?.model?.phase == TerminalViewPhase.Live }
        return checkNotNull(surfaceIn(controller))
    }

    /** The surface takes the keyboard as a tap gives it. */
    private fun takeKeyboard(controller: ActivityController<TerminalHostActivity>) {
        val surface = liveSurface(controller)
        surface.focusAndShowKeyboard()
        until("the surface has the keyboard") { surface.hasFocus() }
        // The user rotates later: the screen has seen the focus by then.
        idle(300)
    }

    @Test
    fun aRotationKeepsTheKeyboard() {
        val controller = host()
        takeKeyboard(controller)
        val shows = ime.shows
        controller.recreate()
        focusWindow(controller)
        until("the new surface has the keyboard") { surfaceIn(controller)?.hasFocus() == true }
        until("the keyboard is asked for again") { ime.shows > shows }
    }

    /** The keyboard as the system tells the window: [height] dp of room, shown while it takes some. */
    private fun keyboard(controller: ActivityController<TerminalHostActivity>, height: Int) {
        val root = controller.get().findViewById<ViewGroup>(android.R.id.content).getChildAt(0)
        val px = (height * root.resources.displayMetrics.density).toInt()
        val insets = WindowInsetsCompat.Builder()
            .setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, px))
            .setVisible(WindowInsetsCompat.Type.ime(), px > 0)
            .build()
        ViewCompat.dispatchApplyWindowInsets(root, insets)
    }

    /**
     * A phone rotating with the keyboard up hides the keyboard first, while the window still has the focus, and the
     * window is made again a moment later (API 36 emulator): that is no "the user put the keyboard away", and the
     * keyboard comes back in the new window.
     */
    @Test
    fun aRotationThatHidesTheKeyboardFirstKeepsIt() {
        val controller = host()
        takeKeyboard(controller)
        keyboard(controller, 300)
        idle(100)
        keyboard(controller, 0)
        idle(50)
        controller.recreate()
        focusWindow(controller)
        until("the new surface has the keyboard") { surfaceIn(controller)?.hasFocus() == true }
    }

    /**
     * The API 36 emulator after a rotation: the keyboard the new page asks for before its window has the focus is shown
     * and then hidden by the system as the window takes the focus. The page takes it once the window has the focus, so
     * the keyboard stays.
     */
    @Test
    fun aRotationTakesTheKeyboardBackOnceTheWindowHasTheFocus() {
        val controller = host()
        takeKeyboard(controller)
        controller.recreate()
        liveSurface(controller)
        idle(100)
        keyboard(controller, 300)
        idle(50)
        keyboard(controller, 0)
        focusWindow(controller)
        until("the new surface has the keyboard") { surfaceIn(controller)?.hasFocus() == true }
        idle(800)
        assertTrue("the keyboard stays", surfaceIn(controller)!!.hasFocus())
    }

    /**
     * The API 36 emulator after a rotation: once the page took the keyboard back, the system hid it once more as it
     * settled the new window, and the "keyboard went down" rule gave the focus up. Just after a page took the keyboard
     * back, the keyboard going down asks for it again.
     */
    @Test
    fun aKeyboardTheSystemHidesJustAfterARotationIsAskedForAgain() {
        val controller = host()
        takeKeyboard(controller)
        controller.recreate()
        focusWindow(controller)
        until("the new surface has the keyboard") { surfaceIn(controller)?.hasFocus() == true }
        val shows = ime.shows
        keyboard(controller, 300)
        idle(50)
        keyboard(controller, 0)
        idle(800)
        assertTrue("the keyboard stays with the terminal", surfaceIn(controller)!!.hasFocus())
        assertTrue("the keyboard is asked for again", ime.shows > shows)
    }

    @Test
    fun aRotationDoesNotBringBackAKeyboardTheUserHid() {
        val controller = host()
        takeKeyboard(controller)
        surfaceIn(controller)!!.clearTerminalFocus()
        idle(300)
        controller.recreate()
        focusWindow(controller)
        liveSurface(controller)
        idle(500)
        assertFalse(surfaceIn(controller)!!.hasFocus())
    }

    @Test
    fun aPageThatComesBackAfterAPushDoesNotTakeTheKeyboardAgain() {
        val controller = host()
        takeKeyboard(controller)
        shown = false
        idle(300)
        shown = true
        liveSurface(controller)
        idle(500)
        assertFalse(surfaceIn(controller)!!.hasFocus())
    }
}
