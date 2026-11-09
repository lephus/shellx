package com.shellx.app

import android.app.Application
import android.util.Log
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ProcessLifecycleOwner
import com.shellx.app.platform.ActivityTracker
import com.shellx.core.platform.CoreLog
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The application (contracts §5): reads the settings snapshot and builds the platform services off the main thread,
 * then makes the [AppComposition] and feeds it the process lifecycle. Plan 3E adds its `PlatformServices` here and
 * passes its pieces to the `AppComposition(…)` call (3E Task 12).
 */
class ShellXApplication : Application() {
    private val _composition = MutableStateFlow<AppComposition?>(null)

    /** Null until the settings snapshot is read and the composition built ([onCreate] starts it). */
    val composition: StateFlow<AppComposition?> = _composition.asStateFlow()

    suspend fun awaitComposition(): AppComposition = composition.filterNotNull().first()

    override fun onCreate() {
        super.onCreate()
        CoreLog.sink = { Log.i("ShellX", it) }
        registerActivityLifecycleCallbacks(ActivityTracker.shared)
        val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        // One channel keeps ON_START and ON_STOP in order, and holds the ones that come before the composition exists.
        val events = Channel<Lifecycle.Event>(Channel.UNLIMITED)
        ProcessLifecycleOwner.get().lifecycle.addObserver(
            LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_START || event == Lifecycle.Event.ON_STOP) events.trySend(event)
            },
        )
        appScope.launch {
            val environment = withContext(Dispatchers.IO) { AppEnvironment.android(this@ShellXApplication) }
            val composition = AppComposition(environment, appScope)
            _composition.value = composition
            for (event in events) {
                if (event == Lifecycle.Event.ON_START) composition.lifecycle.onStart() else composition.lifecycle.onStop()
            }
        }
    }
}
