package com.shellx.core.voice

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest

/** The microphone holds one dictation at a time. The newest start wins: a start that a newer one overtook, or whose
 *  run was cancelled while it started, never takes the microphone and never tears down the run that holds it. */
class SpeechRunSlotTest {
    /** Records what each run's handlers were asked to do. */
    private class Log {
        private val events = mutableListOf<String>()

        val all: List<String> get() = synchronized(this) { events.toList() }

        fun add(event: String) {
            synchronized(this) { events += event }
        }

        fun handlers(name: String): SpeechRunSlot.Handlers = SpeechRunSlot.Handlers(
            finish = { add("finish $name"); "text $name" },
            teardown = { add("teardown $name") },
        )
    }

    private fun refused(claim: SpeechRunSlot.Claim): Boolean = claim is SpeechRunSlot.Claim.Refused

    /** The granted claim, or null when refused. */
    private fun granted(claim: SpeechRunSlot.Claim): SpeechRunSlot.Claim.Granted? = claim as? SpeechRunSlot.Claim.Granted

    @Test fun claimTakesTheMicAndHandsBackTheRunItReplaces() { runTest {
        val slot = SpeechRunSlot()
        val log = Log()
        val first = SpeechRunId()
        val second = SpeechRunId()
        slot.begin(first)
        assertNotNull(granted(slot.claim(first, log.handlers("first"))))
        assertTrue(slot.isActive(first))

        slot.begin(second)
        val replaced = assertNotNull(granted(slot.claim(second, log.handlers("second"))))
        assertTrue(slot.isActive(second))
        assertFalse(slot.isActive(first))
        replaced.replaced?.teardown?.invoke()
        assertEquals(listOf("teardown first"), log.all, "the new run tears down the one it replaces")
    } }

    @Test fun staleStartFinishingSecondIsRefused() {
        val slot = SpeechRunSlot()
        val log = Log()
        val stale = SpeechRunId()
        val newer = SpeechRunId()
        slot.begin(stale)
        slot.begin(newer)
        assertNotNull(granted(slot.claim(newer, log.handlers("newer"))))
        assertTrue(refused(slot.claim(stale, log.handlers("stale"))), "an overtaken start never takes over")
        assertTrue(slot.isActive(newer))
        assertTrue(log.all.isEmpty(), "and tears nothing down")
    }

    @Test fun beginningAgainNeverMovesNewestBack() {
        // The router begins every press at its entry; an inner engine (or a fallback retry) begins the same run again
        // later. That must not make an older run the newest again.
        val slot = SpeechRunSlot()
        val log = Log()
        val stale = SpeechRunId()
        val newer = SpeechRunId()
        slot.begin(stale)
        slot.begin(newer)
        slot.begin(stale)
        assertTrue(refused(slot.claim(stale, log.handlers("stale"))))
        assertNotNull(granted(slot.claim(newer, log.handlers("newer"))), "the newer press still gets the mic")
        assertTrue(slot.isActive(newer))
    }

    @Test fun runCancelledWhileStartingIsRefused() { runTest {
        val slot = SpeechRunSlot()
        val log = Log()
        val active = SpeechRunId()
        slot.begin(active)
        slot.claim(active, log.handlers("active"))

        val tap = SpeechRunId()
        slot.begin(tap)
        val handlers = slot.cancel(tap)
        assertNull(handlers, "nothing to tear down yet")
        assertTrue(refused(slot.claim(tap, log.handlers("tap"))))
        assertTrue(slot.isActive(active), "the run that holds the mic keeps it")

        // A cancel that arrives before its start began counts too.
        val early = SpeechRunId()
        slot.cancel(early)
        slot.begin(early)
        assertTrue(refused(slot.claim(early, log.handlers("early"))))
        assertTrue(log.all.isEmpty())
    } }

    @Test fun cancelTearsDownOnlyTheRunItNames() { runTest {
        val slot = SpeechRunSlot()
        val log = Log()
        val run = SpeechRunId()
        slot.begin(run)
        slot.claim(run, log.handlers("run"))
        assertNull(slot.cancel(SpeechRunId()))
        assertTrue(slot.isActive(run))
        slot.cancel(run)?.teardown?.invoke()
        assertFalse(slot.isActive(run))
        assertEquals(listOf("teardown run"), log.all)
        assertNull(slot.cancel(run), "a second cancel finds nothing")
    } }

    @Test fun finishAndEndTakeTheActiveRunOnly() { runTest {
        val slot = SpeechRunSlot()
        val log = Log()
        val run = SpeechRunId()
        slot.begin(run)
        slot.claim(run, log.handlers("run"))
        assertNull(slot.takeForFinish(SpeechRunId()))
        val text = slot.takeForFinish(run)?.finish?.invoke()
        assertEquals("text run", text)
        assertFalse(slot.isActive(run), "a finishing run no longer holds the slot")

        val ending = SpeechRunId()
        slot.begin(ending)
        assertIs<SpeechRunSlot.Claim.Granted>(slot.claim(ending, log.handlers("ending")))
        assertFalse(slot.ended(SpeechRunId()))
        assertTrue(slot.ended(ending), "it ended by itself while it held the mic")
        assertFalse(slot.ended(ending))
        assertNull(slot.active)
    } }
}
