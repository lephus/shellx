package com.shellx.link.core

import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeout

/** Runs [block], failing the test when it takes longer than [timeout]. */
suspend fun <T> within(timeout: Duration = 5.seconds, block: suspend CoroutineScope.() -> T): T = withTimeout(timeout, block)

/** Polls [condition] every 5 ms until it holds or [timeout] passes; returns the last result. */
suspend fun eventually(timeout: Duration = 2.seconds, condition: () -> Boolean): Boolean {
    val deadline = TimeSource.Monotonic.markNow() + timeout
    while (true) {
        if (condition()) return true
        if (deadline.hasPassedNow()) return condition()
        delay(5)
    }
}
