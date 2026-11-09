package com.shellx.app.testing

import com.shellx.core.platform.Clock
import kotlin.time.Duration
import kotlin.time.TestTimeSource
import kotlin.time.TimeSource

/** A clock the test moves: [advance] moves the wall time and the monotonic source together. Thread-safe. */
class ManualClock(wallMs: Long = 1_700_000_000_000) : Clock {
    private val source = TestTimeSource()

    @Volatile var wallMs: Long = wallMs

    override fun nowMs(): Long = wallMs

    override val monotonic: TimeSource.WithComparableMarks get() = source

    @Synchronized
    fun advance(by: Duration) {
        wallMs += by.inWholeMilliseconds
        source += by
    }
}
