package com.shellx.core.testing

import com.shellx.core.platform.Clock
import kotlin.time.Duration
import kotlin.time.TestTimeSource
import kotlin.time.TimeSource

/**
 * A clock the test moves by hand: [wallMs] changes only through [advance] or assignment, and the monotonic source
 * (a [TestTimeSource]) only through [advance], so a measured duration is exactly what the test advanced.
 */
class ManualClock(@Volatile var wallMs: Long = 1_700_000_000_000) : Clock {
    private val source = TestTimeSource()

    override fun nowMs(): Long = wallMs

    override val monotonic: TimeSource.WithComparableMarks get() = source

    fun advance(by: Duration) {
        synchronized(source) {
            wallMs += by.inWholeMilliseconds
            source += by
        }
    }
}
