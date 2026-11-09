package com.shellx.app.platform

import com.google.firebase.messaging.FirebaseMessaging
import com.shellx.core.platform.CoreLog
import com.shellx.core.push.PushRegistrar
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/**
 * 3C's [PushRegistrar] over FCM (contracts §5, §8). FCM's auto-init is off in the manifest, so no token and no
 * Firebase installation exist until the first [currentToken], which 3C's `PushRegistration` calls only while a session
 * is stored (contracts §25: never while signed out). The first call turns auto-init on, so FCM keeps the token fresh
 * from then on. Any failure (no Play services, no network, Firebase not set up) is null. The token is never logged.
 */
class FcmPushRegistrar(private val messaging: () -> FirebaseMessaging = FirebaseMessaging::getInstance) : PushRegistrar {
    override suspend fun currentToken(): String? = try {
        val fcm = messaging()
        fcm.isAutoInitEnabled = true
        fcm.token.await()
    } catch (e: CancellationException) {
        currentCoroutineContext().ensureActive()
        CoreLog.log("push_token_cancelled")
        null
    } catch (e: Exception) {
        CoreLog.log("push_token_failed ${e.javaClass.simpleName}")
        null
    }
}
