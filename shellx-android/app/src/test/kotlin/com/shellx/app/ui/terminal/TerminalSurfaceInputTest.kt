package com.shellx.app.ui.terminal

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.os.SystemClock
import android.text.InputType
import android.view.KeyEvent
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.WorkRig
import com.shellx.app.testing.eventually
import com.shellx.core.terminal.TerminalBarKey
import com.shellx.core.terminal.TerminalViewModel
import com.shellx.core.terminal.TerminalViewPhase
import com.shellx.link.core.TerminalInputUnit
import com.shellx.link.core.TerminalInputUnit.Key
import com.shellx.link.core.TerminalInputUnit.Paste
import com.shellx.link.core.TerminalInputUnit.Text
import com.shellx.link.core.TerminalKey
import com.shellx.link.core.TerminalModifier
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.shadows.ShadowLooper

/**
 * The terminal surface as the keyboard and a hardware keyboard reach it (`TerminalSurfaceTests.swift`), against the
 * fake Mac's `t-zsh` at 40 × 10: what the editor asks of the keyboard, composing that stays on the phone, hardware keys,
 * Ctrl+Shift+V, a key bar key during a composition, and keys that reach a surface whose terminal is no longer shown.
 */
@RunWith(AndroidJUnit4::class)
class TerminalSurfaceInputTest {
    private val rig = WorkRig.make()
    private val model = TerminalViewModel(rig.machineId, rig.hub, rig.hub.scope)
    private val ime = RecordingIme()
    private lateinit var run: Job
    private lateinit var activity: Activity
    private lateinit var surface: TerminalSurfaceView

    @Before
    fun setUp() {
        run = rig.hub.scope.launch { model.run() }
        model.setPhoneGrid(40, 10)
        model.show("t-zsh")
        assertTrue(eventually { model.phase == TerminalViewPhase.Live })
        activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        surface = TerminalSurfaceView(activity, model, "t-zsh", TerminalFont(activity), ime)
        activity.setContentView(surface)
    }

    @After
    fun tearDown() {
        run.cancel()
        rig.close()
    }

    private fun inputs(id: String = "t-zsh") = rig.mac.terminalViewInputs(id)

    private fun connection(): InputConnection = checkNotNull(surface.onCreateInputConnection(EditorInfo()))

    /** Down and up of [keyCode] with [meta] held. */
    private fun press(keyCode: Int, meta: Int = 0) {
        surface.dispatchKeyEvent(KeyEvent(0, 0, KeyEvent.ACTION_DOWN, keyCode, 0, meta))
        surface.dispatchKeyEvent(KeyEvent(0, 0, KeyEvent.ACTION_UP, keyCode, 0, meta))
    }

    /** Lets the main looper run for [ms] of real time and says whether [condition] came true meanwhile. */
    private fun within(ms: Long, condition: () -> Boolean) = eventually(ms, condition)

    @Test
    fun theEditorInfoKeepsComposingAndTurnsOffWhatATerminalMustNotHave() {
        val info = EditorInfo().also { surface.onCreateInputConnection(it) }
        assertEquals(
            InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS or InputType.TYPE_TEXT_FLAG_MULTI_LINE,
            info.inputType,
        )
        for (flag in listOf(
            EditorInfo.IME_FLAG_NO_EXTRACT_UI, EditorInfo.IME_FLAG_NO_FULLSCREEN, EditorInfo.IME_FLAG_NO_ENTER_ACTION,
            EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING,
        )) {
            assertTrue("imeOptions has $flag", info.imeOptions and flag == flag)
        }
        assertTrue(surface.onCheckIsTextEditor())
    }

    @Test
    fun telexComposingReachesTheMacOnlyWhenCommitted() {
        val c = connection()
        for (word in listOf("T", "Ti", "Tie", "Tiê", "Tiên", "Tiến", "Tiếng")) c.setComposingText(word, 1)
        assertFalse("nothing composed goes out", within(200) { inputs().isNotEmpty() })
        c.commitText("Tiếng", 1)
        assertTrue("${inputs()}", eventually { inputs() == listOf(listOf(Text("Tiếng"))) })
    }

    @Test
    fun hardwareKeysReachTheMacAsNamedKeysOrText() { // Review Focus 3
        press(KeyEvent.KEYCODE_ESCAPE)
        press(KeyEvent.KEYCODE_DPAD_LEFT)
        press(KeyEvent.KEYCODE_C, KeyEvent.META_CTRL_ON)
        press(KeyEvent.KEYCODE_X)
        press(KeyEvent.KEYCODE_1)
        press(KeyEvent.KEYCODE_DEL)
        press(KeyEvent.KEYCODE_V, KeyEvent.META_CTRL_ON)
        val expected = listOf(
            listOf(Key(TerminalKey.ESCAPE)), listOf(Key(TerminalKey.LEFT)),
            listOf(Key(TerminalKey.letter('c'), listOf(TerminalModifier.CTRL))), listOf(Text("x")), listOf(Text("1")),
            listOf(Key(TerminalKey.BACKSPACE)), listOf(Key(TerminalKey.letter('v'), listOf(TerminalModifier.CTRL))),
        )
        assertTrue("${inputs()}", eventually { inputs() == expected })
    }

    @Test
    fun ctrlShiftVPastesTheClipboard() {
        activity.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("", "echo a\necho b"))
        press(KeyEvent.KEYCODE_V, KeyEvent.META_CTRL_ON or KeyEvent.META_SHIFT_ON)
        assertTrue("${inputs()}", eventually { inputs() == listOf<List<TerminalInputUnit>>(listOf(Paste("echo a\necho b"))) })
    }

    @Test
    fun aKeyBarKeyWhileComposingCommitsTheWordAndRestartsTheKeyboard() {
        connection().setComposingText("việ", 1)
        TerminalPane.perform(TerminalKeyBarItem.Key(TerminalBarKey.LEFT), model) {}
        surface.render(model.state.value)
        assertTrue("${inputs()}", eventually { inputs() == listOf(listOf(Text("việ"), Key(TerminalKey.LEFT))) })
        ShadowLooper.idleMainLooper()
        assertEquals(1, ime.restarts)
    }

    @Test
    fun onlyTheTerminalShownTakesKeys() { // Review Focus 1
        val c = connection()
        model.show("t-claude")
        assertFalse(surface.handleKey(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_X)))
        c.commitText("x", 1)
        assertTrue(eventually { rig.mac.terminalViewOpens.any { it.terminalId == "t-claude" } })
        assertFalse("nothing reaches the terminal left", within(200) { inputs().isNotEmpty() })
        assertEquals("nor the one shown now", emptyList<List<TerminalInputUnit>>(), inputs("t-claude"))
    }

    // Fix round (reviews D1 M2, M3, M7 and final m2)

    /**
     * A Backspace the keyboard sends as a key event while a word is composed edits the word on the phone, as
     * deleteSurroundingText does: nothing restarts the keyboard (a restart closes the connection, which commits the
     * word), and nothing goes to the Mac.
     */
    @Test
    fun aDeleteKeyEventWhileComposingKeepsTheWordOnThePhone() {
        val c = connection()
        c.setComposingText("việ", 1)
        c.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL))
        c.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL))
        surface.render(model.state.value)
        ShadowLooper.idleMainLooper()
        // What the framework does when the keyboard restarts.
        if (ime.restarts > 0) c.closeConnection()
        assertFalse("${inputs()}", within(200) { inputs().isNotEmpty() })
        assertEquals("vi", model.markedText)
        assertEquals(0, ime.restarts)
        c.setComposingText("viê", 1)
        c.commitText("việt", 1)
        assertTrue("${inputs()}", eventually { inputs() == listOf(listOf(Text("việt"))) })
    }

    /** Text a key event carries (ACTION_MULTIPLE) is a key: the word being composed is committed first. */
    @Test
    fun aMultipleKeyEventWhileComposingCommitsTheWordFirst() {
        connection().setComposingText("vi", 1)
        assertTrue(surface.handleKey(KeyEvent(SystemClock.uptimeMillis(), "x", 0, 0)))
        assertTrue("${inputs()}", eventually { inputs() == listOf(listOf(Text("vi"), Text("x"))) || inputs() == listOf(listOf(Text("vix"))) })
    }

    /** ACTION_MULTIPLE text with a line break is pasted, as a commit with one is (A-32). */
    @Test
    fun aMultipleKeyEventWithALineBreakIsPasted() {
        assertTrue(surface.handleKey(KeyEvent(SystemClock.uptimeMillis(), "echo a\necho b", 0, 0)))
        assertTrue("${inputs()}", eventually { inputs() == listOf<List<TerminalInputUnit>>(listOf(Paste("echo a\necho b"))) })
    }

    /**
     * replaceText (API 34) reaches the model: a range inside the word being composed is replaced and the word committed;
     * the base class would edit its own empty buffer and say it worked.
     */
    @Test
    fun replaceTextReachesTheMac() {
        val c = connection()
        c.setComposingText("teh", 1)
        assertTrue(c.replaceText(0, 3, "the", 1, null))
        assertTrue("${inputs()}", eventually { inputs() == listOf(listOf(Text("the"))) })
        assertTrue(c.replaceText(0, 0, "x", 1, null))
        assertTrue("${inputs()}", eventually { inputs() == listOf(listOf(Text("the")), listOf(Text("x"))) })
    }

    /**
     * A commit longer than one input message (4 096 bytes) is a paste (final review m2): 100 KB arrives whole, in paste
     * messages, never cut by the Mac's 64-message queue.
     */
    @Test
    fun aCommitLongerThanOneMessageIsPasted() {
        val text = "a".repeat(100_000)
        connection().commitText(text, 1)
        assertTrue(eventually { inputs().flatten().joinToString("") { (it as? Paste)?.text.orEmpty() }.length == 100_000 })
        assertTrue("${inputs().flatten().map { it::class.simpleName }.toSet()}", inputs().flatten().all { it is Paste })
        assertTrue(inputs().size <= 16)
    }

    /** A commit over the paste limit sends nothing and says so, as a paste does. */
    @Test
    fun aCommitOverThePasteLimitIsRefused() {
        connection().commitText("a".repeat(262_145), 1)
        assertTrue(eventually { model.state.value.pasteTooLarge == 1 })
        assertFalse(within(200) { inputs().isNotEmpty() })
    }

    /** The keyboard's own Paste (its context menu, its clipboard key) pastes the clipboard as one paste (review D1 M11). */
    @Test
    fun theKeyboardsPasteSendsOnePasteUnit() {
        activity.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("", "echo a\necho b"))
        assertTrue(connection().performContextMenuAction(android.R.id.paste))
        assertTrue("${inputs()}", eventually { inputs() == listOf<List<TerminalInputUnit>>(listOf(Paste("echo a\necho b"))) })
    }
}
