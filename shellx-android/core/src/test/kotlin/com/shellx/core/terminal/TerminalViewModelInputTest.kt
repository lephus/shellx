package com.shellx.core.terminal

import com.shellx.core.diagnostics.LatencyMetric
import com.shellx.core.testing.Gate
import com.shellx.core.testing.ManualClock
import com.shellx.core.testing.ManualSleeper
import com.shellx.core.testing.ScriptedTerminalLink
import com.shellx.core.testing.ScriptedTerminalLink.Call
import com.shellx.core.testing.deltaPart
import com.shellx.core.testing.eventually
import com.shellx.core.testing.snapshotPart
import com.shellx.link.core.TerminalInputUnit
import com.shellx.link.core.TerminalInputUnit.Key
import com.shellx.link.core.TerminalInputUnit.Paste
import com.shellx.link.core.TerminalInputUnit.Scroll
import com.shellx.link.core.TerminalInputUnit.Text
import com.shellx.link.core.TerminalKey
import com.shellx.link.core.TerminalModifier
import com.shellx.link.core.TerminalScreen
import com.shellx.link.core.TerminalViewPush
import com.shellx.link.core.TerminalViewPush.Frame
import com.shellx.link.core.TerminalViewPush.Opened
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

/**
 * The terminal view model's typing, paste, scrolling and resizing (rules R10–R12, A6), against a [ScriptedTerminalLink]
 * (TerminalViewModelInputTests.swift).
 */
class TerminalViewModelInputTest {
    /** A model of Mac `m1` whose run() runs in the test's backgroundScope until the test ends, and that run's job. */
    private fun TestScope.makeModel(
        link: ScriptedTerminalLink,
        sleeper: ManualSleeper = ManualSleeper(),
        maxHistoryRows: Int = TerminalScreen.DEFAULT_MAX_HISTORY_ROWS,
        clock: ManualClock = ManualClock(),
    ): Pair<TerminalViewModel, Job> {
        val model = TerminalViewModel("m1", link, backgroundScope, maxHistoryRows, sleeper.sleep, clock.monotonic)
        val run = backgroundScope.launch { model.run() }
        return model to run
    }

    /** Shows [id] at 50 × 20 and brings it live with a first snapshot of [text]. */
    private suspend fun TestScope.live(
        model: TerminalViewModel,
        link: ScriptedTerminalLink,
        id: String = "t1",
        text: List<String> = listOf("$"),
        alt: Boolean = false,
    ) {
        model.setPhoneGrid(50, 20)
        model.show(id)
        eventually { link.opens.lastOrNull() == id }
        emit(link, Opened(id))
        emit(link, Frame(id, snapshotPart(1, cols = 50, rows = 20, text = text, alt = alt)))
        assertTrue(eventually { model.phase == TerminalViewPhase.Live }, "${model.phase} ${link.calls}")
    }

    private fun emit(link: ScriptedTerminalLink, push: TerminalViewPush) = link.emit(TerminalHubEvent.Push("m1", push))

    private fun ScriptedTerminalLink.resizes() = calls.filterIsInstance<Call.Resize>()

    private fun ScriptedTerminalLink.echoes() = latencies.count { it == LatencyMetric.TERMINAL_KEY_ECHO }

    @Test fun typingSendsCommittedTextOnly() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link); live(model, link)
        model.setMarkedText("v"); model.setMarkedText("vi"); model.setMarkedText("việ")
        assertEquals("việ", model.markedText)
        delay(50.milliseconds); assertEquals(emptyList(), link.inputs)
        model.insertText("việt")
        assertTrue(eventually { link.inputs == listOf(listOf(Text("việt"))) })
    } }

    @Test fun backspaceWhileComposingSendsNothing() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link); live(model, link)
        model.setMarkedText("việ"); model.deleteBackward()
        assertEquals("vi", model.markedText)
        model.unmarkText(); model.deleteBackward()
        assertTrue(eventually { link.inputs == listOf(listOf(Text("vi")), listOf(Key(TerminalKey.BACKSPACE))) })
    } }

    @Test fun theKeyBarAndTheCtrlLatch() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link); live(model, link)
        model.toggleCtrl(); assertTrue(model.ctrlLatched)
        model.insertText("c"); model.press(TerminalKey.ESCAPE)
        assertTrue(eventually {
            link.inputs == listOf(listOf(Key(TerminalKey.letter('c'), listOf(TerminalModifier.CTRL))), listOf(Key(TerminalKey.ESCAPE)))
        })
    } }

    @Test fun inputTypedWhileOpeningGoesAfterTheOpen() { runTest {
        val link = ScriptedTerminalLink(); val gate = Gate(); link.openGate = gate
        val (model, _) = makeModel(link)
        model.setPhoneGrid(50, 20); model.show("t1")
        eventually { link.opens == listOf("t1") }
        model.insertText("ls")
        delay(50.milliseconds)
        assertEquals(listOf<Call>(Call.Open("t1", 50, 20)), link.calls)
        gate.open()
        assertTrue(eventually { link.calls == listOf(Call.Open("t1", 50, 20), Call.Input("t1", listOf(Text("ls")))) })
    } }

    @Test fun inputAfterASwitchGoesToTheNewTerminal() { runTest {   // Review Focus 1
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link); live(model, link)
        model.show("t2"); model.insertText("x")
        assertTrue(eventually { link.calls.last() == Call.Input("t2", listOf(Text("x"))) })
        assertFalse(Call.Input("t1", listOf(Text("x"))) in link.calls)
    } }

    @Test fun nothingIsTypedWithoutAView() { runTest {
        val link = ScriptedTerminalLink(); link.online = false
        val (model, _) = makeModel(link)
        model.setPhoneGrid(50, 20); model.show("t1")
        eventually { model.phase == TerminalViewPhase.Offline }
        model.insertText("x"); model.paste("y"); model.press(TerminalKey.ENTER)
        delay(50.milliseconds)
        assertEquals(emptyList(), link.inputs)
    } }

    @Test fun pasteGoesInPasteSizedMessages() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link); live(model, link)
        model.paste("a".repeat(20_000))
        assertTrue(eventually { link.inputs.size == 2 })
        assertEquals(listOf(listOf(Paste("a".repeat(16_384))), listOf(Paste("a".repeat(3_616)))), link.inputs)
    } }

    @Test fun aPasteOverTheLimitIsRefused() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link); live(model, link)
        model.paste("a".repeat(TerminalInputBatcher.MAX_PASTE_BYTES + 1))
        delay(50.milliseconds)
        assertEquals(emptyList(), link.inputs, "nothing of it is sent")
        assertEquals(1, model.pasteTooLarge); assertEquals(0, model.sentInputs)
    } }

    @Test fun scrollOnTheAlternateScreenIsSummed() { runTest {
        val link = ScriptedTerminalLink(); val sleeper = ManualSleeper(); val (model, _) = makeModel(link, sleeper)
        live(model, link, alt = true)
        model.scroll(1); model.scroll(1); model.scroll(1)
        assertEquals(emptyList(), link.inputs)
        eventually { TerminalViewModel.SCROLL_COALESCING in sleeper.waiting }
        sleeper.release { it == TerminalViewModel.SCROLL_COALESCING }
        assertTrue(eventually { link.inputs == listOf(listOf(Scroll(3))) })
    } }

    @Test fun scrollOnTheMainScreenSendsNothing() { runTest {
        val link = ScriptedTerminalLink(); val sleeper = ManualSleeper(); val (model, _) = makeModel(link, sleeper)
        live(model, link)
        model.scroll(3); sleeper.release()
        delay(50.milliseconds)
        assertEquals(emptyList(), link.inputs)
    } }

    @Test fun gridChangesSendOneResizeWithTheLatestSize() { runTest {   // Review Focus 3
        val link = ScriptedTerminalLink(); val sleeper = ManualSleeper(); val (model, _) = makeModel(link, sleeper)
        live(model, link)
        model.setPhoneGrid(50, 10); model.setPhoneGrid(40, 18); model.setPhoneGrid(50, 12)
        assertEquals(emptyList(), link.resizes())
        eventually { TerminalViewModel.RESIZE_DELAY in sleeper.waiting }
        sleeper.release { it == TerminalViewModel.RESIZE_DELAY }
        val one = eventually { link.resizes() == listOf(Call.Resize("t1", 50, 12)) }
        delay(50.milliseconds)
        assertTrue(one); assertEquals(1, link.resizes().size)
    } }

    @Test fun resizeDuringTheOpenFollowsIt() { runTest {   // Review Focus 3
        val link = ScriptedTerminalLink(); val gate = Gate(); link.openGate = gate
        val sleeper = ManualSleeper(); val (model, _) = makeModel(link, sleeper)
        model.setPhoneGrid(50, 20); model.show("t1")
        eventually { link.opens == listOf("t1") }
        model.setPhoneGrid(50, 12)
        eventually { TerminalViewModel.RESIZE_DELAY in sleeper.waiting }
        sleeper.release { it == TerminalViewModel.RESIZE_DELAY }
        gate.open()
        assertTrue(eventually { link.calls == listOf(Call.Open("t1", 50, 20), Call.Resize("t1", 50, 12)) })
    } }

    @Test fun theSameSizeSendsNoResize() { runTest {
        val link = ScriptedTerminalLink(); val sleeper = ManualSleeper(); val (model, _) = makeModel(link, sleeper)
        live(model, link)
        model.setPhoneGrid(50, 20); sleeper.release()
        delay(50.milliseconds)
        assertEquals(emptyList(), link.resizes())
    } }

    @Test fun echoIsMeasuredFromTypingToTheNextFrame() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link); live(model, link)
        model.insertText("a")
        eventually { link.inputs.size == 1 }
        emit(link, Frame("t1", deltaPart(2, cols = 50, rows = 20, replacing = mapOf(0 to "$ a"))))
        assertTrue(eventually { link.echoes() == 1 })
        emit(link, Frame("t1", deltaPart(3, cols = 50, rows = 20, replacing = mapOf(1 to "x"))))
        delay(50.milliseconds)
        assertEquals(1, link.echoes(), "one echo per keystroke")
    } }

    @Test fun anEchoThatNeverComesIsDropped() { runTest {
        val link = ScriptedTerminalLink(); val sleeper = ManualSleeper(); val (model, _) = makeModel(link, sleeper)
        live(model, link)
        model.insertText("a")
        eventually { TerminalViewModel.ECHO_TIMEOUT in sleeper.waiting }
        sleeper.release { it == TerminalViewModel.ECHO_TIMEOUT }
        delay(20.milliseconds)
        emit(link, Frame("t1", deltaPart(2, cols = 50, rows = 20, replacing = mapOf(0 to "late"))))
        delay(50.milliseconds)
        assertFalse(LatencyMetric.TERMINAL_KEY_ECHO in link.latencies)
    } }

    /** A paste while a word is composed sends the word first, like a key does; a paste refused for its size leaves the
     *  word composing (the iPhone's final review, core M2). */
    @Test fun aPasteWhileComposingCommitsTheWordFirst() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link); live(model, link)
        model.setMarkedText("việ")
        model.paste("x".repeat(TerminalInputBatcher.MAX_PASTE_BYTES + 1))
        assertEquals(1, model.pasteTooLarge)
        assertEquals("việ", model.markedText, "a refused paste commits nothing")
        model.paste("echo hi")
        assertTrue(eventually { link.inputs.flatten() == listOf(Text("việ"), Paste("echo hi")) }, "${link.inputs}")
        assertEquals("", model.markedText)
    } }

    /** A6: the limit is on the cleaned paste (control characters dropped), and each refusal raises the notice by one. */
    @Test fun aPasteOverTheLimitIsRefusedWithANotice() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link); live(model, link)
        model.paste("a".repeat(262_145)); runCurrent()
        assertEquals(emptyList(), link.inputs); assertEquals(1, model.pasteTooLarge)
        model.paste("a".repeat(262_144) + "\u001b")
        assertTrue(eventually { link.inputs.size == 16 })
        assertTrue(link.inputs.all { it == listOf(Paste("a".repeat(16_384))) }); assertEquals(1, model.pasteTooLarge)
    } }

    /** Review B2 I-2: text a key event types commits the word in progress first, in the same message. */
    @Test fun aKeyEventWhileComposingCommitsTheWordInOneMessage() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link); live(model, link)
        model.setMarkedText("việ")
        model.typeKey("\n")
        assertEquals("", model.markedText)
        assertTrue(eventually { link.inputs.isNotEmpty() })
        assertEquals(listOf<List<TerminalInputUnit>>(listOf(Text("việ"), Key(TerminalKey.ENTER))), link.inputs)
        assertEquals(1, model.sentInputs)
    } }
}
