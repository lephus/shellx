package com.shellx.core.platform

import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
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
internal suspend fun <T> CoroutineScope.runDetached(block: suspend CoroutineScope.() -> T): T =
    startDetached(block).await().getOrThrow()

/**
 * One run at a time of an action that outlives its screen (review 3a m-2). [run] works as runDetached, but a call while
 * an earlier run is still going waits for that run and gets its result, instead of starting a second one beside it:
 * a screen that came back cannot start a second sign-in while the first is still on the relay. A call after the run
 * ended starts a new one. Main-confined.
 */
internal class DetachedRun<T> {
    private var running: Deferred<Result<T>>? = null

    suspend fun run(scope: CoroutineScope, block: suspend CoroutineScope.() -> T): T {
        val work = running?.takeUnless { it.isCompleted } ?: scope.startDetached(block).also { running = it }
        return work.await().getOrThrow()
    }
}

private fun <T> CoroutineScope.startDetached(block: suspend CoroutineScope.() -> T): Deferred<Result<T>> =
    async(start = CoroutineStart.UNDISPATCHED) {
        try {
            Result.success(block())
        } catch (e: Throwable) {
            rethrowIfCancelled(e)
            Result.failure(if (e is CancellationException) IllegalStateException("detached_work_cancelled", e) else e)
        }
    }

/**
 * For a `catch (e: Exception)` around suspending work: throws this coroutine's cancellation when it is cancelled.
 * Otherwise it returns, and [e] is handled as an ordinary failure, even a `CancellationException` that the work threw
 * of its own (an inner `withTimeout`, an awaited `Deferred` cancelled elsewhere; review 1 M-3).
 */
internal suspend fun rethrowIfCancelled(e: Throwable) {
    if (e is CancellationException) currentCoroutineContext().ensureActive()
}
