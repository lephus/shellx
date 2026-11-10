package com.shellx.app.platform

import com.google.firebase.messaging.FirebaseMessaging
import com.shellx.core.account.AppPhase
import com.shellx.core.platform.CoreLog
import com.shellx.core.push.PushRegistrar
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/** The FCM calls [FcmPushRegistrar] makes (FirebaseMessaging is final; tests give a fake). */
interface FcmMessaging {
    fun setAutoInit(enabled: Boolean)

    suspend fun token(): String

    companion object {
        /** Firebase's own; throws when Firebase is not set up (no `google-services.json`). */
        fun firebase(): FcmMessaging = FirebaseFcmMessaging(FirebaseMessaging.getInstance())
    }
}

private class FirebaseFcmMessaging(private val fcm: FirebaseMessaging) : FcmMessaging {
    override fun setAutoInit(enabled: Boolean) {
        fcm.isAutoInitEnabled = enabled
    }

    override suspend fun token(): String = fcm.token.await()
}

/**
 * 3C's [PushRegistrar] over FCM (contracts §5, §8). FCM's auto-init is off in the manifest, so no token and no
 * Firebase installation exist until the first [currentToken], which 3C's `PushRegistration` calls only while a session
 * is stored (contracts §25: never while signed out). That call turns auto-init on, so FCM keeps the token fresh while
 * signed in; each sign-out turns it off again ([followSignOuts]), so a signed-out phone stops syncing the token with
 * Google (review C concern 7). The token itself is not deleted (3C's `PushRegistration` would still send it at the next
 * sign-in). Any failure (no Play services, no network, Firebase not set up) is null. The token is never logged.
 */
class FcmPushRegistrar(private val messaging: () -> FcmMessaging = FcmMessaging::firebase) : PushRegistrar {
    override suspend fun currentToken(): String? = try {
        val fcm = messaging()
        fcm.setAutoInit(true)
        fcm.token()
    } catch (e: CancellationException) {
        currentCoroutineContext().ensureActive()
        CoreLog.log("push_token_cancelled")
        null
    } catch (e: Exception) {
        CoreLog.log("push_token_failed ${e.javaClass.simpleName}")
        null
    }

    /** Signed out: FCM stops refreshing the token until the next [currentToken] for a signed-in account. */
    fun signedOut() {
        try {
            messaging().setAutoInit(false)
        } catch (e: Exception) {
            CoreLog.log("push_auto_init_off_failed ${e.javaClass.simpleName}")
        }
    }

    /** Until cancelled: [signedOut] each time [phase] (the real account's) turns signed out, a launch without a session
     *  included (a phone signed out by an older version). */
    suspend fun followSignOuts(phase: Flow<AppPhase>) {
        phase.map { it is AppPhase.SignedOut }.distinctUntilChanged().collect { out -> if (out) signedOut() }
    }
}
