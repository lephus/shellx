package com.shellx.core.platform

import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async

/**
 * Runs [block] in this scope and waits for it. Cancelling the caller does not cancel the work. The block starts at
 * once in the caller's frame (CoroutineStart.UNDISPATCHED). The inner `async` returns a `Result` and never completes
 * exceptionally, so a supervised parent that reports child failures (runTest's backgroundScope) never sees the
 * failure; `getOrThrow()` hands the failure to the caller.
 *
 * A cancellation of the work itself (this scope cancelled) is not caught: the work ends cancelled, and the caller's
 * wait throws `CancellationException`.
 */
internal suspend fun <T> CoroutineScope.runDetached(block: suspend CoroutineScope.() -> T): T {
    val work = async(start = CoroutineStart.UNDISPATCHED) {
        try {
            Result.success(block())
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            Result.failure(e)
        }
    }
    return work.await().getOrThrow()
}
