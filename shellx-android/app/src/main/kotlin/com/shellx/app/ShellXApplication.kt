package com.shellx.app

import android.app.Application
import android.util.Log
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ProcessLifecycleOwner
import com.shellx.app.platform.ActivityTracker
import com.shellx.app.platform.PushHooks
import com.shellx.app.platform.PushHost
import com.shellx.app.platform.PushNotifier
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
 * The application (contracts §5): makes plan 3E's [PlatformServices] first, reads the settings snapshot and builds the
 * environment off the main thread, then makes the [AppComposition] with the platform's pieces and feeds it the process
 * lifecycle. It is the FCM service's [PushHost]: a push can start the process in the background, before the composition
 * exists, so the hooks wait for it ([awaitComposition]) rather than read it.
 */
class ShellXApplication : Application(), PushHost {
    private val _composition = MutableStateFlow<AppComposition?>(null)

    /** Null until the settings snapshot is read and the composition built ([onCreate] starts it). */
    val composition: StateFlow<AppComposition?> = _composition.asStateFlow()

    /** Plan 3E's platform pieces, made first in [onCreate]. */
    lateinit var platform: PlatformServices
        private set

    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /** `shellx-link` links that came before the composition existed, in order (main thread; review D m-2). */
    private val heldLinks = mutableListOf<String>()

    suspend fun awaitComposition(): AppComposition = composition.filterNotNull().first()

    override val pushHooks: PushHooks by lazy {
        PushHooks(platform.makeNotifier { awaitComposition().vault }) { token ->
            appScope.launch { awaitComposition().push?.tokenArrived(token) }
        }
    }

    /**
     * A `shellx-link` link from an intent (main thread): into the pairing inbox, or held until the composition exists.
     * The application holds it, so it outlives an activity recreated or finished before then.
     */
    fun receiveLink(uri: String) {
        val built = composition.value
        if (built == null) heldLinks += uri else built.inbox.receive(uri)
    }

    override fun onCreate() {
        super.onCreate()
        CoreLog.sink = { Log.i("ShellX", it) }
        platform = PlatformServices(this, BuildConfig.DEBUG)
        PushNotifier.ensureChannel(this)
        registerActivityLifecycleCallbacks(ActivityTracker.shared)
        // One channel keeps ON_START and ON_STOP in order, and holds the ones that come before the composition exists.
        val events = Channel<Lifecycle.Event>(Channel.UNLIMITED)
        ProcessLifecycleOwner.get().lifecycle.addObserver(
            LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_START || event == Lifecycle.Event.ON_STOP) events.trySend(event)
            },
        )
        appScope.launch {
            val environment = withContext(Dispatchers.IO) { AppEnvironment.android(this@ShellXApplication) }
            val composition = AppComposition(
                environment,
                appScope,
                speechEngine = platform.speechEngine,
                voicePermissions = platform.voicePermissions,
                pushRegistrar = platform.pushRegistrar,
                updateChecker = platform.updateChecker,
                attachmentReader = platform.attachmentReader,
                makeVoice = platform::makeVoice,
            )
            heldLinks.forEach(composition.inbox::receive)
            heldLinks.clear()
            _composition.value = composition
            for (event in events) {
                if (event == Lifecycle.Event.ON_START) {
                    composition.lifecycle.onStart()
                    // The user is in the app, which shows what waits: the alerts go (iPhone removeAllDeliveredNotifications).
                    pushHooks.notifier.clearAll()
                } else {
                    composition.lifecycle.onStop()
                }
            }
        }
    }
}
