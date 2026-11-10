package com.shellx.app.ui.terminal

import android.view.View
import android.view.accessibility.AccessibilityNodeInfo
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.pinch
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.test.swipeUp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.screenshots.StillSpinner
import com.shellx.app.testing.WorkRig
import com.shellx.app.ui.components.LocalSpinner
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.demo.DemoTerminalFixture
import com.shellx.core.demo.DemoTerminalScreens
import com.shellx.core.terminal.TerminalViewModel
import com.shellx.core.terminal.TerminalViewPhase
import com.shellx.link.core.TerminalInputUnit
import com.shellx.link.core.TerminalScreen
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.launch
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.shadows.ShadowLooper

/**
 * A terminal inside a pager (plan 3G Review Focus 4): a vertical swipe scrolls the history (or, on the alternate screen,
 * sends scroll units) and never turns the page, a sideways swipe at fit turns it, a pinch zooms between fit and 2 and
 * locks paging, a zoomed-in grid pans instead of paging, and a page still loading reports its size.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE) // Real text metrics: the grid's cell is the font's.
@Config(qualifiers = "w400dp-h900dp")
class TerminalPaneGestureTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private var locked by mutableStateOf(false)
    private lateinit var pager: PagerState
    private var rig: WorkRig? = null

    @After
    fun tearDown() {
        rig?.close()
    }

    private fun screen(fixture: DemoTerminalFixture) = TerminalScreen().apply { apply(fixture.snapshot) }

    /** Page 0 is the terminal `t-zsh` of [model], page 1 another page; a terminal that asks locks the pager. */
    private fun show(model: TerminalViewModel) = compose.setContent {
        ShellXTheme {
            CompositionLocalProvider(LocalSpinner provides StillSpinner) {
                val state = rememberPagerState { 2 }
                pager = state
                HorizontalPager(state, Modifier.fillMaxSize(), userScrollEnabled = !locked) { page ->
                    if (page == 0) {
                        TerminalPane(model, "t-zsh", "zsh", shown = state.settledPage == 0, locksPaging = { locked = it })
                    } else {
                        Box(Modifier.fillMaxSize().testTag("other"))
                    }
                }
            }
        }
    }

    /** Waits on real time while the main looper's clock moves on 5 ms a round, so the model's delays come due. */
    private fun until(condition: () -> Boolean) = compose.waitUntil(10_000) {
        compose.waitForIdle()
        ShadowLooper.idleMainLooper(5, TimeUnit.MILLISECONDS)
        condition()
    }

    private fun surface(): TerminalSurfaceView {
        fun find(view: View): TerminalSurfaceView? = when (view) {
            is TerminalSurfaceView -> view
            is ViewGroup -> (0 until view.childCount).firstNotNullOfOrNull { find(view.getChildAt(it)) }
            else -> null
        }
        return checkNotNull(find(compose.activity.window.decorView)) { "no terminal surface" }
    }

    private fun swipe(block: androidx.compose.ui.test.TouchInjectionScope.() -> Unit) {
        compose.onNodeWithTag("terminal.surface").performTouchInput(block)
        compose.waitForIdle()
    }

    @Test
    fun aVerticalSwipeOnTheMainScreenScrollsTheHistory() {
        show(TerminalViewModel.fixed("t-zsh", screen(DemoTerminalScreens.SHELL)))
        compose.waitForIdle()
        swipe { swipeDown() }
        val viewport = surface().viewport
        assertTrue("${viewport.scrollY} of ${viewport.maxScrollY}", viewport.scrollY < viewport.maxScrollY)
        assertFalse(viewport.followsBottom)
    }

    @Test
    fun aVerticalSwipeNeverTurnsThePage() { // Review Focus 4
        show(TerminalViewModel.fixed("t-zsh", screen(DemoTerminalScreens.SHELL)))
        compose.waitForIdle()
        swipe { swipeUp() }
        swipe { swipeDown() }
        assertEquals(0, pager.currentPage)
    }

    @Test
    fun aHorizontalSwipeAtFitTurnsThePage() { // Review Focus 4
        show(TerminalViewModel.fixed("t-zsh", screen(DemoTerminalScreens.SHELL)))
        compose.waitForIdle()
        assertEquals("50 columns fit", 0f, surface().viewport.maxScrollX, 0.5f)
        swipe { swipeLeft() }
        until { pager.settledPage == 1 }
    }

    @Test
    fun aPinchZoomsBetweenFitAndTwoAndLocksPaging() {
        show(TerminalViewModel.fixed("t-zsh", screen(DemoTerminalScreens.HTOP)))
        compose.waitForIdle()
        val fit = surface().viewport.fit
        assertTrue("fit $fit", fit < 1f)
        swipe {
            pinch(center - Offset(40f, 0f), center - Offset(240f, 0f), center + Offset(40f, 0f), center + Offset(240f, 0f))
        }
        val zoomed = surface().viewport
        assertTrue("${zoomed.scale} after zooming in from $fit", zoomed.scale > fit && zoomed.scale <= 2f)
        assertTrue("a zoomed grid locks the pages", locked)
        swipe {
            // Both fingers start on the surface, 340 px apart, and end 20 px apart: past fit.
            pinch(center - Offset(170f, 0f), center - Offset(10f, 0f), center + Offset(170f, 0f), center + Offset(10f, 0f))
        }
        assertEquals(fit, surface().viewport.scale, 0.0001f)
        assertFalse("back at fit the pages swipe again", locked)
    }

    @Test
    fun zoomedInAHorizontalSwipePansTheGrid() { // Review Focus 4
        show(TerminalViewModel.fixed("t-zsh", screen(DemoTerminalScreens.HTOP)))
        compose.waitForIdle()
        compose.runOnIdle { surface().pinch(4f, 0f, 0f) }
        compose.waitForIdle()
        assertTrue(locked)
        swipe { swipeLeft() }
        assertTrue("${surface().viewport.scrollX}", surface().viewport.scrollX > 0f)
        assertEquals(0, pager.currentPage)
    }

    /**
     * TalkBack scrolls the history a page at a time (its scroll actions, as a swipe does) and reads the rows then shown;
     * at the bottom only backward is offered, at the top only forward.
     */
    @Test
    fun talkBackScrollsTheHistory() {
        show(TerminalViewModel.fixed("t-zsh", screen(DemoTerminalScreens.SHELL)))
        compose.waitForIdle()
        val surface = surface()
        fun actions() = surface.createAccessibilityNodeInfo().actionList.map { it.id }
        val bottom = surface.createAccessibilityNodeInfo()
        assertTrue(bottom.isScrollable)
        assertTrue(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD in actions())
        assertFalse(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD in actions())
        compose.runOnIdle { assertTrue(surface.performAccessibilityAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD, null)) }
        compose.waitForIdle()
        val viewport = surface.viewport
        assertTrue("${viewport.scrollY} of ${viewport.maxScrollY}", viewport.scrollY < viewport.maxScrollY)
        val older = surface.createAccessibilityNodeInfo()
        assertNotEquals("it reads the older rows", bottom.text?.toString(), older.text?.toString())
        assertTrue(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD in actions())
        compose.runOnIdle {
            while (surface.performAccessibilityAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD, null)) Unit
        }
        assertEquals(0f, surface.viewport.scrollY, 0.5f)
        assertFalse(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD in actions())
        compose.runOnIdle {
            while (surface.performAccessibilityAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD, null)) Unit
        }
        assertTrue(surface.viewport.followsBottom)
        assertEquals(bottom.text?.toString(), surface.createAccessibilityNodeInfo().text?.toString())
    }

    @Test
    fun onTheAlternateScreenAVerticalSwipeSendsScrollUnits() {
        val rig = WorkRig.make().also { rig = it }
        rig.mac.setTerminalFixtures(mapOf("t-zsh" to DemoTerminalScreens.VIM))
        val model = TerminalViewModel(rig.machineId, rig.hub, rig.hub.scope)
        rig.hub.scope.launch { model.run() }
        model.show("t-zsh")
        show(model)
        until { model.phase == TerminalViewPhase.Live }
        swipe { swipeDown() }
        until {
            rig.mac.terminalViewInputs("t-zsh").flatten().any { it is TerminalInputUnit.Scroll && it.lines > 0 }
        }
    }

    @Test
    fun theLoadingPageStillReportsThePhoneGrid() {
        val rig = WorkRig.make().also { rig = it }
        rig.mac.holdTerminalViewOpens()
        val model = TerminalViewModel(rig.machineId, rig.hub, rig.hub.scope)
        rig.hub.scope.launch { model.run() }
        model.show("t-zsh")
        show(model)
        until { rig.mac.terminalViewOpens.size == 1 }
        assertTrue("${rig.mac.terminalViewOpens}", rig.mac.terminalViewOpens.single().cols >= 20)
        compose.onNodeWithTag("terminal.connecting").assertIsDisplayed()
        rig.mac.releaseTerminalViewOpens()
    }
}
