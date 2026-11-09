package com.shellx.app.testing

import org.robolectric.shadows.ShadowLooper

/**
 * Runs the main looper and waits (real time, at most [timeoutMs]) until [condition] holds: idle the main looper, check,
 * sleep 5 ms. Returns the condition's last value. Call it on the test's (main) thread. Only a wait for an asynchronous
 * effect, never a delay.
 */
fun eventually(timeoutMs: Long = 10_000, condition: () -> Boolean): Boolean {
    val deadline = System.currentTimeMillis() + timeoutMs
    while (true) {
        ShadowLooper.idleMainLooper()
        if (condition()) return true
        if (System.currentTimeMillis() >= deadline) return false
        Thread.sleep(5)
    }
}
