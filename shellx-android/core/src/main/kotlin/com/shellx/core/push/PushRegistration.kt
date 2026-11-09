package com.shellx.core.push

import com.shellx.core.account.AccountVault
import com.shellx.core.account.RelayAccountCalling
import com.shellx.core.account.StoredSession
import com.shellx.core.platform.rethrowIfCancelled

/**
 * Keeps the relay holding this phone's FCM token while it is signed in, so a paired Mac can reach it while the app is
 * closed (contracts §8: `PUT /v1/devices/me/push-token`). Port of PushRegistration.swift with FCM tokens:
 * `setPushToken(fcmToken, session token)`. A token and session pair is sent once; again after a failure, after
 * [appBecameActive], or after another sign-in.
 *
 * Session guard: every path that would call `registrar.currentToken()` first reads `vault.session()`. With no session
 * it returns before calling the registrar, so a signed-out phone never requests or creates an FCM token (plan 3H's
 * Data safety answers rely on this). A token that arrives while signed out is kept, and sent at the next [signedIn].
 *
 * Main-confined. Tokens never print or reach `CoreLog`.
 */
class PushRegistration(
    private val relay: RelayAccountCalling,
    private val vault: AccountVault,
    private val registrar: PushRegistrar,
) {
    private class Sent(val fcmToken: String, val session: String)

    private var latest: String? = null

    /** The FCM token and session token the relay last accepted. */
    private var sent: Sent? = null

    /** `FirebaseMessagingService.onNewToken` (3E). Never asks the registrar. */
    suspend fun tokenArrived(token: String) {
        latest = token
        val session = session() ?: return
        send(token, session)
    }

    /** A session exists now (launch, sign-in, or the first Mac paired). Asks the registrar when no token arrived
     *  yet. */
    suspend fun signedIn() {
        val session = session() ?: return
        val token = latest ?: ask() ?: return
        send(token, session)
    }

    /** The app came to the front. The relay deletes a token FCM calls gone while this phone still remembers sending
     *  it, so forget that and send the known token again; with a session and no known token, ask the registrar. */
    suspend fun appBecameActive() {
        sent = null
        val session = session() ?: return
        val token = latest ?: ask() ?: return
        send(token, session)
    }

    /** The stored session, or null (none, or the vault failed: nothing is sent). Read before any registrar call. */
    private suspend fun session(): StoredSession? = try {
        vault.session()
    } catch (e: Exception) {
        rethrowIfCancelled(e)
        null
    }

    /** Called only with a stored session (the session guard). */
    private suspend fun ask(): String? {
        val token = try {
            registrar.currentToken()
        } catch (e: Exception) {
            rethrowIfCancelled(e)
            null
        }?.takeIf { it.isNotEmpty() } ?: return null
        latest = latest ?: token
        return latest
    }

    private suspend fun send(token: String, session: StoredSession) {
        val last = sent
        if (last != null && last.fcmToken == token && last.session == session.token) return
        try {
            relay.setPushToken(token, session.token)
            sent = Sent(token, session.token)
        } catch (e: Exception) {
            rethrowIfCancelled(e)
            // Not sent: the next sign-in, return to the front or token tries again.
        }
    }
}
