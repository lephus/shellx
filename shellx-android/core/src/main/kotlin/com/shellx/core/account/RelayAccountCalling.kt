package com.shellx.core.account

import com.shellx.link.account.AccountSignIn
import com.shellx.link.account.EmailChallenge
import com.shellx.link.account.PairedMachine
import com.shellx.link.account.PairedMachineListing

/**
 * The relay calls the app needs (contracts §2, §8). [RelayAccountClient] is the real one; tests use FakeRelayAccount;
 * the demo uses DemoRelay (Task 29). Sign-in is Google's or an emailed code's; Android has no password, Apple or
 * Google-link calls (contracts §5).
 *
 * `clientKey` is the phone's Noise static **public** key (`NoiseStaticKey.publicKey`), never its private key.
 */
interface RelayAccountCalling {
    suspend fun nonce(): String

    suspend fun signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: ByteArray): AccountSignIn

    suspend fun deleteAccount(idToken: String, nonce: String, token: String)

    /** Asks the relay to mail a sign-in code to [email], written in [locale] ("en" or "vi"). */
    suspend fun requestEmailCode(email: String, locale: String): EmailChallenge

    /** Signs this phone in with the code mailed for [challengeId]. */
    suspend fun signInWithEmailCode(challengeId: String, code: String, deviceName: String, clientKey: ByteArray): AccountSignIn

    /** Deletes the account of [token], proven by a code mailed to its address. */
    suspend fun deleteAccountWithEmailCode(challengeId: String, code: String, token: String)

    suspend fun logout(token: String)

    suspend fun machines(token: String): List<PairedMachineListing>

    suspend fun unpair(grantId: String, token: String)

    /** Pairs with the Mac of the scanned offer and waits for its Allow. Cancelling it withdraws the pairing. */
    suspend fun pair(offerUri: String, clientKey: ByteArray, token: String): PairedMachine

    /** This phone's FCM registration token. */
    suspend fun setPushToken(fcmToken: String, token: String)

    suspend fun unsetPushToken(token: String)
}
