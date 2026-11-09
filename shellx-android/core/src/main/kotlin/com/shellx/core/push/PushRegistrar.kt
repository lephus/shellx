package com.shellx.core.push

/**
 * The platform's push service (contracts §5; 3E implements it with `FirebaseMessaging.getToken()`). Asking may create
 * an FCM token, so [PushRegistration] asks only while a session is stored.
 */
interface PushRegistrar {
    /** This phone's FCM token; null when there is none (no Play services, not issued yet). */
    suspend fun currentToken(): String?
}
