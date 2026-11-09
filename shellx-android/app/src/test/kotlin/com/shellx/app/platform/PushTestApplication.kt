package com.shellx.app.platform

import android.app.Application

/** The FCM service's [PushHost] in tests: the app's foreground state, the paired Macs and the tokens received. */
class PushTestApplication : Application(), PushHost {
    var foreground = false
    var machines: Set<String>? = setOf("m1")
    val tokens = mutableListOf<String>()

    override val pushHooks: PushHooks by lazy { PushHooks(PushNotifier(this, { foreground }, { machines })) { tokens += it } }
}
