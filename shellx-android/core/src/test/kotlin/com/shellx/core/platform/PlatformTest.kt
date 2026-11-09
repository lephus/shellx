package com.shellx.core.platform

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

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

    @Test fun coreLogGoesToTheSink() {
        val lines = mutableListOf<String>(); CoreLog.sink = { lines += it }
        try { CoreLog.log("hub_started") } finally { CoreLog.sink = {} }
        assertEquals(listOf("hub_started"), lines)
    }
}
