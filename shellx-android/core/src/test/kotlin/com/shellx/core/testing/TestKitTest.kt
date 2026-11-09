package com.shellx.core.testing

import com.shellx.link.account.RelayApiException
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext

class TestKitTest {
    @Test fun manualSleeperRecordsReleasesAndCountsCancellations() { runTest {
        val s = ManualSleeper()
        val a = backgroundScope.launch { s.sleep(1.seconds) }; val b = backgroundScope.launch { s.sleep(2.seconds) }
        runCurrent()
        assertEquals(listOf(1.seconds, 2.seconds), s.requested); assertEquals(listOf(1.seconds, 2.seconds), s.waiting)
        s.release { it == 1.seconds }; runCurrent(); assertTrue(a.isCompleted)
        b.cancelAndJoin(); assertEquals(1, s.cancelled); assertEquals(emptyList(), s.waiting)
    } }

    @Test fun gateHoldsThroughCancellationUntilOpened() { runTest {
        val g = Gate(); val job = backgroundScope.launch { g.wait() }; runCurrent()
        assertEquals(1, g.waiting); job.cancel(); runCurrent(); assertEquals(1, g.waiting)
        g.open(); runCurrent(); assertEquals(0, g.waiting)
        val late = backgroundScope.launch { g.wait() }; runCurrent(); assertTrue(late.isCompleted)
    } }

    @Test fun eventuallyLetsVirtualTimePass() { runTest {
        var ready = false; backgroundScope.launch { delay(3.seconds); ready = true }
        assertTrue(eventually { ready }); assertFalse(eventually(timeout = 100.milliseconds) { false })
    } }

    @Test fun eventuallyRealWaitsForRealThreadsWithoutMovingVirtualTime() { runTest {
        val flag = AtomicBoolean(false)
        thread { Thread.sleep(200); flag.set(true) }
        assertTrue(eventuallyReal { flag.get() })
        var handedBack = false
        backgroundScope.launch { withContext(Dispatchers.IO) { Thread.sleep(100) }; handedBack = true }
        assertTrue(eventuallyReal { handedBack })
        val started = TimeSource.Monotonic.markNow()
        assertFalse(eventuallyReal(timeout = 50.milliseconds) { false })
        assertTrue(started.elapsedNow() >= 50.milliseconds)
        assertEquals(0L, testScheduler.currentTime)
    } }

    @Test fun manualClockMovesOnlyWhenTold() {
        val c = ManualClock(wallMs = 1_700_000_000_000); val mark = c.monotonic.markNow()
        c.advance(1500.milliseconds)
        assertEquals(1_700_000_001_500, c.nowMs()); assertEquals(1500.milliseconds, mark.elapsedNow())
        c.wallMs = 5; assertEquals(5, c.nowMs())
    }

    @Test fun sameCaseComparesClassAndFields() {
        assertSameCase(RelayApiException.BadResponse(), RelayApiException.BadResponse())
        assertSameCase(RelayApiException.Http(401, "x"), RelayApiException.Http(401, "x"))
        assertFails { assertSameCase(RelayApiException.Http(401, "x"), RelayApiException.Http(401, "y")) }
        assertFails { assertSameCase(RelayApiException.BadResponse(), RelayApiException.SlotMismatch()) }
    }
}
