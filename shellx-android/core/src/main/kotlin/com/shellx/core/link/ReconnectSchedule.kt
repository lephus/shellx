package com.shellx.core.link

import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

/**
 * How long to wait before the next attempt to reach a Mac. [steps] is the wait after 1, 2, 3, … failures in a row
 * (the last one repeats); [jitterFraction] is the largest share by which a wait may be longer or shorter (0.2 = 20 %).
 */
data class ReconnectSchedule(val steps: List<Duration>, val jitterFraction: Double) {
    init {
        require(steps.isNotEmpty()) { "a schedule needs at least one step" }
    }

    /**
     * The wait after [afterFailures] failures in a row (a session that ended counts as one), zero when there was
     * none. [jitter] in -1..1 (clamped) moves the wait by up to [jitterFraction], so phones that lost the same relay
     * do not all come back at the same instant.
     */
    fun delay(afterFailures: Int, jitter: Double): Duration {
        if (afterFailures <= 0) return Duration.ZERO
        val base = steps[minOf(afterFailures, steps.size) - 1]
        val clamped = jitter.coerceIn(-1.0, 1.0)
        return base * (1 + clamped * jitterFraction)
    }

    companion object {
        /** 0.5, 1, 2, 4, 8, 15, then 30 s for good, each up to 20 % longer or shorter. */
        val STANDARD: ReconnectSchedule = ReconnectSchedule(
            listOf(500.milliseconds, 1.seconds, 2.seconds, 4.seconds, 8.seconds, 15.seconds, 30.seconds),
            0.2,
        )
    }
}
