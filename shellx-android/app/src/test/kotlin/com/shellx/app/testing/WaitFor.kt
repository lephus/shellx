@file:OptIn(ExperimentalCoroutinesApi::class)

package com.shellx.app.testing

import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent

/**
 * A virtual-time wait (3C's `eventually`): runCurrent(), check, delay(5 ms), until [condition] holds or [timeout] of
 * virtual time passed. Returns the condition's last value. Only a wait for an asynchronous effect.
 */
suspend fun TestScope.waitFor(timeout: Duration = 10.seconds, condition: () -> Boolean): Boolean {
    val deadline = testScheduler.currentTime + timeout.inWholeMilliseconds
    while (testScheduler.currentTime < deadline) {
        runCurrent()
        if (condition()) return true
        delay(5.milliseconds)
    }
    runCurrent()
    return condition()
}
