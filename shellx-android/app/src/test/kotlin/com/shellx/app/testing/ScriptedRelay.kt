package com.shellx.app.testing

import com.shellx.core.account.RelayAccountCalling
import com.shellx.core.demo.DemoRelay
import com.shellx.link.account.AccountSession
import com.shellx.link.account.AccountSignIn
import com.shellx.link.account.PairedMachine
import com.shellx.link.account.PairedMachineListing
import kotlin.time.Duration

/**
 * The relay in `:app` tests: the account calls answer from presets ([signIn], [delete]); machines, unpair, pair and
 * logout go to a `DemoRelay(paired, pairable, approvalDelay = Duration.ZERO)`, and push calls do nothing. Every call is
 * recorded by name in [calls]: "nonce", "google:<idToken>", "delete:<idToken>", "logout", "machines",
 * "unpair:<grantId>", "pair", "push:set", "push:unset". Thread-safe.
 */
class ScriptedRelay(paired: List<PairedMachine> = emptyList(), pairable: Set<String> = emptySet()) : RelayAccountCalling {
    private val demo = DemoRelay(paired, pairable, Duration.ZERO)
    private val recorded = mutableListOf<String>()
    private var nonces = 0

    @Volatile var signIn: Result<AccountSignIn> =
        Result.success(AccountSignIn(AccountSession("u1", "d1", "tok-1"), "phu@example.com"))

    @Volatile var delete: Result<Unit> = Result.success(Unit)

    val calls: List<String> get() = synchronized(recorded) { recorded.toList() }

    private fun record(call: String) {
        synchronized(recorded) { recorded += call }
    }

    override suspend fun nonce(): String {
        record("nonce")
        return "nonce-${synchronized(recorded) { ++nonces }}"
    }

    override suspend fun signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: ByteArray): AccountSignIn {
        record("google:$idToken")
        return signIn.getOrThrow()
    }

    override suspend fun deleteAccount(idToken: String, nonce: String, token: String) {
        record("delete:$idToken")
        delete.getOrThrow()
    }

    override suspend fun logout(token: String) {
        record("logout")
        demo.logout(token)
    }

    override suspend fun machines(token: String): List<PairedMachineListing> {
        record("machines")
        return demo.machines(token)
    }

    override suspend fun unpair(grantId: String, token: String) {
        record("unpair:$grantId")
        demo.unpair(grantId, token)
    }

    override suspend fun pair(offerUri: String, clientKey: ByteArray, token: String): PairedMachine {
        record("pair")
        return demo.pair(offerUri, clientKey, token)
    }

    override suspend fun setPushToken(fcmToken: String, token: String) {
        record("push:set")
    }

    override suspend fun unsetPushToken(token: String) {
        record("push:unset")
    }
}
