package com.shellx.app.platform

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.shellx.core.platform.CoreLog
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Runtime permissions for code that is not a screen (the mic's model, the push effect). One per process; the activity
 * [attach]es its result registry. Main thread: [attach] and [request] are called there (every caller runs in a main
 * scope); a caller cancelled from another thread is let go on the main thread, and never gets its prompt meanwhile.
 *
 * A prompt shows only while the attached activity is resumed: a request made in the background (or while the activity
 * is only started) waits for its next ON_RESUME, because Android may drop a prompt started from the background and
 * then never answer it (review 3E-A M-5). A request whose every caller left before its prompt showed is dropped. A
 * prompt open while the activity is recreated is answered through the new activity's registration, once.
 */
class PermissionRequester(context: Context) {
    private class Ask(val permission: String) {
        /** The callers waiting for the answer. */
        val waiting = mutableListOf<CancellableContinuation<Boolean>>()

        /** The prompt was started; from then on the ask waits for its answer even when its callers leave. */
        var launched = false

        /** Run once, when the prompt is started. */
        val onLaunch = mutableListOf<() -> Unit>()
    }

    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private var launcher: ActivityResultLauncher<String>? = null
    private var lifecycle: Lifecycle? = null

    /** The requests not answered yet, in order: the first one is being asked (or waits to be). */
    private val asks = ArrayDeque<Ask>()

    fun isGranted(permission: String): Boolean =
        ContextCompat.checkSelfPermission(app, permission) == PackageManager.PERMISSION_GRANTED

    /**
     * Registers one RequestPermission launcher (key [KEY]) in [registry]; call from `MainActivity.onCreate`. A request
     * asked when the activity is recreated gets its answer through the new registration; one whose activity went for
     * good is answered with what the phone says now.
     */
    fun attach(registry: ActivityResultRegistry, owner: LifecycleOwner) {
        val registered = registry.register(KEY, owner, ActivityResultContracts.RequestPermission()) { granted -> answered(granted) }
        launcher = registered
        lifecycle = owner.lifecycle
        owner.lifecycle.addObserver(
            LifecycleEventObserver { source, event ->
                // An older activity's events say nothing about the newest one's.
                if (launcher !== registered) return@LifecycleEventObserver
                when (event) {
                    Lifecycle.Event.ON_RESUME -> asks.firstOrNull()?.let(::launchWhenResumed)
                    Lifecycle.Event.ON_DESTROY -> {
                        launcher = null
                        lifecycle = null
                        if ((source as? Activity)?.isChangingConfigurations != true) answerAllFromThePhone()
                    }
                    else -> {}
                }
            },
        )
    }

    /**
     * The user's answer; false at once while nothing is attached. Requests run one at a time, in order; a request for a
     * permission already being asked (or waiting to be) waits for that answer. [onLaunch] runs once the prompt has
     * started (at once when it already has), never for a request that was dropped, or whose prompt failed to start.
     */
    suspend fun request(permission: String, onLaunch: (() -> Unit)? = null): Boolean {
        if (launcher == null) return false
        val ask = asks.firstOrNull { it.permission == permission } ?: Ask(permission).also { asks.addLast(it) }
        if (onLaunch != null) if (ask.launched) onLaunch() else ask.onLaunch += onLaunch
        return suspendCancellableCoroutine { caller ->
            ask.waiting += caller
            // At once, not when the cancelled caller next runs: an ON_RESUME in between must not show its prompt. A
            // cancellation on another thread is handed to the main thread (review C m-3); launchWhenResumed skips the
            // ask meanwhile.
            caller.invokeOnCancellation {
                if (Looper.getMainLooper().isCurrentThread) left(ask, caller) else main.post { left(ask, caller) }
            }
            if (asks.first() === ask) launchWhenResumed(ask)
        }
    }

    /** Starts [ask]'s prompt now if the attached activity is resumed; else its next ON_RESUME (or attach) does. */
    private fun launchWhenResumed(ask: Ask) {
        if (ask.launched) return
        val current = launcher ?: return
        if (lifecycle?.currentState?.isAtLeast(Lifecycle.State.RESUMED) != true) return
        if (ask.waiting.all { it.isCancelled }) {
            // Every caller was cancelled on another thread, and left() has not run here yet: drop it now.
            asks.remove(ask)
            asks.firstOrNull()?.let(::launchWhenResumed)
            return
        }
        ask.launched = true
        try {
            current.launch(ask.permission)
        } catch (e: RuntimeException) {
            CoreLog.log("permission_launch_failed ${e.javaClass.simpleName}")
            ask.onLaunch.clear()
            finish(ask, isGranted(ask.permission))
            return
        }
        // Only once the prompt started: a launch that failed spends nothing (review C m-3).
        val started = ask.onLaunch.toList()
        ask.onLaunch.clear()
        started.forEach { it() }
    }

    private fun answered(granted: Boolean) {
        val ask = asks.firstOrNull() ?: return
        finish(ask, granted)
    }

    /** Answers [ask] (the first), then asks the next one. */
    private fun finish(ask: Ask, granted: Boolean) {
        if (asks.firstOrNull() !== ask) return
        asks.removeFirst()
        answer(ask, granted)
        asks.firstOrNull()?.let(::launchWhenResumed)
    }

    private fun answer(ask: Ask, granted: Boolean) {
        val callers = ask.waiting.toList()
        ask.waiting.clear()
        // A caller cancelled meanwhile ignores its answer.
        callers.forEach { it.resume(granted) }
    }

    /** [caller] stopped waiting. An ask no one waits for any more, whose prompt never started, is dropped. */
    private fun left(ask: Ask, caller: CancellableContinuation<Boolean>) {
        ask.waiting.remove(caller)
        if (ask.waiting.isNotEmpty() || ask.launched || ask !in asks) return
        val first = asks.firstOrNull() === ask
        asks.remove(ask)
        if (first) asks.firstOrNull()?.let(::launchWhenResumed)
    }

    private fun answerAllFromThePhone() {
        while (asks.isNotEmpty()) {
            val ask = asks.removeFirst()
            answer(ask, isGranted(ask.permission))
        }
    }

    companion object {
        const val KEY = "shellx.permission"
    }
}
