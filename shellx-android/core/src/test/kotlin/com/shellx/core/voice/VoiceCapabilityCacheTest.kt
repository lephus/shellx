package com.shellx.core.voice

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TestTimeSource
import kotlinx.coroutines.test.runTest

/** Every press asks which recognizer can run; an answer with one is reused for a while, so the question stays off the
 *  way to the first word. An answer without one is never reused: the next press asks again (the network may be
 *  back). */
class VoiceCapabilityCacheTest {
    /** Counts the questions and answers with what the test sets. */
    private class Asker(private var answer: VoiceCapabilities) {
        private val asked = mutableListOf<VoiceLanguage>()

        val questions: List<VoiceLanguage> get() = synchronized(this) { asked.toList() }

        fun set(answer: VoiceCapabilities) {
            synchronized(this) { this.answer = answer }
        }

        fun ask(language: VoiceLanguage): VoiceCapabilities = synchronized(this) {
            asked += language
            answer
        }
    }

    private companion object {
        val SERVER = VoiceCapabilities(onDeviceRecognizer = false, standardOnDevice = false, standardAvailable = true)
        val RECOGNIZER = VoiceCapabilities(onDeviceRecognizer = true, standardOnDevice = true, standardAvailable = true)
    }

    @Test fun positiveAnswerReusedWithinTheWindow() { runTest {
        val clock = TestTimeSource()
        val asker = Asker(SERVER)
        val cache = VoiceCapabilityCache(reuse = 30.seconds, timeSource = clock) { asker.ask(it) }

        val first = cache.capabilities(VoiceLanguage.VIETNAMESE)
        assertEquals(SERVER, first)
        clock += 29.seconds
        asker.set(RECOGNIZER)
        val second = cache.capabilities(VoiceLanguage.VIETNAMESE)
        assertEquals(SERVER, second, "still within 30 s")
        assertEquals(listOf(VoiceLanguage.VIETNAMESE), asker.questions)

        // Each language has its own answer.
        cache.capabilities(VoiceLanguage.ENGLISH)
        assertEquals(listOf(VoiceLanguage.VIETNAMESE, VoiceLanguage.ENGLISH), asker.questions)
    } }

    @Test fun answerExpiresAfterTheWindow() { runTest {
        val clock = TestTimeSource()
        val asker = Asker(SERVER)
        val cache = VoiceCapabilityCache(reuse = 30.seconds, timeSource = clock) { asker.ask(it) }
        cache.capabilities(VoiceLanguage.VIETNAMESE)
        clock += 30.seconds
        asker.set(RECOGNIZER)
        val later = cache.capabilities(VoiceLanguage.VIETNAMESE)
        assertEquals(RECOGNIZER, later, "asked again once 30 s passed")
        assertEquals(2, asker.questions.size)
    } }

    @Test fun forgetAsksAgainAtOnce() { runTest {
        // The on-device recognizer failed to start and a press fell back: the next answer must name that path.
        val clock = TestTimeSource()
        val asker = Asker(RECOGNIZER)
        val cache = VoiceCapabilityCache(reuse = 30.seconds, timeSource = clock) { asker.ask(it) }
        cache.capabilities(VoiceLanguage.VIETNAMESE)
        asker.set(SERVER)
        cache.forget(VoiceLanguage.VIETNAMESE)
        val now = cache.capabilities(VoiceLanguage.VIETNAMESE)
        assertEquals(SERVER, now)
        assertEquals(2, asker.questions.size)
    } }

    @Test fun noRecognizerIsNeverReused() { runTest {
        val clock = TestTimeSource()
        val asker = Asker(VoiceCapabilities.NONE)
        val cache = VoiceCapabilityCache(reuse = 30.seconds, timeSource = clock) { asker.ask(it) }
        val offline = cache.capabilities(VoiceLanguage.VIETNAMESE)
        assertNull(offline.engine)
        asker.set(SERVER)
        val back = cache.capabilities(VoiceLanguage.VIETNAMESE)
        assertEquals(SERVER, back, "the next press asks again")
        assertEquals(2, asker.questions.size)
    } }
}
