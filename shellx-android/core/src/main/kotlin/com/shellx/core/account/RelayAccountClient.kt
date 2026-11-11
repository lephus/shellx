package com.shellx.core.account

import com.shellx.link.account.AccountSignIn
import com.shellx.link.account.EmailChallenge
import com.shellx.link.account.PairedMachine
import com.shellx.link.account.PairedMachineListing
import com.shellx.link.account.PhonePairing
import com.shellx.link.account.RelayApi

/** The relay calls of [RelayAccountCalling] over 3B's [RelayApi]. Every call goes to [api]; [pair] is
 *  `PhonePairing.pair(offerUri, clientKey, api, token)`. Calls are main-safe (OkHttp enqueue). */
class RelayAccountClient(val api: RelayApi) : RelayAccountCalling {
    override suspend fun nonce(): String = api.nonce()

    override suspend fun signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: ByteArray): AccountSignIn =
        api.signInWithGoogle(idToken, nonce, deviceName, clientKey)

    override suspend fun deleteAccount(idToken: String, nonce: String, token: String) {
        api.deleteAccount(idToken, nonce, token)
    }

    override suspend fun requestEmailCode(email: String, locale: String): EmailChallenge = api.requestEmailCode(email, locale)

    override suspend fun signInWithEmailCode(challengeId: String, code: String, deviceName: String, clientKey: ByteArray): AccountSignIn =
        api.signInWithEmailCode(challengeId, code, deviceName, clientKey)

    override suspend fun deleteAccountWithEmailCode(challengeId: String, code: String, token: String) {
        api.deleteAccountWithEmailCode(challengeId, code, token)
    }

    override suspend fun logout(token: String) {
        api.logout(token)
    }

    override suspend fun machines(token: String): List<PairedMachineListing> = api.machines(token)

    override suspend fun unpair(grantId: String, token: String) {
        api.unpair(grantId, token)
    }

    override suspend fun pair(offerUri: String, clientKey: ByteArray, token: String): PairedMachine =
        PhonePairing.pair(offerUri, clientKey, api, token)

    override suspend fun setPushToken(fcmToken: String, token: String) {
        api.setPushToken(fcmToken, token)
    }

    override suspend fun unsetPushToken(token: String) {
        api.unsetPushToken(token)
    }
}
