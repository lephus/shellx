package com.shellx.app.platform

import android.app.Activity
import android.app.Application
import android.os.Bundle
import java.lang.ref.WeakReference

/**
 * The current (latest started or resumed, not destroyed) activity, weakly held; registered by ShellXApplication
 * (Task 8). Google's sign-in sheet needs an activity to show over, and sign-in and deletion outlive their screen, so
 * they ask for the activity when they need it instead of holding one. Main thread only, like the callbacks.
 */
object ActivityTracker : Application.ActivityLifecycleCallbacks {
    private var current: WeakReference<Activity>? = null

    fun current(): Activity? = current?.get()

    override fun onActivityStarted(activity: Activity) {
        current = WeakReference(activity)
    }

    override fun onActivityResumed(activity: Activity) {
        current = WeakReference(activity)
    }

    override fun onActivityDestroyed(activity: Activity) {
        if (current?.get() === activity) current = null
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}

    override fun onActivityPaused(activity: Activity) {}

    override fun onActivityStopped(activity: Activity) {}

    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
}
