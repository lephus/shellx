package com.shellx.core.testing

import com.shellx.core.account.LocalDataWiping
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred

/** Counts its wipes (AppCoordinatorTests.swift). Thread-safe. */
class CountingWiper : LocalDataWiping {
    private val count = AtomicInteger()

    val wipes: Int get() = count.get()

    override suspend fun wipe() {
        count.incrementAndGet()
    }
}

/** A wiper that throws while failing is set (at first it is), and counts its attempts. Thread-safe. */
class FlakyWiper : LocalDataWiping {
    class Failure : Exception("wipe_failed")

    private val attemptCount = AtomicInteger()

    @Volatile private var isFailing = true

    val attempts: Int get() = attemptCount.get()

    fun setFailing(value: Boolean) {
        isFailing = value
    }

    override suspend fun wipe() {
        attemptCount.incrementAndGet()
        if (isFailing) throw Failure()
    }
}

/**
 * A wiper whose wipe() does not return while it is held: the app dying in the middle of a sign-out's wipe looks like
 * this from outside. Thread-safe.
 */
class GatedWiper : LocalDataWiping {
    private val lock = Any()
    private var isHeld = false
    private var entered = 0
    private val waiters = ArrayList<CompletableDeferred<Unit>>()

    /** How many times wipe() was called, held or not. */
    val calls: Int get() = synchronized(lock) { entered }

    fun hold() {
        synchronized(lock) { isHeld = true }
    }

    fun release() {
        val waiting = synchronized(lock) {
            isHeld = false
            waiters.toList().also { waiters.clear() }
        }
        for (waiter in waiting) waiter.complete(Unit)
    }

    override suspend fun wipe() {
        val waiter = synchronized(lock) {
            entered += 1
            if (isHeld) CompletableDeferred<Unit>().also { waiters += it } else null
        }
        waiter?.await()
    }
}
