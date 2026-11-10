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
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.screenshots.StillSpinner
import com.shellx.app.testing.WorkRig
import com.shellx.app.ui.components.LocalSpinner
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.workspaces.WorkspaceView
import com.shellx.core.terminal.TerminalViewPhase
import com.shellx.core.workspaces.WorkspaceRef
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.fail
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
    private val rig = WorkRig.make()
    private val ime = RecordingIme()
    private var shown by mutableStateOf(true)

    @After
    fun tearDown() {
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
        return Robolectric.buildActivity(TerminalHostActivity::class.java).setup().also(::focusWindow)
    }

    /** The window has the focus, as the system gives it to the window in front (Robolectric gives none). */
    private fun focusWindow(controller: ActivityController<TerminalHostActivity>) {
        val viewRoot = View::class.java.getMethod("getViewRootImpl").invoke(controller.get().window.decorView)
        viewRoot.javaClass.getMethod("windowFocusChanged", Boolean::class.javaPrimitiveType).invoke(viewRoot, true)
        idle(50)
    }

    private fun idle(ms: Long) = repeat((ms / 10).toInt()) { ShadowLooper.idleMainLooper(10, TimeUnit.MILLISECONDS) }

    private fun until(what: String, condition: () -> Boolean) {
        repeat(1_000) {
            if (condition()) return
            ShadowLooper.idleMainLooper(10, TimeUnit.MILLISECONDS)
        }
        fail("not within 10 s: $what")
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
