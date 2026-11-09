package com.shellx.app.platform

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.shellx.core.platform.CoreLog
import com.shellx.core.push.PushPayload
import kotlinx.coroutines.runBlocking

/** What the FCM service reaches through its Application (ShellXApplication; tests use their own). */
interface PushHost {
    val pushHooks: PushHooks
}

/** The notifier, and where a new FCM token goes (3C's `PushRegistration.tokenArrived`). */
class PushHooks(val notifier: PushNotifier, val tokenArrived: (String) -> Unit)

/**
 * FCM's data-only messages from paired Macs (contracts §8; `PushAppDelegate.swift`). A message may start the process in
 * the background; it posts or removes an alert and connects nothing. Never touches FirebaseApp in
 * [onMessageReceived], and logs neither tokens nor message text.
 */
class ShellXMessagingService : FirebaseMessagingService() {
    private val hooks: PushHooks? get() = (application as? PushHost)?.pushHooks

    /** FCM calls this on its own thread, and the process stays up until it returns. */
    override fun onMessageReceived(message: RemoteMessage) {
        val payload = PushPayload.parse(message.data)
        if (payload == null) {
            CoreLog.log("push_ignored")
            return
        }
        val notifier = hooks?.notifier ?: return
        runBlocking { notifier.handle(payload) }
    }

    override fun onNewToken(token: String) {
        hooks?.tokenArrived?.invoke(token)
    }
}
