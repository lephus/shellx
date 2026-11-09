package com.shellx.core.voice

import kotlin.time.ComparableTimeMark
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Reuses what the phone answered about a language's recognizers. Every press asks, so an answer with a recognizer is
 * kept for [reuse] by [timeSource], keeping the question off the way to the first word. An answer without one is never
 * kept: the next press asks again (the network may be back).
 *
 * Mutex-guarded. The lock covers the kept answers only, never the question itself, so a slow [ask] does not hold up
 * [forget] (the iPhone's actor lets calls in while it waits, too).
 */
class VoiceCapabilityCache(
    private val reuse: Duration = DEFAULT_REUSE,
    private val timeSource: TimeSource.WithComparableMarks,
    private val ask: suspend (VoiceLanguage) -> VoiceCapabilities,
) {
    private class Entry(val capabilities: VoiceCapabilities, val since: ComparableTimeMark)

    private val mutex = Mutex()
    private val kept = HashMap<VoiceLanguage, Entry>()

    suspend fun capabilities(language: VoiceLanguage): VoiceCapabilities {
        mutex.withLock {
            val entry = kept[language]
            if (entry != null && entry.since.elapsedNow() < reuse) return entry.capabilities
        }
        val found = ask(language)
        mutex.withLock {
            if (found.engine != null) kept[language] = Entry(found, timeSource.markNow()) else kept.remove(language)
        }
        return found
    }

    /** Drops the kept answer for [language]: the next question goes to the phone (the path changed, for example the
     *  on-device recognizer failed to start and a press fell back to the standard one). */
    suspend fun forget(language: VoiceLanguage) {
        mutex.withLock { kept.remove(language) }
    }

    companion object {
        /** S3 §6.2: 30 s. */
        val DEFAULT_REUSE: Duration = 30.seconds
    }
}
