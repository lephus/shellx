package com.shellx.core.voice

import com.shellx.core.testing.FakeTranscriber
import com.shellx.core.testing.eventually
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest

/** The on-device recognizer first when it can run the language, the standard one otherwise. Only an error of the
 *  primary recognizer itself makes a press fall back and stops offering it for that language; a passing audio error
 *  (the microphone is busy during a call, no input) fails that press and keeps the primary for the next one, so a
 *  language never moves to the speech service for nothing. */
class FallbackTranscriberTest {
    /** Records which languages the primary was given up for. */
    private class Failures {
        private val list = mutableListOf<VoiceLanguage>()
        val languages: List<VoiceLanguage> get() = synchronized(this) { list.toList() }
        fun add(language: VoiceLanguage) {
            synchronized(this) { list += language }
        }
    }

    private class Rig(
        val router: FallbackTranscriber,
        val analyzer: FakeTranscriber,
        val legacy: FakeTranscriber,
        val failures: Failures,
    )

    private fun makeRig(analyzerReady: Boolean = true): Rig {
        val slot = SpeechRunSlot()
        val analyzer = FakeTranscriber(slot)
        val legacy = FakeTranscriber(slot)
        val failures = Failures()
        val router = FallbackTranscriber(
            slot, primary = analyzer, fallback = legacy, usePrimary = { analyzerReady },
            primaryFailed = { failures.add(it) },
        )
        return Rig(router, analyzer, legacy, failures)
    }

    /** Holds the first `usePrimary` question until opened; later ones pass at once. */
    private class FirstCallGate {
        private var calls = 0
        private var isOpen = false
        private var held: CompletableDeferred<Unit>? = null

        val waiting: Boolean get() = synchronized(this) { held != null }

        suspend fun pass(): Boolean {
            val wait = synchronized(this) {
                calls += 1
                if (calls == 1 && !isOpen) CompletableDeferred<Unit>().also { held = it } else null
            }
            wait?.await()
            return true
        }

        fun open() {
            val continuation = synchronized(this) {
                isOpen = true
                held.also { held = null }
            }
            continuation?.complete(Unit)
        }
    }

    @Test fun staleStartHeldInReadinessNeverBlocksTheNewerPress() { runTest {
        val slot = SpeechRunSlot()
        val analyzer = FakeTranscriber(slot)
        val gate = FirstCallGate()
        val router = FallbackTranscriber(
            slot, primary = analyzer, fallback = FakeTranscriber(slot), usePrimary = { gate.pass() },
            primaryFailed = {},
        )
        val stale = SpeechRunId()
        val newer = SpeechRunId()

        // A quick tap: its readiness question is held, and the press is released meanwhile.
        val language = VoiceLanguage.VIETNAMESE
        val tap = backgroundScope.async { router.start(stale, language, emptyList()) }
        assertTrue(eventually { gate.waiting })
        router.cancel(stale)
        // The hold right after: its start is held inside the primary.
        analyzer.holdStarts()
        val hold = backgroundScope.async { router.start(newer, language, emptyList()) }
        assertTrue(eventually { analyzer.startsWaiting == 1 })
        // Only now does the stale press get past its readiness question and begin inside.
        gate.open()
        assertTrue(eventually { analyzer.startsWaiting == 2 })
        analyzer.releaseStart(stale)
        tap.await()
        analyzer.releaseStart(newer)
        hold.await()

        assertEquals(listOf(newer), analyzer.grantedRuns, "the newer press gets the microphone")
        assertEquals(newer, slot.active)
    } }

    @Test fun analyzerErrorFallsBackAndStopsOfferingIt() { runTest {
        val rig = makeRig()
        rig.analyzer.startError = SpeechStartException.Recognizer(IOException("offline"))
        val run = SpeechRunId()
        rig.router.start(run, VoiceLanguage.VIETNAMESE, emptyList())
        assertEquals(listOf(VoiceLanguage.VIETNAMESE), rig.failures.languages, "the primary is given up for vi-VN")
        assertEquals(listOf(run), rig.legacy.starts.map { it.run }, "this press goes through the fallback")
        assertEquals(run, rig.legacy.activeRun)
    } }

    @Test fun audioErrorNeverDisablesTheAnalyzer() { runTest {
        val rig = makeRig()
        rig.analyzer.startError = SpeechStartException.Audio(IOException("offline"))
        val failure = runCatching { rig.router.start(SpeechRunId(), VoiceLanguage.VIETNAMESE, emptyList()) }
        assertIs<SpeechStartException.Audio>(failure.exceptionOrNull(), "an audio error fails the press")
        assertTrue(rig.failures.languages.isEmpty(), "a passing audio error keeps the primary")
        assertTrue(rig.legacy.starts.isEmpty(), "and does not send the voice to the fallback")

        // The next press tries the primary again.
        rig.analyzer.startError = null
        val next = SpeechRunId()
        rig.router.start(next, VoiceLanguage.VIETNAMESE, emptyList())
        assertEquals(listOf(next), rig.analyzer.grantedRuns)
    } }

    @Test fun notReadyGoesStraightToTheFallback() { runTest {
        val rig = makeRig(analyzerReady = false)
        val run = SpeechRunId()
        rig.router.start(run, VoiceLanguage.VIETNAMESE, emptyList())
        assertTrue(rig.analyzer.starts.isEmpty())
        assertEquals(listOf(run), rig.legacy.grantedRuns)
        assertTrue(rig.failures.languages.isEmpty())
    } }

    @Test fun finishAndCancelReachTheRunsTranscriber() { runTest {
        val rig = makeRig(analyzerReady = false)
        val run = SpeechRunId()
        rig.router.start(run, VoiceLanguage.VIETNAMESE, emptyList())
        rig.legacy.say("merge main")
        rig.legacy.finalText = "Merge main."
        val text = rig.router.finish(run)
        assertEquals("Merge main.", text)
        assertNull(rig.legacy.activeRun, "finishing gave the microphone back")

        val other = SpeechRunId()
        rig.router.start(other, VoiceLanguage.VIETNAMESE, emptyList())
        rig.router.cancel(other)
        assertNull(rig.legacy.activeRun)
        assertFalse(rig.legacy.isRunning)
    } }

    @Test fun finishReachesTheRunHoldingTheMicWhateverCameBetween() { runTest {
        // One run holds the microphone while many presses that were cancelled while starting come and go; finishing
        // it must still give the microphone back.
        val rig = makeRig(analyzerReady = false)
        val live = SpeechRunId()
        rig.router.start(live, VoiceLanguage.VIETNAMESE, emptyList())
        repeat(40) {
            val tap = SpeechRunId()
            rig.router.cancel(tap)
            rig.router.start(tap, VoiceLanguage.VIETNAMESE, emptyList())
        }
        assertEquals(live, rig.legacy.activeRun)
        rig.legacy.say("chạy test")
        rig.legacy.finalText = "Chạy test."
        val text = rig.router.finish(live)
        assertEquals("Chạy test.", text)
        assertNull(rig.legacy.activeRun, "nothing is left holding the microphone")
    } }
}
