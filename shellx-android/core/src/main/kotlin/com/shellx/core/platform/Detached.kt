package com.shellx.core.platform

import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/**
 * Runs [block] in this scope and waits for it. Cancelling the caller does not cancel the work. The block starts at
 * once in the caller's frame (CoroutineStart.UNDISPATCHED). The inner `async` returns a `Result` and never completes
 * exceptionally, so a supervised parent that reports child failures (runTest's backgroundScope) never sees the
 * failure; `getOrThrow()` hands the failure to the caller.
 *
 * A cancellation of the work itself (this scope cancelled) is not caught: the work ends cancelled, and the caller's
 * wait throws `CancellationException`. A `CancellationException` the block throws of its own while the work is still
 * active (an inner `withTimeout`, an awaited `Deferred` cancelled elsewhere) reaches the caller as an
 * `IllegalStateException("detached_work_cancelled")` with that cause, so a caller that was not cancelled never ends
 * silently as if it had been (review 1 M-3).
 */
internal suspend fun <T> CoroutineScope.runDetached(block: suspend CoroutineScope.() -> T): T {
    val work = async(start = CoroutineStart.UNDISPATCHED) {
        try {
            Result.success(block())
        } catch (e: Throwable) {
            rethrowIfCancelled(e)
            Result.failure(if (e is CancellationException) IllegalStateException("detached_work_cancelled", e) else e)
        }
    }
    return work.await().getOrThrow()
}

/**
 * For a `catch (e: Exception)` around suspending work: throws this coroutine's cancellation when it is cancelled.
 * Otherwise it returns, and [e] is handled as an ordinary failure, even a `CancellationException` that the work threw
 * of its own (an inner `withTimeout`, an awaited `Deferred` cancelled elsewhere; review 1 M-3).
 */
internal suspend fun rethrowIfCancelled(e: Throwable) {
    if (e is CancellationException) currentCoroutineContext().ensureActive()
}
