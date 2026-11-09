package com.shellx.app.platform

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.shellx.core.platform.CoreLog
import kotlinx.coroutines.CompletableDeferred

/**
 * Runtime permissions for code that is not a screen (the mic's model, the push effect). One per process; the activity
 * [attach]es its result registry. Main thread.
 */
class PermissionRequester(context: Context) {
    private class Ask(val permission: String) {
        val answer = CompletableDeferred<Boolean>()
    }

    private val app = context.applicationContext
    private var launcher: ActivityResultLauncher<String>? = null

    /** The requests not answered yet, in order: the first one is being asked. */
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
        owner.lifecycle.addObserver(
            LifecycleEventObserver { source, event ->
                if (event != Lifecycle.Event.ON_DESTROY) return@LifecycleEventObserver
                if (launcher === registered) launcher = null
                if ((source as? Activity)?.isChangingConfigurations != true) answerAllFromThePhone()
            },
        )
    }

    /**
     * The user's answer; false at once while nothing is attached. Requests run one at a time, in order; a request for a
     * permission already being asked (or waiting to be) waits for that answer.
     */
    suspend fun request(permission: String): Boolean {
        if (launcher == null) return false
        val ask = asks.firstOrNull { it.permission == permission } ?: Ask(permission).also {
            asks.addLast(it)
            if (asks.size == 1) launch(it)
        }
        return ask.answer.await()
    }

    private fun launch(ask: Ask) {
        val current = launcher
        if (current == null) {
            finish(ask, isGranted(ask.permission))
            return
        }
        try {
            current.launch(ask.permission)
        } catch (e: RuntimeException) {
            CoreLog.log("permission_launch_failed ${e.javaClass.simpleName}")
            finish(ask, isGranted(ask.permission))
        }
    }

    private fun answered(granted: Boolean) {
        val ask = asks.firstOrNull() ?: return
        finish(ask, granted)
    }

    /** Answers [ask] (the first), then asks the next one. */
    private fun finish(ask: Ask, granted: Boolean) {
        if (asks.firstOrNull() !== ask) return
        asks.removeFirst()
        ask.answer.complete(granted)
        asks.firstOrNull()?.let(::launch)
    }

    private fun answerAllFromThePhone() {
        while (asks.isNotEmpty()) {
            val ask = asks.removeFirst()
            ask.answer.complete(isGranted(ask.permission))
        }
    }

    companion object {
        const val KEY = "shellx.permission"
    }
}
