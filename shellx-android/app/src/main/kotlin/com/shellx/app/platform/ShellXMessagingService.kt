package com.shellx.app.platform

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.shellx.core.platform.CoreLog
import com.shellx.core.push.PushPayload
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull

/** What the FCM service reaches through its Application (ShellXApplication; tests use their own). */
interface PushHost {
    val pushHooks: PushHooks
}

/** The notifier, and where a new FCM token goes (3C's `PushRegistration.tokenArrived`): [tokenArrived] returns once the
 *  relay has it, or the attempt ended. */
class PushHooks(val notifier: PushNotifier, val tokenArrived: suspend (String) -> Unit)

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

    /**
     * FCM calls this on its own thread too. As [onMessageReceived], the relay work is done before it returns: FCM may
     * have started the process for the token alone, and the process can die once the service is done (review C m-7).
     * At most [TOKEN_TIMEOUT]; a token not sent by then is sent at the app's next start in front.
     */
    override fun onNewToken(token: String) {
        val arrived = hooks?.tokenArrived ?: return
        runBlocking { withTimeoutOrNull(TOKEN_TIMEOUT) { arrived(token) } }
    }

    companion object {
        /** How long [onNewToken] waits for the relay. */
        val TOKEN_TIMEOUT: Duration = 10.seconds
    }
}
