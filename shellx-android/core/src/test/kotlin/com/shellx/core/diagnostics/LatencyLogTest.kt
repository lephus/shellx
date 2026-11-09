package com.shellx.core.diagnostics

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

class LatencyLogTest {
    @Test fun percentilesOverLast200() {
        val log = LatencyLog()
        assertNull(log.summary(LatencyMetric.REPLY_ROUND_TRIP))
        for (ms in 1..300) log.record(LatencyMetric.REPLY_ROUND_TRIP, ms.milliseconds)
        log.record(LatencyMetric.FIRST_WORD, 80.milliseconds)

        // Only 101..300 ms count: nearest-rank p50 is the 100th value, p95 the 190th.
        assertEquals(LatencySummary(200, 200.milliseconds, 290.milliseconds), log.summary(LatencyMetric.REPLY_ROUND_TRIP))
        assertEquals(LatencySummary(1, 80.milliseconds, 80.milliseconds), log.summary(LatencyMetric.FIRST_WORD))
        assertNull(log.summary(LatencyMetric.PENDING_ARRIVAL))
    }

    @Test fun negativeDurationRecordedAsZero() {
        val lines = mutableListOf<String>()
        val log = LatencyLog { lines += it }
        log.record(LatencyMetric.PENDING_ARRIVAL, (-40).milliseconds)
        assertEquals(LatencySummary(1, Duration.ZERO, Duration.ZERO), log.summary(LatencyMetric.PENDING_ARRIVAL))
        // A log line carries only the metric name and milliseconds.
        assertEquals(listOf("pendingArrival 0 ms"), lines)
    }

    @Test fun recordingFromManyThreads() {
        val log = LatencyLog()
        runBlocking {
            (0 until 8).map { task ->
                launch(Dispatchers.Default) {
                    for (ms in 0 until 50) log.record(LatencyMetric.SESSION_CHANGE_ARRIVAL, (task * 50 + ms).milliseconds)
                }
            }.joinAll()
        }
        assertEquals(200, log.summary(LatencyMetric.SESSION_CHANGE_ARRIVAL)?.count)
    }
}
