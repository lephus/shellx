package com.shellx.core.testing

import kotlin.coroutines.resume
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.withContext
import kotlinx.coroutines.yield

/** A sleep that returns at once (after a yield), so reconnect backoff costs nothing. */
val instantSleep: suspend (Duration) -> Unit = { yield() }

/**
 * Repeats until the condition holds or [timeout] of virtual time passed, returning the condition's last value:
 * runCurrent(), check the condition, then delay(5.milliseconds). Only a wait for an asynchronous effect: no test
 * logic depends on how long it takes.
 */
suspend fun TestScope.eventually(timeout: Duration = 10.seconds, condition: suspend () -> Boolean): Boolean {
    val deadline = testScheduler.currentTime + timeout.inWholeMilliseconds
    while (testScheduler.currentTime < deadline) {
        runCurrent()
        if (condition()) return true
        delay(5.milliseconds)
    }
    runCurrent()
    return condition()
}

/**
 * Like [eventually], but for an effect that a real thread produces (OkHttp, `Dispatchers.IO`/`Default`, a plain
 * `Thread`): repeats until the condition holds or [timeout] of real time passed (Swift's `eventually` waits 10 s
 * of real time). Each round runs runCurrent(), so work a real thread handed back to the test dispatcher runs, then
 * checks the condition, then blocks the test thread for 5 ms of real time. Virtual time never moves here.
 */
suspend fun TestScope.eventuallyReal(timeout: Duration = 10.seconds, condition: suspend () -> Boolean): Boolean {
    val deadline = TimeSource.Monotonic.markNow() + timeout
    while (deadline.hasNotPassedNow()) {
        runCurrent()
        if (condition()) return true
        Thread.sleep(5)
    }
    runCurrent()
    return condition()
}

/**
 * A sleep the test drives (port of ManualSleeper): each call waits until [release], or until its coroutine is
 * cancelled (then it counts in [cancelled] and rethrows). Thread-safe.
 */
class ManualSleeper {
    private val lock = Any()
    private val calls = mutableListOf<Duration>()
    private val waiters = LinkedHashMap<Any, Pair<Duration, CancellableContinuation<Unit>>>()
    private var cancellations = 0

    val sleep: suspend (Duration) -> Unit = { duration -> wait(duration) }

    /** Every duration asked for, in order. */
    val requested: List<Duration> get() = synchronized(lock) { calls.toList() }

    /** The waits still blocked, in the order they began. */
    val waiting: List<Duration> get() = synchronized(lock) { waiters.values.map { it.first } }

    /** How many waits ended by cancellation. */
    val cancelled: Int get() = synchronized(lock) { cancellations }

    /** Ends every blocked wait whose duration matches, as if the time had passed. */
    fun release(matches: (Duration) -> Boolean = { true }) {
        val due = synchronized(lock) {
            val ids = waiters.filter { matches(it.value.first) }.keys.toList()
            ids.mapNotNull { waiters.remove(it)?.second }
        }
        for (continuation in due) continuation.resume(Unit)
    }

    private suspend fun wait(duration: Duration) {
        val id = Any()
        suspendCancellableCoroutine { continuation ->
            synchronized(lock) {
                calls += duration
                waiters[id] = duration to continuation
            }
            continuation.invokeOnCancellation {
                synchronized(lock) { if (waiters.remove(id) != null) cancellations += 1 }
            }
        }
    }
}

/**
 * Holds callers until [open]. Ignores cancellation on purpose, so a test can keep a call (and whoever awaits it)
 * suspended at a known point. Thread-safe.
 */
class Gate {
    private val lock = Any()
    private val opened = CompletableDeferred<Unit>()
    private var isOpen = false
    private var held = 0

    /** How many callers are held right now. */
    val waiting: Int get() = synchronized(lock) { held }

    suspend fun wait() {
        synchronized(lock) {
            if (isOpen) return
            held += 1
        }
        withContext(NonCancellable) { opened.await() }
    }

    /** Lets every held caller and every later one through. */
    fun open() {
        synchronized(lock) {
            isOpen = true
            held = 0
        }
        opened.complete(Unit)
    }
}
