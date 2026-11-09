package com.shellx.app.platform

import com.google.android.gms.tasks.Task
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * The [Task]'s result (FCM's token, Play's update info). The listener runs on a direct executor (`Runnable::run`), so
 * nothing waits for the main thread. Cancellation-aware: a cancelled caller stops waiting (the task itself runs on),
 * and a cancelled task cancels the caller.
 */
suspend fun <T> Task<T>.await(): T {
    if (isComplete) {
        exception?.let { throw it }
        if (isCanceled) throw CancellationException("Task $this was cancelled")
        @Suppress("UNCHECKED_CAST")
        return result as T
    }
    return suspendCancellableCoroutine { continuation ->
        addOnCompleteListener(Runnable::run) { task ->
            val error = task.exception
            when {
                error != null -> continuation.resumeWithException(error)
                task.isCanceled -> continuation.cancel()
                else -> {
                    @Suppress("UNCHECKED_CAST")
                    continuation.resume(task.result as T)
                }
            }
        }
    }
}
