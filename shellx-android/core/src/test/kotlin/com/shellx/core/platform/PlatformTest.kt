package com.shellx.core.platform

import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout

class PlatformTest {
    @Test fun memoryStoreKeepsStringsAndBooleans() {
        val s = MemoryKeyValueStore()
        assertNull(s.getString("a")); s.putString("a", "1"); assertEquals("1", s.getString("a"))
        s.putString("a", null); assertNull(s.getString("a"))
        assertFalse(s.getBoolean("b")); s.putBoolean("b", true); assertTrue(s.getBoolean("b"))
        s.remove("b"); assertFalse(s.getBoolean("b"))
    }

    @Test fun detachedWorkSurvivesTheCallersCancellation() { runTest {
        val scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
        val gate = CompletableDeferred<Unit>(); var finished = false
        val caller = launch { scope.runDetached { gate.await(); finished = true } }
        runCurrent(); caller.cancelAndJoin(); gate.complete(Unit); runCurrent()
        assertTrue(finished); scope.cancel()
    } }

    @Test fun detachedFailuresReachTheCallerAndNotTheScope() { runTest {
        val scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
        assertEquals("boom", assertFailsWith<IllegalStateException> { scope.runDetached { error("boom") } }.message)
        assertTrue(scope.isActive); scope.cancel()
        // A parent that a failed child cancels: the failure must not reach it.
        val parent = Job()
        val plain = CoroutineScope(parent + StandardTestDispatcher(testScheduler))
        assertEquals("boom", assertFailsWith<IllegalStateException> { plain.runDetached { error("boom") } }.message)
        assertTrue(parent.isActive); parent.cancel()
        // runTest's backgroundScope reports a failed child as the test's failure.
        assertEquals("boom", assertFailsWith<IllegalStateException> { backgroundScope.runDetached { error("boom") } }.message)
        assertTrue(backgroundScope.isActive)
    } }

    /**
     * Review 1 M-3: a block that throws a CancellationException of its own (an inner timeout, a Deferred cancelled
     * elsewhere) fails the caller's wait with an ordinary exception, so a caller that was not cancelled never ends
     * silently as if it had been.
     */
    @Test fun aBlocksOwnCancellationIsAFailureForTheCaller() { runTest {
        val scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
        val timedOut = assertFails { scope.runDetached { withTimeout(1.seconds) { awaitCancellation() } } }
        assertFalse(timedOut is CancellationException, "$timedOut")
        assertEquals("detached_work_cancelled", timedOut.message)
        assertIs<TimeoutCancellationException>(timedOut.cause)

        val other = CompletableDeferred<Unit>().apply { cancel() }
        val awaited = assertFails { scope.runDetached { other.await() } }
        assertFalse(awaited is CancellationException, "$awaited")
        assertIs<CancellationException>(awaited.cause)
        assertTrue(scope.isActive)

        // The scope's own cancellation still ends the work cancelled.
        val gate = CompletableDeferred<Unit>()
        val caller = async { runCatching { scope.runDetached { gate.await() } }.exceptionOrNull() }
        runCurrent(); scope.cancel(); runCurrent()
        assertIs<CancellationException>(caller.await())
    } }

    @Test fun coreLogGoesToTheSink() {
        val lines = mutableListOf<String>(); CoreLog.sink = { lines += it }
        try { CoreLog.log("hub_started") } finally { CoreLog.sink = {} }
        assertEquals(listOf("hub_started"), lines)
    }
}
