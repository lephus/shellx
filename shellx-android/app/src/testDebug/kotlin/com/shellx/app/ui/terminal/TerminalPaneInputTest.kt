package com.shellx.app.ui.terminal

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.view.View
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo
import com.shellx.link.core.TerminalCursor
import com.shellx.link.core.TerminalFrameHead
import com.shellx.link.core.TerminalFrameKind
import com.shellx.link.core.TerminalGridFrame
import com.shellx.link.core.TerminalLine
import com.shellx.link.core.TerminalRun
import org.junit.Assert.assertNull
import org.robolectric.Shadows.shadowOf
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.screenshots.StillSpinner
import com.shellx.app.testing.WorkRig
import com.shellx.app.ui.components.LocalSpinner
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.workspaces.WorkspaceView
import com.shellx.core.workspaces.WorkspaceRef
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.core.demo.DemoTerminalScreens
import com.shellx.core.terminal.TerminalInputBatcher
import com.shellx.core.terminal.TerminalUnavailableReason
import com.shellx.core.terminal.TerminalViewModel
import com.shellx.core.terminal.TerminalViewPhase
import com.shellx.link.core.TerminalInputUnit
import com.shellx.link.core.TerminalInputUnit.Key
import com.shellx.link.core.TerminalInputUnit.Paste
import com.shellx.link.core.TerminalInputUnit.Text
import com.shellx.link.core.TerminalKey
import com.shellx.link.core.TerminalModifier
import com.shellx.link.core.TerminalScreen
import com.shellx.link.core.TerminalViewEndReason
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.shadows.ShadowLooper

/**
 * The terminal page live in a window, against the fake Mac's `t-zsh` (plan 3G Task 13 and `TerminalPaneTests.swift`):
 * a tap takes the keyboard and shows the key bar, the key bar drives the model, a long press offers Paste; and who
 * holds the keyboard, when the key bar shows, and which terminal the keys reach.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE) // Real text metrics: the grid's cell is the font's.
@Config(qualifiers = "w400dp-h900dp")
class TerminalPaneInputTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val rig = WorkRig.make()
    private val ime = RecordingIme()
    private val model = TerminalViewModel(rig.machineId, rig.hub, rig.hub.scope)
    private var run: Job? = null

    @After
    fun tearDown() {
        run?.cancel()
        rig.close()
    }

    /** The model runs as the workspace screen runs it, and shows `t-zsh`. */
    private fun start() {
        run = rig.hub.scope.launch { model.run() }
        model.show("t-zsh")
    }

    private fun show(content: @Composable () -> Unit) = compose.setContent {
        ShellXTheme {
            CompositionLocalProvider(LocalTerminalIme provides ime, LocalSpinner provides StillSpinner) { content() }
        }
    }

    /** `t-zsh`'s page, the one shown, live. */
    private fun livePane() {
        start()
        show { TerminalPane(model, "t-zsh", "zsh", shown = true) }
        until { model.phase == TerminalViewPhase.Live }
    }

    /** Waits on real time while the main looper's clock moves on 5 ms a round, so the model's delays come due. */
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

    private fun surfaces(): List<TerminalSurfaceView> {
        fun find(view: View): List<TerminalSurfaceView> = when (view) {
            is TerminalSurfaceView -> listOf(view)
            is ViewGroup -> (0 until view.childCount).flatMap { find(view.getChildAt(it)) }
            else -> emptyList()
        }
        return find(compose.activity.window.decorView)
    }

    private fun surface(): TerminalSurfaceView = surfaces().single()

    private fun InputConnection(surface: TerminalSurfaceView): InputConnection =
        checkNotNull(surface.onCreateInputConnection(EditorInfo()))

    private fun inputs(id: String = "t-zsh") = rig.mac.terminalViewInputs(id)

    private fun clipboard(text: String?) {
        val manager = context.getSystemService(ClipboardManager::class.java)
        if (text == null) manager.clearPrimaryClip() else manager.setPrimaryClip(ClipData.newPlainText("", text))
    }

    /** A tap on the surface: it takes the keyboard and the key bar shows. */
    private fun focus() {
        compose.onNodeWithTag("terminal.surface").performClick()
        until { surface().hasFocus() && tagged("terminal.key.escape") }
    }

    // Plan 3G Task 13

    @Test
    fun aTapFocusesAndShowsTheKeyboardAndTheKeyBar() {
        livePane()
        compose.onNodeWithTag("terminal.surface").performClick()
        until { ime.shows == 1 }
        compose.onNodeWithTag("terminal.key.escape").assertIsDisplayed()
    }

    @Test
    fun theKeyBarDrivesTheModel() {
        livePane()
        focus()
        compose.onNodeWithTag("terminal.key.ctrl").performClick()
        compose.onNodeWithTag("terminal.key.ctrl").assertIsSelected()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, context.getString(R.string.terminal_key_ctrl_latched)))
        compose.onNodeWithTag("terminal.key.escape").performClick()
        until { inputs() == listOf(listOf(Key(TerminalKey.ESCAPE, listOf(TerminalModifier.CTRL)))) }
        compose.onNodeWithTag("terminal.key.hideKeyboard").performClick()
        until { !tagged("terminal.key.escape") }
        assertEquals(1, ime.hides)
    }

    @Test
    fun aLongPressOffersPasteThatSendsOnePasteUnit() {
        clipboard("echo a\necho b")
        livePane()
        compose.onNodeWithTag("terminal.surface").performTouchInput { longClick() }
        until { tagged("terminal.paste") }
        compose.onNodeWithTag("terminal.paste").performClick()
        until { inputs() == listOf<List<TerminalInputUnit>>(listOf(Paste("echo a\necho b"))) }
    }

    @Test
    fun aPasteOverTheLimitShowsTheNoticeAndSendsNothing() {
        clipboard("a".repeat(262_145))
        livePane()
        compose.onNodeWithTag("terminal.surface").performTouchInput { longClick() }
        until { tagged("terminal.paste") }
        val notice = context.getString(R.string.terminal_paste_too_large)
        // Frame by frame from here, so the 4 s count from the frame the notice shows.
        compose.mainClock.autoAdvance = false
        compose.onNodeWithTag("terminal.paste").performClick()
        compose.waitUntil(10_000) {
            compose.mainClock.advanceTimeByFrame()
            compose.onAllNodesWithText(notice).fetchSemanticsNodes().isNotEmpty()
        }
        assertEquals(emptyList<List<TerminalInputUnit>>(), inputs())
        compose.mainClock.advanceTimeBy(4_100)
        assertTrue("the notice goes after 4 s", compose.onAllNodesWithText(notice).fetchSemanticsNodes().isEmpty())
        compose.mainClock.autoAdvance = true
    }

    @Test
    fun withNothingToPasteTheItemIsDisabled() {
        clipboard(null)
        livePane()
        compose.onNodeWithTag("terminal.surface").performTouchInput { longClick() }
        until { tagged("terminal.paste") }
        compose.onNodeWithTag("terminal.paste").assertIsNotEnabled()
    }

    /** The surface's node as TalkBack gets it. */
    private fun node(surface: TerminalSurfaceView = surface()): AccessibilityNodeInfo = surface.createAccessibilityNodeInfo()

    /** The screen's rows as TalkBack should read them: blank rows at either end left out. */
    private fun screenRows(): String = model.screen.screenText().joinToString("\n").trim('\n')

    /** `t-zsh`'s row 0 becomes [text] on the Mac. */
    private fun macPrints(text: String) {
        rig.mac.emitTerminalFrame(
            "t-zsh",
            TerminalGridFrame(
                TerminalFrameHead(TerminalFrameKind.DELTA, model.screen.cols, model.screen.rows, cursor = TerminalCursor(0, 0)),
                lines = listOf(TerminalLine(0, listOf(TerminalRun(text = text)))),
            ),
        )
    }

    /** Turns TalkBack on for this test (Robolectric's accessibility manager). */
    private fun talkBackOn() {
        shadowOf(context.getSystemService(AccessibilityManager::class.java)).setEnabled(true)
    }

    /** Every text change [surface] tells accessibility services about. */
    private fun textChanges(surface: TerminalSurfaceView): List<Long> {
        val at = mutableListOf<Long>()
        surface.accessibilityDelegate = object : View.AccessibilityDelegate() {
            override fun sendAccessibilityEventUnchecked(host: View, event: AccessibilityEvent) {
                if (event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED &&
                    event.contentChangeTypes and AccessibilityEvent.CONTENT_CHANGE_TYPE_TEXT != 0
                ) {
                    at += SystemClock.uptimeMillis()
                }
                super.sendAccessibilityEventUnchecked(host, event)
            }
        }
        return at
    }

    /**
     * TalkBack reaches the terminal through the surface View itself: Compose hands an AndroidView's node to its View,
     * so semantics set on the pane never reach an accessibility service (found on the API 36 emulator). The page shown
     * reads "Terminal zsh", then its screen's rows (VoiceOver's label and value; TalkBack speaks a description in place
     * of the text, so the description carries both); under a card the surface is hidden from it and reads nothing.
     */
    @Test
    fun talkBackReadsTheTerminalShownAndNothingUnderACard() {
        livePane()
        assertTrue(surface().isImportantForAccessibility)
        val info = node()
        val rows = screenRows()
        assertTrue("the prompt is on the screen", rows.isNotEmpty())
        assertEquals(rows, info.text?.toString())
        assertEquals(context.getString(R.string.terminal_surface_label, "zsh") + "\n" + rows, info.contentDescription?.toString())
        rig.mac.endTerminalView("t-zsh", TerminalViewEndReason.REFUSED)
        until { model.phase is TerminalViewPhase.Unavailable }
        until { !surface().isImportantForAccessibility }
        assertNull(node().text)
        assertNull(node().contentDescription)
    }

    /** What the Mac prints is what TalkBack reads next: the node is built when asked, never kept. */
    @Test
    fun talkBackReadsTheScreenAsItIsNow() {
        livePane()
        macPrints("hello from the Mac")
        until { model.screen.screenText().first() == "hello from the Mac" }
        assertEquals(screenRows(), node().text?.toString())
        assertTrue("${node().text}", node().text!!.startsWith("hello from the Mac"))
    }

    /**
     * A change of the screen is told to TalkBack (a text change of the node, so it never keeps a stale screen), at most
     * once a second while the Mac keeps printing; the last change still goes out.
     */
    @Test
    fun talkBackHearsOfScreenChangesAtMostOnceASecond() {
        talkBackOn()
        livePane()
        val changes = textChanges(surface())
        idle(1_100)
        macPrints("one")
        until { changes.size == 1 }
        repeat(5) {
            macPrints("line $it")
            idle(50)
        }
        until { model.screen.screenText().first() == "line 4" }
        val printed = SystemClock.uptimeMillis()
        until { changes.last() >= printed }
        idle(1_500)
        assertTrue("five changes in a quarter second are told once or twice: $changes", changes.size in 2..3)
        assertTrue("a second between two: $changes", changes.zipWithNext().all { (a, b) -> b - a >= 1_000 })
    }

    /**
     * Nothing is told once a card covers the surface: neither a change still waiting for its second when the card came,
     * nor a change under the card.
     */
    @Test
    fun aCoveredSurfaceTellsTalkBackNothing() {
        talkBackOn()
        livePane()
        val surface = surface()
        val changes = textChanges(surface)
        idle(1_100)
        macPrints("one")
        until { changes.size == 1 }
        macPrints("two")
        until { model.screen.screenText().first() == "two" }
        rig.mac.endTerminalView("t-zsh", TerminalViewEndReason.REFUSED)
        until { model.phase is TerminalViewPhase.Unavailable }
        idle(1_500)
        assertEquals("$changes", 1, changes.size)
        compose.runOnIdle { surface.render(model.state.value.let { it.copy(screenRevision = it.screenRevision + 1) }) }
        idle(1_500)
        assertEquals("$changes", 1, changes.size)
    }

    /** A TalkBack user opens the keyboard with a double tap: the node says what it does ("Double-tap to type"). */
    @Test
    fun aTalkBackDoubleTapOpensTheKeyboard() {
        livePane()
        val info = node()
        val click = info.actionList.single { it.id == AccessibilityNodeInfo.ACTION_CLICK }
        assertEquals(context.getString(R.string.action_type), click.label?.toString())
        assertTrue(info.isClickable)
        compose.runOnIdle { assertTrue(surface().performAccessibilityAction(AccessibilityNodeInfo.ACTION_CLICK, null)) }
        until { surface().hasFocus() && ime.shows == 1 && tagged("terminal.key.escape") }
    }

    /** The surface of a page that is no longer the terminal shown reads nothing and offers nothing. */
    @Test
    fun aSurfaceOfAnotherTerminalReadsNothing() {
        livePane()
        val surface = surface()
        model.show("t-claude")
        until { model.terminalId == "t-claude" }
        val info = node(surface)
        assertNull(info.text)
        assertNull(info.contentDescription)
        assertTrue(info.actionList.none { it.id == AccessibilityNodeInfo.ACTION_CLICK })
        assertFalse(surface.performAccessibilityAction(AccessibilityNodeInfo.ACTION_CLICK, null))
    }

    /**
     * The terminal's screen is the user's (final review I-2): the pane's Compose node carries no text (Compose 1.7+ sends
     * semantics text to content capture), the surface takes no part in content capture or autofill, and only
     * accessibility tools read its node (API 34+).
     */
    @Test
    fun theScreenNeverReachesContentCaptureOrAutofill() {
        livePane()
        val config = compose.onNodeWithTag("terminal.surface").fetchSemanticsNode().config
        assertFalse(SemanticsProperties.Text in config)
        assertFalse(SemanticsProperties.ContentDescription in config)
        val surface = surface()
        assertEquals(View.IMPORTANT_FOR_CONTENT_CAPTURE_NO, surface.importantForContentCapture)
        assertEquals(View.IMPORTANT_FOR_AUTOFILL_NO, surface.importantForAutofill)
        assertTrue(surface.isAccessibilityDataSensitive)
    }

    /**
     * The soft keyboard as the system tells the window: [height] dp of room, [shown] (a floating keyboard is shown and
     * takes no room).
     */
    private fun keyboard(height: Int, shown: Boolean = height > 0) {
        compose.runOnIdle {
            val root = compose.activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0)
            val px = (height * root.resources.displayMetrics.density).toInt()
            val insets = WindowInsetsCompat.Builder()
                .setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, px))
                .setVisible(WindowInsetsCompat.Type.ime(), shown)
                .build()
            ViewCompat.dispatchApplyWindowInsets(root, insets)
        }
        idle(50)
    }

    /** The keyboard going down (system Back, its own key) takes the focus and the key bar with it, as on the iPhone. */
    @Test
    fun theKeyboardGoingDownGivesUpTheFocus() {
        livePane()
        focus()
        keyboard(300)
        assertTrue(surface().hasFocus())
        keyboard(0)
        until { !surface().hasFocus() && !tagged("terminal.key.escape") }
    }

    /** A keyboard turned floating while typing is still shown though it takes no room: the focus stays (review D1 M5). */
    @Test
    fun aFloatingKeyboardKeepsTheFocus() {
        livePane()
        focus()
        keyboard(300)
        keyboard(0, shown = true)
        idle(300)
        assertTrue(surface().hasFocus())
        assertTrue(tagged("terminal.key.escape"))
    }

    /**
     * The app going to the background hides the keyboard after the window lost the focus: the terminal keeps its focus
     * for the return (final review m4; the iPhone keeps its first responder through a resume).
     */
    @Test
    fun theKeyboardHiddenWhileTheWindowIsAwayKeepsTheFocus() {
        livePane()
        focus()
        keyboard(300)
        compose.runOnIdle { compose.activity.window.decorView.dispatchWindowFocusChanged(false) }
        idle(50)
        keyboard(0)
        idle(300)
        assertTrue(surface().hasFocus())
        compose.runOnIdle { compose.activity.window.decorView.dispatchWindowFocusChanged(true) }
        idle(300)
        assertTrue(surface().hasFocus())
        assertTrue(tagged("terminal.key.escape"))
    }

    // TerminalPaneTests.swift, re-expressed for Android (ruling 11)

    /** A page that stops taking input (the Mac refused the view) gives the keyboard back and hides the key bar. */
    @Test
    fun aCoveredPageGivesUpTheKeyboardAndTheKeyBar() {
        livePane()
        focus()
        rig.mac.endTerminalView("t-zsh", TerminalViewEndReason.REFUSED)
        until { model.phase == TerminalViewPhase.Unavailable(TerminalUnavailableReason.REFUSED) }
        until { !surface().hasFocus() && !tagged("terminal.key.escape") }
        assertTrue(ime.hides >= 1)
    }

    /** Keys typed into the surface of a page that is no longer the one shown never reach the terminal shown now. */
    @Test
    fun aPageNoLongerShownSendsNoKeys() {
        livePane()
        val surface = surface()
        val connection = InputConnection(surface)
        model.show("t-claude")
        connection.commitText("x", 1)
        connection.commitText("\n", 1)
        assertFalse(surface.handleKey(android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_X)))
        until { rig.mac.terminalViewOpens.any { it.terminalId == "t-claude" } }
        idle(300)
        assertEquals(emptyList<List<TerminalInputUnit>>(), inputs("t-claude"))
        assertEquals(emptyList<List<TerminalInputUnit>>(), inputs("t-zsh"))
    }

    /** A text field that takes the keyboard keeps it while the terminal it took it from keeps changing. */
    @Test
    fun aTerminalNeverTakesTheKeyboardBack() {
        start()
        show {
            Column(Modifier.fillMaxSize()) {
                TerminalPane(model, "t-zsh", "zsh", shown = true, modifier = Modifier.weight(1f))
                var text by remember { mutableStateOf("") }
                BasicTextField(text, { text = it }, Modifier.fillMaxWidth().testTag("field"))
            }
        }
        until { model.phase == TerminalViewPhase.Live }
        focus()
        compose.onNodeWithTag("field").performClick()
        // The terminal changes in the same turn, before the pane hears the surface lost the keyboard.
        model.toggleCtrl()
        idle(300)
        compose.onNodeWithTag("field").assertIsFocused()
        assertFalse(surface().hasFocus())
    }

    /** Only the page shown says a paste is too large: a neighbour composed with the same model says nothing. */
    @Test
    fun onlyThePageShownSaysAPasteIsTooLarge() {
        val screen = TerminalScreen().apply { apply(DemoTerminalScreens.SHELL.snapshot) }
        val fixed = TerminalViewModel.fixed("t-zsh", screen)
        show {
            Column(Modifier.fillMaxSize()) {
                TerminalPane(fixed, "t-zsh", "zsh", shown = true, modifier = Modifier.weight(1f))
                TerminalPane(fixed, "t-web", "zsh", shown = true, modifier = Modifier.weight(1f))
            }
        }
        compose.waitForIdle()
        fixed.paste("x".repeat(TerminalInputBatcher.MAX_PASTE_BYTES + 1))
        val notice = context.getString(R.string.terminal_paste_too_large)
        until { compose.onAllNodesWithText(notice).fetchSemanticsNodes().isNotEmpty() }
        assertEquals(1, compose.onAllNodesWithText(notice).fetchSemanticsNodes().size)
    }

    /** A shell the user is typing into stays shown when an agent of the workspace starts waiting for an answer: the
     *  keyboard is not pulled away mid-command (the workspace screen settles on the page typed into). */
    @Test
    fun typingIntoAShellKeepsItShownWhenAnAgentAsks() {
        show { WorkspaceView(rig.scope, WorkspaceRef(rig.machineId, "ws-shellx"), open = {}, back = {}) }
        until { surfaces().singleOrNull()?.let { it.model.terminalId == "t-zsh" && it.model.phase == TerminalViewPhase.Live } == true }
        focus()
        InputConnection(surface()).commitText("ec", 1)
        until { inputs() == listOf(listOf(Text("ec"))) }
        val nowMs = System.currentTimeMillis()
        rig.mac.upsertSession(
            AgentSession("s1", "claude", "ws-shellx", "shellx-ios", state = AgentState.NEEDS_INPUT, stateSinceMs = nowMs, lastActivityMs = nowMs),
        )
        until { rig.hub.liveSessions.firstOrNull()?.session?.state == AgentState.NEEDS_INPUT }
        idle(300)
        assertEquals("the shell being typed into stays shown", "t-zsh", surface().model.terminalId)
    }

    /** A page that is reopening (its view ended `failed`; the last screen stays, uncovered) takes no input: the
     *  keyboard and the key bar go. */
    @Test
    fun aReopeningPageGivesUpTheKeyboardAndTheKeyBar() {
        livePane()
        focus()
        rig.mac.endTerminalView("t-zsh", TerminalViewEndReason.FAILED)
        until { model.phase == TerminalViewPhase.Connecting }
        until { !surface().hasFocus() && !tagged("terminal.key.escape") }
    }

    /** Review Focus 1 through a pager: after A → B → A there is one surface, on the page shown, and keys typed into it
     *  reach A only. */
    @Test
    fun swipingBackAndForthLeavesOneSurfaceOnThePageShown() {
        start()
        val ids = listOf("t-zsh", "t-claude")
        lateinit var pager: PagerState
        lateinit var scope: CoroutineScope
        show {
            val state = rememberPagerState { ids.size }
            pager = state
            scope = rememberCoroutineScope()
            // The workspace screen's wiring: the page the pager settles on is the terminal the model shows.
            LaunchedEffect(state.settledPage) { model.show(ids[state.settledPage]) }
            HorizontalPager(state, Modifier.fillMaxSize()) { page ->
                TerminalPane(model, ids[page], "zsh", shown = state.settledPage == page)
            }
        }
        fun shows(id: String) = until { model.phase == TerminalViewPhase.Live && surfaces().map { it.terminalId } == listOf(id) }
        shows("t-zsh")
        compose.runOnIdle { scope.launch { pager.scrollToPage(1) } }
        shows("t-claude")
        compose.runOnIdle { scope.launch { pager.scrollToPage(0) } }
        shows("t-zsh")
        InputConnection(surface()).commitText("ls", 1)
        until { inputs() == listOf(listOf(Text("ls"))) }
        assertEquals(emptyList<List<TerminalInputUnit>>(), inputs("t-claude"))
    }

    /** The screen stops and starts again (the background, a rotation) while the user is typing: the keyboard and the key
     *  bar stay through the reopen, and a key typed before the first screen comes back reaches the reopened view. */
    @Test
    fun theKeyboardStaysThroughAResume() {
        livePane()
        focus()
        run?.cancel()
        until { rig.mac.terminalViewCloses == listOf("t-zsh") }
        rig.mac.holdTerminalViewOpens()
        run = rig.hub.scope.launch { model.run() }
        until { rig.mac.terminalViewOpens.size == 2 && model.phase == TerminalViewPhase.Connecting }
        idle(200)
        assertTrue("the keyboard stays while the view reopens", surface().hasFocus())
        assertTrue("the key bar stays", tagged("terminal.key.escape"))
        InputConnection(surface()).commitText("ls", 1)
        rig.mac.releaseTerminalViewOpens()
        until { inputs() == listOf(listOf(Text("ls"))) }
        until { model.phase == TerminalViewPhase.Live }
        assertTrue(surface().hasFocus())
    }

    /** A view the Mac ends `not_open` is reopened at once: the keyboard stays. */
    @Test
    fun theKeyboardStaysThroughANotOpenReopen() {
        livePane()
        focus()
        rig.mac.holdTerminalViewOpens()
        rig.mac.endTerminalView("t-zsh", TerminalViewEndReason.NOT_OPEN)
        until { rig.mac.terminalViewOpens.size == 2 && model.phase == TerminalViewPhase.Connecting }
        idle(200)
        assertTrue("the keyboard stays while the view reopens", surface().hasFocus())
        rig.mac.releaseTerminalViewOpens()
        until { model.phase == TerminalViewPhase.Live }
        assertTrue(surface().hasFocus())
    }

    /** The wait before a failed view is reopened has no view to type into: it takes the keyboard away and sends nothing
     *  typed meanwhile. */
    @Test
    fun aFailedViewsRetryWaitSendsNothing() {
        livePane()
        focus()
        val connection = InputConnection(surface())
        rig.mac.endTerminalView("t-zsh", TerminalViewEndReason.FAILED)
        until { model.phase == TerminalViewPhase.Connecting }
        connection.commitText("rm", 1)
        until { !surface().hasFocus() }
        until { model.phase == TerminalViewPhase.Live }
        idle(100)
        assertEquals("nothing typed during the wait is sent", emptyList<List<TerminalInputUnit>>(), inputs())
    }
}
