package com.shellx.core.link

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlin.time.DurationUnit

class ReconnectScheduleTest {
    private fun seconds(d: Duration): Double = d.toDouble(DurationUnit.SECONDS)

    @Test fun delaysGrowAndCapAt30s() {
        val schedule = ReconnectSchedule.STANDARD
        val delays = (1..10).map { seconds(schedule.delay(it, 0.0)) }
        assertEquals(listOf(0.5, 1.0, 2.0, 4.0, 8.0, 15.0, 30.0, 30.0, 30.0, 30.0), delays)
        assertEquals(30.seconds, schedule.delay(1000, 0.0))
        assertEquals(Duration.ZERO, schedule.delay(0, 0.0))
    }

    @Test fun jitterWithin20Percent() {
        val schedule = ReconnectSchedule.STANDARD
        for (failures in 1..10) {
            val base = seconds(schedule.delay(failures, 0.0))
            var jitter = -1.0
            while (jitter <= 1.0) {
                val delay = seconds(schedule.delay(failures, jitter))
                assertTrue(abs(delay - base) <= base * 0.2 + 1e-9, "failures $failures, jitter $jitter")
                jitter += 0.125
            }
            assertEquals(base * 1.2, seconds(schedule.delay(failures, 1.0)), 1e-9)
            assertEquals(base * 0.8, seconds(schedule.delay(failures, -1.0)), 1e-9)
            // Out-of-range jitter is clamped, never more than 20 %.
            assertEquals(base * 1.2, seconds(schedule.delay(failures, 7.0)), 1e-9)
            assertEquals(base * 0.8, seconds(schedule.delay(failures, -7.0)), 1e-9)
        }
        assertTrue(schedule.delay(99, 1.0) <= 36.seconds)
    }
}
