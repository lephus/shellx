@file:OptIn(ExperimentalCoroutinesApi::class)

package com.shellx.app.voice

import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.voice.SpeechRunId
import com.shellx.core.voice.SpeechRunSlot
import com.shellx.core.voice.SpeechStartException
import com.shellx.core.voice.VoiceLanguage
import java.io.IOException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** One platform recognizer the test drives: each listener callback is called on the test's thread, as the platform
 *  calls it on the main thread. */
private class FakePort : RecognizerPort {
    val intents = mutableListOf<Intent>()
    var listener: RecognitionListener? = null
    var stops = 0
    var cancels = 0
    var destroyed = false

    override fun start(intent: Intent, listener: RecognitionListener) {
        intents += intent
        this.listener = listener
    }

    override fun stop() {
        stops++
    }

    override fun cancel() {
        cancels++
    }

    override fun destroy() {
        destroyed = true
    }

    fun ready() = listener!!.onReadyForSpeech(Bundle())

    fun partial(t: String) = listener!!.onPartialResults(bundle(t))

    fun results(t: String) = listener!!.onResults(bundle(t))

    fun error(code: Int) = listener!!.onError(code)

    private fun bundle(t: String) = Bundle().apply { putStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION, arrayListOf(t)) }
}

@RunWith(AndroidJUnit4::class)
class SpeechRecognizerEngineTest {
    private val ports = mutableListOf<FakePort>()

    private fun TestScope.engine(
        kind: RecognizerKind = RecognizerKind.STANDARD,
        slot: SpeechRunSlot = SpeechRunSlot(),
        meter: AudioLevelMeter = AudioLevelMeter(),
    ) = SpeechRecognizerEngine(
        kind, slot, { FakePort().also { ports += it } }, meter, RecognizerIntents("com.shellx.dev", 33),
        StandardTestDispatcher(testScheduler),
    )

    private suspend fun TestScope.listening(e: SpeechRecognizerEngine, run: SpeechRunId, strings: List<String> = emptyList()): ReceiveChannel<String> {
        val started = async { e.start(run, VoiceLanguage.VIETNAMESE, strings) }
        runCurrent()
        assertFalse(started.isCompleted)
        ports.last().ready()
        return started.await()
    }

    @Test
    fun aRunWaitsForTheRecognizerAndSendsTheWholeText() {
        runTest {
            val e = engine()
            val words = listening(e, SpeechRunId(), listOf("shellx", "PR"))
            ports[0].partial("chạy")
            assertEquals("chạy", words.receive())
            ports[0].partial("chạy test")
            assertEquals("chạy test", words.receive())
            val intent = ports[0].intents.single()
            assertEquals("vi-VN", intent.getStringExtra(RecognizerIntent.EXTRA_LANGUAGE))
            assertTrue(intent.getBooleanExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false))
            assertEquals(1, intent.getIntExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 0))
            assertEquals(arrayListOf("shellx", "PR"), intent.getStringArrayListExtra(RecognizerIntent.EXTRA_BIASING_STRINGS))
        }
    }

    /** RF 5. */
    @Test
    fun aPauseWhileHeldKeepsListeningAndTheWords() {
        runTest {
            val e = engine()
            val run = SpeechRunId()
            val words = listening(e, run)
            ports[0].partial("chạy test")
            ports[0].results("chạy test")
            assertEquals("listening again, same recognizer", 2, ports[0].intents.size)
            ports[0].partial("rồi tạo PR")
            assertEquals("chạy test rồi tạo PR", words.receive())
            val finished = async { e.finish(run) }
            runCurrent()
            assertEquals(1, ports[0].stops)
            ports[0].results("rồi tạo PR")
            assertEquals("chạy test rồi tạo PR", finished.await())
            assertTrue(ports[0].destroyed)
        }
    }

    /** RF 5. */
    @Test
    fun silenceAfterWordsEndsTheRunKeepingThem() {
        runTest {
            val slot = SpeechRunSlot()
            val e = engine(slot = slot)
            val words = listening(e, SpeechRunId())
            ports[0].partial("xin chào")
            ports[0].error(SpeechRecognizer.ERROR_SPEECH_TIMEOUT)
            assertEquals("xin chào", words.receive())
            assertNull(words.receiveCatching().exceptionOrNull())
            assertTrue(words.isClosedForReceive)
            assertEquals(1, ports[0].intents.size)
            assertTrue(ports[0].destroyed)
            assertNull(slot.active)
        }
    }

    @Test
    fun aNetworkErrorBeforeAnyWordEndsTheRunWithIt() {
        runTest {
            val e = engine()
            val words = listening(e, SpeechRunId())
            ports[0].error(SpeechRecognizer.ERROR_NETWORK)
            assertTrue(words.receiveCatching().exceptionOrNull() is IOException)
        }
    }

    @Test
    fun finishWaitsForTheFinalResultAtMostItsTimeout() {
        runTest {
            for ((kind, ms) in listOf(RecognizerKind.STANDARD to 1_500L, RecognizerKind.ON_DEVICE to 2_000L)) {
                val e = engine(kind)
                val run = SpeechRunId()
                listening(e, run)
                ports.last().partial("gần xong")
                val finished = async { e.finish(run) }
                advanceTimeBy(ms - 1)
                runCurrent()
                assertFalse("$kind", finished.isCompleted)
                advanceTimeBy(2)
                runCurrent()
                assertEquals("gần xong", finished.await())
                assertEquals(1, ports.last().cancels)
            }
        }
    }

    @Test
    fun startErrorsSayWhoseFaultTheyWere() {
        runTest {
            for ((code, recognizer) in listOf(12 to true, 13 to true, 5 to true, 8 to true, 4 to true, 2 to true, 3 to false, 9 to false)) {
                val e = engine()
                val started = async { runCatching { e.start(SpeechRunId(), VoiceLanguage.ENGLISH, emptyList()) } }
                runCurrent()
                ports.last().error(code)
                val error = started.await().exceptionOrNull()
                assertTrue("$code", if (recognizer) error is SpeechStartException.Recognizer else error is SpeechStartException.Audio)
                assertTrue(ports.last().destroyed)
            }
            val none = SpeechRecognizerEngine(
                RecognizerKind.ON_DEVICE, SpeechRunSlot(), { null }, AudioLevelMeter(), RecognizerIntents("p", 33),
                StandardTestDispatcher(testScheduler),
            )
            assertTrue(
                runCatching { none.start(SpeechRunId(), VoiceLanguage.ENGLISH, emptyList()) }.exceptionOrNull() is SpeechStartException.Recognizer,
            )
            val slow = engine()
            val started = async { runCatching { slow.start(SpeechRunId(), VoiceLanguage.ENGLISH, emptyList()) } }
            advanceTimeBy(3_001)
            runCurrent()
            assertTrue(started.await().exceptionOrNull() is SpeechStartException.Recognizer)
        }
    }

    @Test
    fun aNewerRunTearsDownTheOlderRecognizer() {
        runTest {
            val slot = SpeechRunSlot()
            val e = engine(slot = slot)
            val old = listening(e, SpeechRunId())
            val newer = SpeechRunId()
            listening(e, newer)
            assertEquals(1, ports[0].cancels)
            assertTrue(ports[0].destroyed)
            assertTrue(old.isClosedForReceive)
            assertEquals(newer, slot.active)
            assertFalse(ports[1].destroyed)
        }
    }

    @Test
    fun levelsReachTheMeterAndDropAtTheEnd() {
        runTest {
            val meter = AudioLevelMeter()
            val e = engine(meter = meter)
            val run = SpeechRunId()
            listening(e, run)
            ports[0].listener!!.onRmsChanged(10f)
            assertEquals(1f, meter.level.value, 0f)
            ports[0].listener!!.onRmsChanged(4f)
            assertEquals(0.5f, meter.level.value, 0.001f)
            e.cancel(run)
            runCurrent()
            assertEquals(0f, meter.level.value, 0f)
            assertTrue(ports[0].destroyed)
        }
    }

    /** 3C final review, consumer fit 11: a cancel while the recognizer starts ends the start at once, and the
     *  microphone goes back (the start never waits out READY_TIMEOUT). */
    @Test
    fun aCancelWhileTheRecognizerStartsGivesTheMicrophoneBack() {
        runTest {
            val slot = SpeechRunSlot()
            val e = engine(slot = slot)
            val run = SpeechRunId()
            val started = async { e.start(run, VoiceLanguage.VIETNAMESE, emptyList()) }
            runCurrent()
            assertFalse(started.isCompleted)
            e.cancel(run)
            runCurrent()
            assertTrue(started.isCompleted)
            assertTrue(started.await().isClosedForReceive)
            assertTrue(ports[0].destroyed)
            assertNull(slot.active)
        }
    }

    /** Consumer fit 12: a finish whose caller is cancelled while it waits for the final result still tears the
     *  recognizer down. */
    @Test
    fun aFinishWhoseCallerIsCancelledStillGivesTheMicrophoneBack() {
        runTest {
            val e = engine()
            val run = SpeechRunId()
            listening(e, run)
            val finishing = launch { e.finish(run) }
            runCurrent()
            assertEquals(1, ports[0].stops)
            finishing.cancel()
            runCurrent()
            assertTrue(ports[0].destroyed)
        }
    }

    /** An error right after the recognizer said it is ready ends the dictation with it: it no longer fails the start,
     *  and the run never listens on a recognizer that stopped. */
    @Test
    fun anErrorRightAfterReadyEndsTheDictation() {
        runTest {
            val e = engine()
            val started = async { e.start(SpeechRunId(), VoiceLanguage.ENGLISH, emptyList()) }
            runCurrent()
            ports[0].ready()
            ports[0].error(SpeechRecognizer.ERROR_NETWORK)
            val words = started.await()
            assertTrue(words.receiveCatching().exceptionOrNull() is IOException)
            assertTrue(ports[0].destroyed)
        }
    }

    @Test
    fun belowApi33TheIntentHasNoBias() {
        val intent = RecognizerIntents("p", sdkInt = 32).of(VoiceLanguage.ENGLISH, listOf("PR"), preferOffline = true)
        assertNull(intent.getStringArrayListExtra(RecognizerIntent.EXTRA_BIASING_STRINGS))
        assertTrue(intent.getBooleanExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, false))
        assertEquals("en-US", intent.getStringExtra(RecognizerIntent.EXTRA_LANGUAGE))
    }
}
