package com.shellx.core.voice

import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.pending.QuestionDraft
import com.shellx.core.platform.MemoryKeyValueStore
import com.shellx.core.testing.FakeTranscriber
import com.shellx.core.testing.FakeVoicePermissions
import com.shellx.core.testing.eventually
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.TestTimeSource
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest

/** The voice service the screens share: it stops every mic at once (an audio interruption, a lost input, the app
 *  going to the background), and when the primary recognizer falls back, Settings names the path presses really
 *  take. */
class VoiceServiceTest {
    /** Answers with what the test sets. */
    private class Asker(private var answer: VoiceCapabilities) {
        fun set(answer: VoiceCapabilities) {
            synchronized(this) { this.answer = answer }
        }

        fun ask(): VoiceCapabilities = synchronized(this) { answer }
    }

    private companion object {
        val RECOGNIZER = VoiceCapabilities(onDeviceRecognizer = true, standardOnDevice = false, standardAvailable = true)
        val SERVER = VoiceCapabilities(onDeviceRecognizer = false, standardOnDevice = false, standardAvailable = true)
    }

    private fun TestScope.makeService(transcriber: FakeTranscriber, asker: Asker): VoiceService {
        val settings = MemoryKeyValueStore()
        VoiceLanguage.VIETNAMESE.save(settings)
        val clock = TestTimeSource()
        return VoiceService(
            transcriber, FakeVoicePermissions(), VoiceCapabilityCache(timeSource = clock) { asker.ask() }, LatencyLog(),
            settings, backgroundScope, clock, preferredLanguages = emptyList(), contextualStrings = { emptyList() },
        )
    }

    @Test fun cancelAllStopsEveryListeningMic() { runTest {
        val transcriber = FakeTranscriber()
        val service = makeService(transcriber, Asker(SERVER))
        val composer = service.makeModel()
        val sheet = service.makeModel(maxBytes = QuestionDraft.MAX_ANSWER_BYTES)
        val idle = service.makeModel()

        composer.press()
        transcriber.say("đang nói")
        val heard = eventually { composer.phase == VoiceInputModel.Phase.Listening("đang nói") }
        assertTrue(heard)
        // One microphone: the sheet's press takes it over, as the real recognizers do.
        sheet.press()
        val runs = transcriber.starts.map { it.run }
        assertEquals(runs[1], transcriber.activeRun)
        val handedOver = eventually { runs[0] in transcriber.cancelledRuns }
        assertTrue(handedOver, "the composer's model let go of its run once it ended")

        service.cancelAll()
        assertEquals(VoiceInputModel.Phase.Idle, composer.phase)
        assertEquals(VoiceInputModel.Phase.Idle, sheet.phase)
        assertEquals(VoiceInputModel.Phase.Idle, idle.phase)
        assertNull(transcriber.activeRun, "nothing holds the microphone")
        assertEquals(runs.toSet(), transcriber.cancelledRuns.toSet(), "both runs stopped")
        val words = composer.release()
        assertNull(words, "nothing heard before the interruption is sent afterwards")
    } }

    /** The workspace pager stops paging while any mic listens, so the mic's drag to cancel stays the mic's. */
    @Test fun isListeningWhileAnyMicIsActive() { runTest {
        val transcriber = FakeTranscriber()
        val service = makeService(transcriber, Asker(SERVER))
        assertFalse(service.isListening, "no mic yet")
        val composer = service.makeModel()
        service.makeModel()
        assertFalse(service.isListening)

        composer.press()
        assertTrue(service.isListening)
        transcriber.say("đang nói")
        val heard = eventually { composer.phase == VoiceInputModel.Phase.Listening("đang nói") }
        assertTrue(heard)
        assertTrue(service.isListening)

        composer.release()
        assertFalse(service.isListening, "released: the pages follow the finger again")
    } }

    @Test fun primaryFallbackMakesSettingsNameThePathUsed() { runTest {
        val asker = Asker(RECOGNIZER)
        val service = makeService(FakeTranscriber(), asker)
        service.refreshEngine()
        assertEquals(VoiceEngine.ON_DEVICE_RECOGNIZER, service.engine)

        // The on-device recognizer failed to start; the probe now answers without it.
        asker.set(SERVER)
        service.refreshEngine()
        assertEquals(VoiceEngine.ON_DEVICE_RECOGNIZER, service.engine, "the cached answer would still claim the phone")
        service.primaryFellBack(VoiceLanguage.VIETNAMESE)
        assertEquals(VoiceEngine.SERVER, service.engine)
    } }
}
