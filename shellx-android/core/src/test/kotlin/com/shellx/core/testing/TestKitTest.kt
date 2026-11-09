package com.shellx.core.testing

import com.shellx.link.account.RelayApiException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

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
