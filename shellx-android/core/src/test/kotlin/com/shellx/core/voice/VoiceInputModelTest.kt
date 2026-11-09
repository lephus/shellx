package com.shellx.core.voice

import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.diagnostics.LatencyMetric
import com.shellx.core.home.ComposerValidation
import com.shellx.core.platform.CoreLog
import com.shellx.core.testing.FakeTranscriber
import com.shellx.core.testing.FakeVoicePermissions
import com.shellx.core.testing.Gate
import com.shellx.core.testing.HoppingCancel
import com.shellx.core.testing.NotReadyPrimary
import com.shellx.core.testing.eventually
import com.shellx.core.text.utf8Size
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TestTimeSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.yield
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

/** Hold-to-talk: press starts listening and shows the words as they come; release returns them; a drag to the left
 *  arms cancel; a swipe up before any word asks for the keyboard. Permissions, a missing recognizer and the
 *  16 384-byte limit each end the dictation visibly, and the keyboard always stays usable. */
class VoiceInputModelTest {
    private class Rig(
        val model: VoiceInputModel,
        val transcriber: FakeTranscriber,
        val permissions: FakeVoicePermissions,
        val clock: TestTimeSource,
        val latency: LatencyLog,
    )

    private companion object {
        val EVERYTHING = VoiceCapabilities(onDeviceRecognizer = true, standardOnDevice = true, standardAvailable = true)
    }

    private fun TestScope.makeRig(
        microphone: Boolean = true,
        speech: Boolean = true,
        capabilities: VoiceCapabilities = EVERYTHING,
        language: VoiceLanguage = VoiceLanguage.VIETNAMESE,
        maxBytes: Int = ComposerValidation.MAX_BYTES,
        engine: (FakeTranscriber) -> SpeechEngine = { it },
        scope: CoroutineScope = backgroundScope,
        slot: SpeechRunSlot = SpeechRunSlot(),
    ): Rig {
        val transcriber = FakeTranscriber(slot)
        val permissions = FakeVoicePermissions(microphone = microphone, speech = speech)
        val clock = TestTimeSource()
        val latency = LatencyLog()
        val model = VoiceInputModel(
            engine(transcriber), permissions, capabilities = { capabilities }, language = language,
            contextualStrings = { listOf("shellx", "PR") }, latency = latency, timeSource = clock, scope = scope,
            maxBytes = maxBytes,
        )
        return Rig(model, transcriber, permissions, clock, latency)
    }

    /** A supervised child of backgroundScope, as hub.scope is of the app scope: `MachineHub.stopAll()` cancels it on a
     *  sign-out, a deletion, a refused token (401) and the demo's Exit. */
    private fun TestScope.hubScope(): CoroutineScope =
        CoroutineScope(backgroundScope.coroutineContext + SupervisorJob(backgroundScope.coroutineContext.job))

    private suspend fun TestScope.waitForPhase(model: VoiceInputModel, phase: VoiceInputModel.Phase) {
        val reached = eventually { model.phase == phase }
        assertTrue(reached, "phase is ${model.phase}, expected $phase")
    }

    @Test fun pressStartsListeningAndStreamsText() { runTest {
        val rig = makeRig()
        rig.model.press()
        assertEquals(VoiceInputModel.Phase.Listening(""), rig.model.phase)
        val start = assertNotNull(rig.transcriber.starts.firstOrNull())
        assertEquals(1, rig.transcriber.starts.size)
        assertEquals(VoiceLanguage.VIETNAMESE, start.language)
        assertEquals(listOf("shellx", "PR"), start.contextualStrings)

        rig.transcriber.say("chạy test")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("chạy test"))
        rig.transcriber.say("chạy test cho shellx")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("chạy test cho shellx"))

        // A second press while listening changes nothing.
        rig.model.press()
        assertEquals(1, rig.transcriber.starts.size)
    } }

    @Test fun releaseReturnsFinalText() { runTest {
        val rig = makeRig(language = VoiceLanguage.ENGLISH)
        rig.model.press()
        assertEquals(VoiceLanguage.ENGLISH, rig.transcriber.starts.firstOrNull()?.language)
        rig.transcriber.say("run the tests for shell")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("run the tests for shell"))
        rig.transcriber.finalText = " Run the tests for shellx. "

        val text = rig.model.release()
        assertEquals("Run the tests for shellx.", text)
        assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase)
        assertEquals(1, rig.transcriber.finishCalls)
        assertEquals(0, rig.transcriber.cancelCalls)

        // When the recognizer has no final text, the last words heard are kept.
        rig.model.press()
        rig.transcriber.say("open a PR")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("open a PR"))
        rig.transcriber.finalText = ""
        val fallback = rig.model.release()
        assertEquals("open a PR", fallback)
    } }

    @Test fun dragLeftThenReleaseCancels() { runTest {
        val rig = makeRig()
        rig.model.press()
        rig.transcriber.say("xoá nhánh main")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("xoá nhánh main"))

        rig.model.drag(dx = -79.0, dy = 0.0)
        assertEquals(VoiceInputModel.Phase.Listening("xoá nhánh main"), rig.model.phase)
        rig.model.drag(dx = -80.0, dy = 0.0)
        assertEquals(VoiceInputModel.Phase.CancelArmed("xoá nhánh main"), rig.model.phase)
        // Back to the right: listening again.
        rig.model.drag(dx = -40.0, dy = 0.0)
        assertEquals(VoiceInputModel.Phase.Listening("xoá nhánh main"), rig.model.phase)
        rig.model.drag(dx = -120.0, dy = 10.0)
        assertEquals(VoiceInputModel.Phase.CancelArmed("xoá nhánh main"), rig.model.phase)

        val text = rig.model.release()
        assertNull(text)
        assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase)
        assertEquals(1, rig.transcriber.cancelCalls)
        assertEquals(0, rig.transcriber.finishCalls)
        assertFalse(rig.model.wantsKeyboard)
    } }

    // The hold gesture (MicHold)

    /** Does what the mic button does for a step of its hold; returns the words it would send. */
    private suspend fun perform(step: MicHold.Step, model: VoiceInputModel): String? = when (step) {
        MicHold.Step.PRESS -> {
            model.press()
            null
        }
        MicHold.Step.RELEASE -> model.release()
        MicHold.Step.CANCEL -> {
            model.drag(dx = -VoiceInputModel.CANCEL_DISTANCE, dy = 0.0)
            model.release()
        }
        MicHold.Step.NONE -> null
    }

    /** The workspace pager (or a scrolling list) takes the touch mid-dictation: the hold state is reset without a
     *  lift. Half-spoken words must not reach the agent. */
    @Test fun aHoldTakenAwayBeforeTheLiftSendsNothing() { runTest {
        val rig = makeRig()
        val hold = MicHold()
        val pressed = perform(hold.holdingChanged(true), rig.model)
        assertNull(pressed)
        rig.transcriber.say("xoá nhánh")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("xoá nhánh"))
        rig.transcriber.finalText = "xoá nhánh"

        // The state is reset, and no lift comes.
        val reset = hold.holdingChanged(false)
        val sentOnReset = perform(reset, rig.model)
        val settled = hold.settle()
        val sentOnSettle = perform(settled, rig.model)

        assertEquals(listOf(MicHold.Step.NONE, MicHold.Step.CANCEL), listOf(reset, settled), "only a lift sends")
        assertNull(sentOnReset ?: sentOnSettle, "nothing goes to the agent")
        assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase)
        assertEquals(0, rig.transcriber.finishCalls)
        assertEquals(1, rig.transcriber.cancelCalls, "the microphone is given back")
    } }

    /** The finger lifts: the lift sends, whichever of the two signals comes first, and the reset state that follows
     *  (or comes before) does nothing more. */
    @Test fun theLiftSendsOnceWhicheverSignalComesFirst() { runTest {
        for (endedFirst in listOf(true, false)) {
            val rig = makeRig()
            val hold = MicHold()
            perform(hold.holdingChanged(true), rig.model)
            rig.transcriber.say("chạy test")
            waitForPhase(rig.model, VoiceInputModel.Phase.Listening("chạy test"))
            rig.transcriber.finalText = "chạy test"

            val steps = mutableListOf<MicHold.Step>()
            val sent = mutableListOf<String>()
            // The mic settles on the next turn after the reset, so after both signals.
            for (signal in (if (endedFirst) listOf("ended", "reset") else listOf("reset", "ended")) + "settle") {
                val step = when (signal) {
                    "ended" -> hold.ended()
                    "reset" -> hold.holdingChanged(false)
                    else -> hold.settle()
                }
                steps += step
                perform(step, rig.model)?.let { sent += it }
            }

            assertEquals(listOf("chạy test"), sent, "ended first: $endedFirst, steps $steps")
            assertEquals(1, rig.transcriber.finishCalls)
        }
    } }

    @Test fun theHoldIgnoresSignalsWithoutAPress() {
        val hold = MicHold()
        assertEquals(MicHold.Step.NONE, hold.ended(), "a lift with no hold before it")
        assertEquals(MicHold.Step.NONE, hold.holdingChanged(false))
        assertEquals(MicHold.Step.NONE, hold.settle())
        assertEquals(MicHold.Step.PRESS, hold.holdingChanged(true))
        assertEquals(MicHold.Step.NONE, hold.holdingChanged(true), "already down")
    }

    @Test fun swipeUpBeforeWordsAsksKeyboard() { runTest {
        val rig = makeRig()
        rig.model.press()
        rig.model.drag(dx = 0.0, dy = -59.0)
        assertFalse(rig.model.wantsKeyboard)
        rig.model.drag(dx = 5.0, dy = -60.0)
        assertTrue(rig.model.wantsKeyboard)
        assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase)
        val cancelled = eventually { rig.transcriber.cancelCalls == 1 }
        assertTrue(cancelled, "listening stops")
        val text = rig.model.release()
        assertNull(text)

        // Once words came, a swipe up keeps listening.
        rig.model.wantsKeyboard = false
        rig.model.press()
        rig.transcriber.say("merge main")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("merge main"))
        rig.model.drag(dx = 0.0, dy = -200.0)
        assertFalse(rig.model.wantsKeyboard)
        assertEquals(VoiceInputModel.Phase.Listening("merge main"), rig.model.phase)
    } }

    @Test fun emptyTranscriptReturnsNil() { runTest {
        val rig = makeRig()
        rig.model.press()
        rig.transcriber.finalText = "  \n "
        val text = rig.model.release()
        assertNull(text)
        assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase)
        assertNull(rig.model.firstWordLatency)
    } }

    @Test fun deniedMicrophoneShowsDenied() { runTest {
        val rig = makeRig(microphone = false)
        rig.model.press()
        assertEquals(VoiceInputModel.Phase.Denied(VoicePermission.MICROPHONE), rig.model.phase)
        assertTrue(rig.transcriber.starts.isEmpty())
        val text = rig.model.release()
        assertNull(text)
        assertEquals(VoiceInputModel.Phase.Denied(VoicePermission.MICROPHONE), rig.model.phase, "the reason stays until the next press")

        val speech = makeRig(speech = false)
        speech.model.press()
        assertEquals(VoiceInputModel.Phase.Denied(VoicePermission.SPEECH), speech.model.phase)
        assertTrue(speech.transcriber.starts.isEmpty())
        assertEquals(1, speech.permissions.microphoneRequests)
        assertEquals(1, speech.permissions.speechRequests)

        // Granted later (in Settings): the next press listens.
        speech.permissions.speechGranted = true
        speech.model.press()
        assertEquals(VoiceInputModel.Phase.Listening(""), speech.model.phase)
        assertEquals(1, speech.transcriber.starts.size)
    } }

    @Test fun unavailableNeverBlocksKeyboard() { runTest {
        val rig = makeRig(capabilities = VoiceCapabilities.NONE)
        rig.model.press()
        assertEquals(VoiceInputModel.Phase.Unavailable, rig.model.phase)
        assertTrue(rig.model.wantsKeyboard, "the reason shows and the keyboard opens")
        assertTrue(rig.transcriber.starts.isEmpty())
        val text = rig.model.release()
        assertNull(text)

        // A recognizer that fails to start is unavailable too, never a stuck mic.
        val failing = makeRig()
        failing.transcriber.startError = IOException("offline")
        failing.model.press()
        assertEquals(VoiceInputModel.Phase.Unavailable, failing.model.phase)
        assertTrue(failing.model.wantsKeyboard)

        // So does one that fails before any word.
        val dropped = makeRig()
        dropped.model.press()
        dropped.transcriber.fail(IOException("offline"))
        waitForPhase(dropped.model, VoiceInputModel.Phase.Unavailable)
        assertTrue(dropped.model.wantsKeyboard)
        dropped.model.dismiss()
        assertEquals(VoiceInputModel.Phase.Idle, dropped.model.phase)
    } }

    @Test fun firstWordLatencyRecorded() { runTest {
        val rig = makeRig()
        rig.model.press()
        rig.clock += 40.milliseconds
        rig.transcriber.say(" ")
        // A blank update is not a word.
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening(" "))
        assertNull(rig.model.firstWordLatency)
        rig.clock += 140.milliseconds
        rig.transcriber.say("chạy")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("chạy"))
        assertEquals(180.milliseconds, rig.model.firstWordLatency)
        rig.clock += 500.milliseconds
        rig.transcriber.say("chạy test")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("chạy test"))
        assertEquals(180.milliseconds, rig.model.firstWordLatency, "only the first word counts")

        val summary = assertNotNull(rig.latency.summary(LatencyMetric.FIRST_WORD))
        assertEquals(1, summary.count)
        assertEquals(180.milliseconds, summary.p50)
        rig.model.release()

        // Each press measures again.
        rig.model.press()
        assertNull(rig.model.firstWordLatency)
        rig.clock += 90.milliseconds
        rig.transcriber.say("push")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("push"))
        assertEquals(90.milliseconds, rig.model.firstWordLatency)
        assertEquals(2, rig.latency.summary(LatencyMetric.FIRST_WORD)?.count)
    } }

    @Test fun dictationStopsAtByteLimit() { runTest {
        val rig = makeRig()
        rig.model.press()
        val start = "chạy test rồi push. ".repeat(600)
        assertTrue(start.utf8Size < ComposerValidation.MAX_BYTES)
        rig.transcriber.say(start)
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening(start))
        assertFalse(rig.model.limitReached)

        // Ten minutes of talking: far past 16 384 bytes, ending in multi-byte letters.
        val long = start + "giữ route v1, đừng xoá. ".repeat(600)
        rig.transcriber.say(long)
        val stopped = eventually { rig.model.limitReached }
        assertTrue(stopped)
        val cancelled = eventually { rig.transcriber.cancelCalls == 1 }
        assertTrue(cancelled, "listening stops at the limit")
        val kept = assertIs<VoiceInputModel.Phase.Listening>(rig.model.phase, "the kept words stay on screen").text
        assertTrue(kept.utf8Size <= ComposerValidation.MAX_BYTES)
        assertTrue(kept.utf8Size > ComposerValidation.MAX_BYTES - 4)
        assertTrue(long.startsWith(kept))
        assertFalse(rig.transcriber.isRunning, "nothing more is heard")

        val released = rig.model.release()
        val text = assertNotNull(released)
        assertEquals(kept.trim(), text)
        assertEquals(ComposerValidation.Ok(text), ComposerValidation.of(text), "the kept words can be sent")
        assertEquals(0, rig.transcriber.finishCalls)
        assertTrue(rig.model.limitReached, "the flag stays for the screen to say why")

        // A final text past a smaller limit (a question's answer) is cut the same way.
        val answer = makeRig(maxBytes = 1024)
        answer.model.press()
        answer.transcriber.finalText = "ệ".repeat(400)
        val answered = answer.model.release()
        val cut = assertNotNull(answered)
        assertEquals(1023, cut.utf8Size)
        assertTrue(answer.model.limitReached)
    } }

    @Test fun releaseWhileStartingStopsCleanly() { runTest {
        val rig = makeRig()
        rig.transcriber.holdStarts()
        val press = backgroundScope.launch { rig.model.press() }
        val held = eventually { rig.transcriber.startsWaiting == 1 }
        assertTrue(held)
        val text = rig.model.release()
        assertNull(text)
        assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase)
        rig.transcriber.releaseStarts()
        press.join()
        assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase, "the late start is not shown")
        val cancelled = eventually { rig.transcriber.cancelCalls == 1 }
        assertTrue(cancelled, "the recognizer that started late is stopped")
    } }

    @Test fun cancelStopsListeningWhenTheScreenGoes() { runTest {
        val rig = makeRig()
        rig.model.press()
        rig.transcriber.say("đang nói dở")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("đang nói dở"))
        rig.model.cancel()
        assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase)
        assertEquals(1, rig.transcriber.cancelCalls)
        assertFalse(rig.transcriber.isRunning)
        val text = rig.model.release()
        assertNull(text, "nothing is sent after the screen went away")

        // Nothing listening: nothing to stop.
        rig.model.cancel()
        assertEquals(1, rig.transcriber.cancelCalls)
    } }

    // The microphone is always released

    @Test fun streamEndingByItselfReleasesTheMic() { runTest {
        // A natural end (a recognizer's time limit): the words stay, the recognizer is stopped.
        val rig = makeRig()
        rig.model.press()
        val run = rig.transcriber.starts.lastOrNull()?.run
        rig.transcriber.say("sửa CI đỏ")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("sửa CI đỏ"))
        rig.transcriber.endStream()
        val released = eventually { rig.transcriber.cancelledRuns == listOfNotNull(run) }
        assertTrue(released, "the engine is cancelled, so it stops the microphone: ${rig.transcriber.cancelledRuns}")
        assertEquals(VoiceInputModel.Phase.Listening("sửa CI đỏ"), rig.model.phase, "the words stay until the finger lifts")
        val text = rig.model.release()
        assertEquals("sửa CI đỏ", text)
        assertEquals(0, rig.transcriber.finishCalls)

        // An error before any word: unavailable, and the microphone is released too.
        val failed = makeRig()
        failed.model.press()
        val failedRun = failed.transcriber.starts.lastOrNull()?.run
        failed.transcriber.fail(IOException("offline"))
        waitForPhase(failed.model, VoiceInputModel.Phase.Unavailable)
        val stopped = eventually { failed.transcriber.cancelledRuns == listOfNotNull(failedRun) }
        assertTrue(stopped)
    } }

    /** Android's recognizer ends a run at a silence (3E review A M-6): with nothing heard, nothing listens and nothing
     *  waits to be sent, so the mic is idle, not "Listening…", until the lift. */
    @Test fun aSilentStreamEndingByItselfShowsIdle() { runTest {
        val rig = makeRig()
        rig.model.press()
        val run = rig.transcriber.starts.lastOrNull()?.run
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening(""))
        rig.transcriber.endStream()
        val released = eventually { rig.transcriber.cancelledRuns == listOfNotNull(run) }
        assertTrue(released, "the microphone is given back: ${rig.transcriber.cancelledRuns}")
        assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase)
        assertFalse(rig.model.isActive)
        assertNull(rig.model.release())
        assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase)
        assertEquals(0, rig.transcriber.finishCalls)
    } }

    @Test fun typeInsteadCancelsTheDictation() { runTest {
        val rig = makeRig()
        rig.model.press()
        rig.transcriber.say("đang nói")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("đang nói"))
        rig.model.typeInstead()
        assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase)
        assertEquals(1, rig.transcriber.cancelCalls)
        assertFalse(rig.transcriber.isRunning)
        val text = rig.model.release()
        assertNull(text, "nothing heard before the keyboard opened is sent later")

        // Nothing listening: nothing to cancel; a "can't listen" notice is left for typing to clear.
        val denied = makeRig(microphone = false)
        denied.model.press()
        denied.model.typeInstead()
        assertEquals(0, denied.transcriber.cancelCalls)
        assertEquals(VoiceInputModel.Phase.Denied(VoicePermission.MICROPHONE), denied.model.phase)
    } }

    @Test fun lateStartCancelNeverStopsTheNextPress() { runTest {
        val rig = makeRig()
        rig.transcriber.holdStarts()
        // A quick tap: its start is still held when the finger lifts.
        val first = backgroundScope.launch { rig.model.press() }
        val firstHeld = eventually { rig.transcriber.startsWaiting == 1 }
        assertTrue(firstHeld)
        val none = rig.model.release()
        assertNull(none)
        // A hold right after: its start is held too.
        val second = backgroundScope.launch { rig.model.press() }
        val secondHeld = eventually { rig.transcriber.startsWaiting == 2 }
        assertTrue(secondHeld)
        rig.transcriber.releaseStarts()
        first.join()
        second.join()

        val runs = rig.transcriber.starts.map { it.run }
        assertEquals(2, runs.size)
        assertEquals(listOf(runs[0]), rig.transcriber.cancelledRuns, "only the tap's run is stopped")
        rig.transcriber.say("tạo PR")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("tạo PR"))
        rig.transcriber.finalText = "Tạo PR."
        val text = rig.model.release()
        assertEquals("Tạo PR.", text)
    } }

    @Test fun startReleasedWhileStartingNeverTakesTheMic() { runTest {
        val rig = makeRig()
        rig.transcriber.holdStarts()
        val press = backgroundScope.launch { rig.model.press() }
        val held = eventually { rig.transcriber.startsWaiting == 1 }
        assertTrue(held)
        val run = rig.transcriber.starts[0].run
        val none = rig.model.release()
        assertNull(none)
        assertEquals(listOf(run), rig.transcriber.cancelledRuns, "the release cancels the run while it still starts")

        rig.transcriber.releaseStarts()
        press.join()
        assertFalse(run in rig.transcriber.grantedRuns, "it never took the microphone, not even briefly")
        assertNull(rig.transcriber.activeRun)
        assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase)
    } }

    @Test fun staleStartFinishingSecondNeverTakesTheMic() { runTest {
        val rig = makeRig()
        rig.transcriber.holdStarts()
        // A quick tap, released while its start is held.
        val tap = backgroundScope.launch { rig.model.press() }
        val tapHeld = eventually { rig.transcriber.startsWaiting == 1 }
        assertTrue(tapHeld)
        rig.model.release()
        // A hold right after.
        val hold = backgroundScope.launch { rig.model.press() }
        val holdHeld = eventually { rig.transcriber.startsWaiting == 2 }
        assertTrue(holdHeld)
        val runs = rig.transcriber.starts.map { it.run }

        // The newer start finishes first, the stale one second.
        rig.transcriber.releaseStart(runs[1])
        hold.join()
        assertEquals(runs[1], rig.transcriber.activeRun)
        rig.transcriber.releaseStart(runs[0])
        tap.join()

        assertEquals(listOf(runs[1]), rig.transcriber.grantedRuns, "the stale start never took the microphone")
        assertEquals(runs[1], rig.transcriber.activeRun, "and never tore down the newer run")
        assertTrue(rig.transcriber.isRunning)
        rig.transcriber.say("tạo PR")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("tạo PR"))
        rig.transcriber.finalText = "Tạo PR."
        val text = rig.model.release()
        assertEquals("Tạo PR.", text)
    } }

    @Test fun noFirstWordSampleAfterAPermissionPrompt() { runTest {
        val rig = makeRig()
        rig.permissions.promptPending = true
        rig.model.press()
        rig.clock += 4.seconds
        rig.transcriber.say("chạy")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("chạy"))
        assertNull(rig.model.firstWordLatency, "the prompt's time is not speech latency")
        assertNull(rig.latency.summary(LatencyMetric.FIRST_WORD))
        rig.model.release()

        // The next press, with nothing to ask, is measured.
        rig.permissions.promptPending = false
        rig.model.press()
        rig.clock += 120.milliseconds
        rig.transcriber.say("push")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("push"))
        assertEquals(120.milliseconds, rig.model.firstWordLatency)
        assertEquals(1, rig.latency.summary(LatencyMetric.FIRST_WORD)?.count)
    } }

    @Test fun limitCutDictationIsForReviewNotSending() { runTest {
        val rig = makeRig(maxBytes = 64)
        rig.model.press()
        rig.transcriber.say("chạy test")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("chạy test"))
        val first = rig.model.release()
        val whole = assertNotNull(first)
        assertEquals(DictationOutcome.Complete("chạy test"), rig.model.outcome(whole))

        rig.model.press()
        rig.transcriber.say("giữ route v1 ".repeat(10))
        val stopped = eventually { rig.model.limitReached }
        assertTrue(stopped)
        val second = rig.model.release()
        val cut = assertNotNull(second)
        assertEquals(DictationOutcome.CutAtLimit(cut), rig.model.outcome(cut), "read it in the field first; no success haptic")
    } }

    @Test fun contextualStringsAddTermsToWorkspaces() {
        val strings = VoiceInputModel.contextualStrings(listOf("shellx", "web", "shellx", " ", "PR"))
        assertEquals(listOf("shellx", "web"), strings.take(2))
        for (term in listOf("PR", "CI", "push", "pull request", "branch", "merge", "deploy", "commit", "Claude")) {
            assertEquals(1, strings.count { it == term }, term)
        }
        assertEquals(11, strings.size)
    }

    /** Android only: a screen's coroutine can be cancelled while the recognizer finishes (the iPhone never cancels a
     *  view's Task). The dictation still ends, so the mic is never stuck in "finishing" and the next press listens. */
    @Test fun aCancelledReleaseStillEndsTheDictation() { runTest {
        val gate = Gate()
        val rig = makeRig(engine = { base ->
            object : SpeechEngine by base {
                override suspend fun finish(run: SpeechRunId): String {
                    gate.wait()
                    return base.finish(run)
                }
            }
        })
        rig.model.press()
        rig.transcriber.say("chạy test")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("chạy test"))
        val release = backgroundScope.async { rig.model.release() }
        runCurrent()
        assertEquals(VoiceInputModel.Phase.Finishing, rig.model.phase)

        release.cancel()
        runCurrent()
        val released = release.isCompleted
        gate.open()
        runCurrent()
        assertTrue(released, "the caller's wait ends at once")
        assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase, "the dictation still ends")
        assertNull(rig.transcriber.activeRun, "the microphone is given back")
        rig.model.press()
        assertEquals(VoiceInputModel.Phase.Listening(""), rig.model.phase, "the next press listens")
        assertEquals(2, rig.transcriber.starts.size)
    } }

    /** An engine whose `cancel` waits at [gate], then hops once (a recognizer's teardown on the main thread), before it
     *  tears the run down. */
    private class GatedCancel(private val base: FakeTranscriber, private val gate: Gate) : SpeechEngine by base {
        override suspend fun cancel(run: SpeechRunId) {
            gate.wait()
            yield()
            base.cancel(run)
        }
    }

    /** Android only (review 4 I-1): the caller of `cancel()`, `typeInstead()` or a release can be cancelled while the
     *  recognizer tears down (a `pointerInput` restart, the screen leaving). The mic still goes back: never a live
     *  recognizer behind an idle mic. */
    @Test fun aCancelledCancelStillGivesTheMicBack() { runTest {
        for (path in listOf("cancel", "armed release", "release while starting")) {
            val gate = Gate()
            val rig = makeRig(engine = { GatedCancel(it, gate) })
            val press = backgroundScope.launch { rig.model.press() }
            if (path == "release while starting") {
                rig.transcriber.holdStarts()
            }
            runCurrent()
            if (path == "release while starting") {
                assertEquals(1, rig.transcriber.startsWaiting, path)
            } else {
                rig.transcriber.say("xoá nhánh")
                waitForPhase(rig.model, VoiceInputModel.Phase.Listening("xoá nhánh"))
            }
            val call = backgroundScope.async {
                when (path) {
                    "cancel" -> rig.model.cancel()
                    "armed release" -> {
                        rig.model.drag(dx = -100.0, dy = 0.0)
                        rig.model.release()
                    }
                    else -> rig.model.release()
                }
            }
            runCurrent()
            assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase, path)
            call.cancel()
            runCurrent()
            gate.open()
            runCurrent()
            rig.transcriber.releaseStarts()
            press.join()
            runCurrent()
            assertNull(rig.transcriber.activeRun, "$path: the mic is given back")
            assertFalse(rig.transcriber.isRunning, path)
        }
    } }

    /** Review 4 M-1: an engine whose finish or cancel throws never leaves the mic stuck, never crashes the model's
     *  scope, and is logged by code only. */
    @Test fun aFailingEngineNeverLeavesTheMicStuck() { runTest {
        val lines = mutableListOf<String>()
        CoreLog.sink = { synchronized(lines) { lines += it } }
        try {
            val finishing = makeRig(engine = { base ->
                object : SpeechEngine by base {
                    override suspend fun finish(run: SpeechRunId): String = throw IOException("offline")
                }
            })
            finishing.model.press()
            finishing.transcriber.say("chạy test")
            waitForPhase(finishing.model, VoiceInputModel.Phase.Listening("chạy test"))
            assertEquals("chạy test", finishing.model.release(), "the words heard are kept")
            assertEquals(VoiceInputModel.Phase.Idle, finishing.model.phase)
            assertFalse(finishing.model.isActive)
            assertNull(finishing.transcriber.activeRun, "the mic is given back")
            finishing.model.press()
            assertEquals(VoiceInputModel.Phase.Listening(""), finishing.model.phase, "the next press listens")

            val cancelling = makeRig(engine = { base ->
                object : SpeechEngine by base {
                    override suspend fun cancel(run: SpeechRunId): Unit = throw IOException("offline")
                }
            })
            cancelling.model.press()
            cancelling.transcriber.say("xoá nhánh")
            waitForPhase(cancelling.model, VoiceInputModel.Phase.Listening("xoá nhánh"))
            cancelling.model.cancel()
            assertEquals(VoiceInputModel.Phase.Idle, cancelling.model.phase)
            // The swipe up's cancel runs in the model's scope: its failure must not reach the scope.
            cancelling.model.press()
            cancelling.model.drag(dx = 0.0, dy = -60.0)
            runCurrent()
            assertTrue(cancelling.model.wantsKeyboard)
            assertEquals(VoiceInputModel.Phase.Idle, cancelling.model.phase)
        } finally {
            CoreLog.sink = {}
        }
        val codes = synchronized(lines) { lines.filter { it.startsWith("voice_") } }
        assertEquals(listOf("voice_finish_failed", "voice_cancel_failed", "voice_cancel_failed"), codes)
    } }

    /** Review 4 M-2: a press whose caller is cancelled while the recognizer starts (after it took the mic) is
     *  dropped, and its run gives the mic back: no run holds the mic with nobody reading it. */
    @Test fun aPressCancelledWhileStartingGivesTheMicBack() { runTest {
        var starts = 0
        val rig = makeRig(engine = { base ->
            object : SpeechEngine by base {
                override suspend fun start(run: SpeechRunId, language: VoiceLanguage, contextualStrings: List<String>): ReceiveChannel<String> {
                    val channel = base.start(run, language, contextualStrings)
                    starts += 1
                    if (starts == 1) awaitCancellation()      // the mic is taken; the start's last step never ends
                    return channel
                }
            }
        })
        val press = backgroundScope.launch { rig.model.press() }
        assertTrue(eventually { rig.transcriber.activeRun != null })
        press.cancel()
        press.join()
        runCurrent()
        assertNull(rig.transcriber.activeRun, "the mic is given back")
        assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase)
        assertFalse(rig.model.isActive)

        rig.model.press()
        assertEquals(VoiceInputModel.Phase.Listening(""), rig.model.phase, "the next press listens")
        assertEquals(2, rig.transcriber.starts.size)
    } }

    /** Final review I-1: the model's scope is hub.scope, which a refused token (401), a sign-out, a deletion or the
     *  demo's Exit cancels while the user may hold the mic. The mic is given back once, even by an engine whose cancel
     *  suspends, the mic shows idle, and the screen's later calls never throw into a caller that was not cancelled. */
    @Test fun aScopeThatEndsWhileListeningGivesTheMicBack() { runTest {
        val hub = hubScope()
        val rig = makeRig(scope = hub, engine = { HoppingCancel(it) })
        rig.model.press()
        val run = rig.transcriber.starts.last().run
        rig.transcriber.say("đang nói")
        waitForPhase(rig.model, VoiceInputModel.Phase.Listening("đang nói"))

        hub.cancel()
        runCurrent()
        assertEquals(listOf(run), rig.transcriber.cancelledRuns, "the mic is given back when the scope ends")
        assertNull(rig.transcriber.activeRun)
        assertFalse(rig.transcriber.isRunning)
        assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase, "the mic shows idle")

        // The hub is null now, so the screen goes; its calls end normally.
        assertNull(runCatching { rig.model.cancel() }.exceptionOrNull(), "cancel() never throws into a live caller")
        assertNull(runCatching { rig.model.release() }.getOrThrow(), "nothing is sent")
        assertEquals(listOf(run), rig.transcriber.cancelledRuns, "given back once")
    } }

    /** Final review I-1: the scope ends while a press still starts. The start then ends by itself, or the screen
     *  cancels first: either way the run never keeps the mic, the mic shows idle, and nothing throws. */
    @Test fun aScopeThatEndsWhileStartingGivesTheMicBack() { runTest {
        for (path in listOf("start ends", "screen cancels")) {
            val hub = hubScope()
            val rig = makeRig(scope = hub, engine = { HoppingCancel(it) })
            rig.transcriber.holdStarts()
            val press = backgroundScope.launch { rig.model.press() }
            assertTrue(eventually { rig.transcriber.startsWaiting == 1 }, path)
            val run = rig.transcriber.starts.last().run

            hub.cancel()
            runCurrent()
            if (path == "screen cancels") {
                assertNull(runCatching { rig.model.cancel() }.exceptionOrNull(), "$path: cancel() never throws")
                assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase, path)
            }
            rig.transcriber.releaseStarts()
            press.join()
            runCurrent()
            assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase, path)
            assertFalse(rig.model.isActive, path)
            assertNull(rig.transcriber.activeRun, "$path: the mic is given back")
            assertFalse(rig.transcriber.isRunning, path)
            assertEquals(listOf(run), rig.transcriber.cancelledRuns, path)
        }
    } }

    /** Final review I-3: a quick tap while the on-device recognizer claimed the mic but is not ready yet (3E's
     *  engine). The release cancels the run, and the recognizer's start then fails. The run never falls back to the
     *  standard recognizer, which would take the mic with nobody reading it; the on-device one stays offered for the
     *  language; and the tap shows nothing. */
    @Test fun aQuickTapOnARecognizerNotYetReadyNeverFallsBack() { runTest {
        val slot = SpeechRunSlot()
        val primary = NotReadyPrimary(slot)
        var primaryFailed = 0
        val rig = makeRig(slot = slot, engine = { fallback ->
            FallbackTranscriber(slot, primary, fallback, usePrimary = { true }, primaryFailed = { primaryFailed += 1 })
        })
        val pressing = backgroundScope.async { rig.model.press() }
        assertTrue(eventually { slot.active != null }, "the on-device recognizer claimed the mic")
        assertNull(rig.model.release(), "the finger lifted while it started")

        primary.failReady()
        pressing.await()
        runCurrent()
        assertTrue(rig.transcriber.grantedRuns.isEmpty(), "the cancelled run never takes the mic on the fallback")
        assertNull(slot.active)
        assertFalse(rig.transcriber.isRunning)
        assertEquals(0, primaryFailed, "the on-device recognizer stays offered")
        assertEquals(VoiceInputModel.Phase.Idle, rig.model.phase, "the tap shows nothing")
        assertFalse(rig.model.wantsKeyboard)
    } }
}
