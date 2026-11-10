package com.shellx.app.platform

import android.app.Activity
import android.app.Application
import android.os.Bundle
import java.lang.ref.WeakReference
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.mapNotNull

/**
 * The resumed activity, weakly held; ShellXApplication registers [shared] (Task 8). Google's sign-in sheet is an
 * activity started over ours, and Android may block one started from the background, leaving the sign-in without an
 * answer (final review F-2), so the sheet waits for [awaitResumed]. Sign-in and deletion outlive their screen, so they
 * ask for the activity when they need it instead of holding one. Set on the main thread, read from any.
 */
class ActivityTracker : Application.ActivityLifecycleCallbacks {
    private val resumed = MutableStateFlow<WeakReference<Activity>?>(null)

    /** The resumed activity, at once or as soon as one is resumed. Cancellable; it holds no activity while it waits. */
    suspend fun awaitResumed(): Activity = resumed.mapNotNull { it?.get() }.first()

    override fun onActivityResumed(activity: Activity) {
        resumed.value = WeakReference(activity)
    }

    override fun onActivityPaused(activity: Activity) = forget(activity)

    override fun onActivityDestroyed(activity: Activity) = forget(activity)

    /** A window that pauses after another one resumed (a page opened over it) leaves the other one current. */
    private fun forget(activity: Activity) {
        if (resumed.value?.get() === activity) resumed.value = null
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}

    override fun onActivityStarted(activity: Activity) {}

    override fun onActivityStopped(activity: Activity) {}

    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}

    companion object {
        /** The app's tracker. */
        val shared = ActivityTracker()
    }
}
