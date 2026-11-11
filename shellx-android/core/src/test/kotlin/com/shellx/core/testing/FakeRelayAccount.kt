package com.shellx.core.testing

import com.shellx.core.account.RelayAccountCalling
import com.shellx.link.account.AccountSession
import com.shellx.link.account.AccountSignIn
import com.shellx.link.account.EmailChallenge
import com.shellx.link.account.PairedMachine
import com.shellx.link.account.PairedMachineListing
import com.shellx.link.core.PairingOffer
import kotlin.time.Duration
import kotlinx.coroutines.delay

/**
 * A RelayAccountCalling that records every call and answers from presets (port of FakeRelayAccount.swift, without
 * `login`, with 1C's Google and delete presets and hooks, and the email-code calls). Thread-safe; no lock is held across
 * a suspension.
 *
 * A code request answers `EmailChallenge("challenge-<n>", 600, 60, <the address trimmed and in lower case>)`, n counting
 * from 1, as the relay hands out a new challenge each time; a sign-in with a code answers [setEmailSignIn]'s preset.
 *
 * Pairing works like the relay and `PhonePairing`: the offer is parsed (a bad one throws its PairingOfferException),
 * the "Mac" approves after the approval delay, and the paired machine comes from the offer, host key included, unless
 * [setPairResult] gave another. A successful pairing adds the Mac's grant to [machines], and [unpair] removes it.
 *
 * Every call is recorded first, then runs its hook ([setHook]), then throws its preset error ([setError]), then
 * answers.
 */
class FakeRelayAccount(private val sleep: suspend (Duration) -> Unit = { delay(it) }) : RelayAccountCalling {
    sealed interface Call {
        data object Nonce : Call
        data class SignInWithGoogle(val idToken: String, val nonce: String, val deviceName: String, val clientKeyHex: String) : Call
        data class DeleteAccount(val idToken: String, val nonce: String, val token: String) : Call
        data class RequestEmailCode(val email: String, val locale: String) : Call
        data class SignInWithEmailCode(val challengeId: String, val code: String, val deviceName: String, val clientKeyHex: String) : Call
        data class DeleteAccountWithEmailCode(val challengeId: String, val code: String, val token: String) : Call
        data class Logout(val token: String) : Call
        data class Machines(val token: String) : Call
        data class Unpair(val grantId: String, val token: String) : Call
        data class Pair(val offerUri: String, val clientKeyHex: String, val token: String) : Call
        data class SetPushToken(val fcmToken: String, val token: String) : Call
        data class UnsetPushToken(val token: String) : Call
    }

    enum class Function {
        NONCE, SIGN_IN_WITH_GOOGLE, DELETE_ACCOUNT, LOGOUT, MACHINES, UNPAIR, PAIR, SET_PUSH_TOKEN, UNSET_PUSH_TOKEN,
        REQUEST_EMAIL_CODE, SIGN_IN_WITH_EMAIL_CODE, DELETE_ACCOUNT_WITH_EMAIL_CODE,
    }

    private val lock = Any()
    private val recorded = ArrayList<Call>()
    /** The next nonce, when [setNonce] chose it. */
    private var presetNonce: String? = null
    private var noncesAnswered = 0
    private var googleSignIn: Result<AccountSignIn> =
        Result.success(AccountSignIn(AccountSession("user", "device", "token"), "user@example.com"))
    private var emailSignIn: Result<AccountSignIn> =
        Result.success(AccountSignIn(AccountSession("user", "device", "token"), "user@example.com"))
    private var challengesAnswered = 0
    private val hooks = HashMap<Function, suspend () -> Unit>()
    private val errors = HashMap<Function, Exception>()
    private val grants = ArrayList<PairedMachineListing>()

    /** null: the machine described by the offer. */
    private var pairedMachine: PairedMachine? = null
    private var approvalDelay: Duration = Duration.ZERO

    val calls: List<Call> get() = synchronized(lock) { recorded.toList() }

    /**
     * The next [nonce] call answers [nonce]. Otherwise every call answers a new one, "nonce-1", "nonce-2", …, as the
     * relay's nonces are single-use (review 3a m-3).
     */
    fun setNonce(nonce: String) {
        synchronized(lock) { presetNonce = nonce }
    }

    fun setGoogleSignIn(result: Result<AccountSignIn>) {
        synchronized(lock) { googleSignIn = result }
    }

    /** What a sign-in with an emailed code answers. */
    fun setEmailSignIn(result: Result<AccountSignIn>) {
        synchronized(lock) { emailSignIn = result }
    }

    fun setGrants(grants: List<PairedMachineListing>) {
        synchronized(lock) {
            this.grants.clear()
            this.grants += grants
        }
    }

    /** Lists [machine] in [machines], as after pairing: grant "grant-<machineId>", "macos", online, fingerprint "fake". */
    fun addGrant(machine: PairedMachine) {
        synchronized(lock) {
            if (grants.any { it.machineId == machine.machineId }) return
            grants += PairedMachineListing(
                grantId = "grant-${machine.machineId}", machineId = machine.machineId, name = machine.name,
                platform = "macos", online = true, linkSlot = machine.linkSlot, fingerprint = "fake",
            )
        }
    }

    fun setError(error: Exception?, function: Function) {
        synchronized(lock) { if (error == null) errors.remove(function) else errors[function] = error }
    }

    /** [pair] answers [machine] (null: the offer's machine) after [approvalDelay]. */
    fun setPairResult(machine: PairedMachine?, approvalDelay: Duration) {
        synchronized(lock) {
            pairedMachine = machine
            this.approvalDelay = approvalDelay
        }
    }

    /** How long [pair] waits before the Mac approves. */
    fun setApprovalDelay(delay: Duration) {
        synchronized(lock) { approvalDelay = delay }
    }

    /** Runs inside [function]'s call, after it is recorded and before it answers (a 401 racing a request). */
    fun setHook(hook: (suspend () -> Unit)?, function: Function) {
        synchronized(lock) { if (hook == null) hooks.remove(function) else hooks[function] = hook }
    }

    fun resetCalls() {
        synchronized(lock) { recorded.clear() }
    }

    private suspend fun enter(call: Call, function: Function) {
        val hook = synchronized(lock) {
            recorded += call
            hooks[function]
        }
        hook?.invoke()
        synchronized(lock) { errors[function] }?.let { throw it }
    }

    override suspend fun nonce(): String {
        enter(Call.Nonce, Function.NONCE)
        return synchronized(lock) {
            noncesAnswered += 1
            presetNonce?.also { presetNonce = null } ?: "nonce-$noncesAnswered"
        }
    }

    override suspend fun signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: ByteArray): AccountSignIn {
        enter(Call.SignInWithGoogle(idToken, nonce, deviceName, clientKey.hex()), Function.SIGN_IN_WITH_GOOGLE)
        return synchronized(lock) { googleSignIn }.getOrThrow()
    }

    override suspend fun deleteAccount(idToken: String, nonce: String, token: String) {
        enter(Call.DeleteAccount(idToken, nonce, token), Function.DELETE_ACCOUNT)
    }

    override suspend fun requestEmailCode(email: String, locale: String): EmailChallenge {
        enter(Call.RequestEmailCode(email, locale), Function.REQUEST_EMAIL_CODE)
        val n = synchronized(lock) { ++challengesAnswered }
        return EmailChallenge("challenge-$n", 600, 60, email.trim().lowercase())
    }

    override suspend fun signInWithEmailCode(challengeId: String, code: String, deviceName: String, clientKey: ByteArray): AccountSignIn {
        enter(Call.SignInWithEmailCode(challengeId, code, deviceName, clientKey.hex()), Function.SIGN_IN_WITH_EMAIL_CODE)
        return synchronized(lock) { emailSignIn }.getOrThrow()
    }

    override suspend fun deleteAccountWithEmailCode(challengeId: String, code: String, token: String) {
        enter(Call.DeleteAccountWithEmailCode(challengeId, code, token), Function.DELETE_ACCOUNT_WITH_EMAIL_CODE)
    }

    override suspend fun logout(token: String) {
        enter(Call.Logout(token), Function.LOGOUT)
    }

    override suspend fun machines(token: String): List<PairedMachineListing> {
        enter(Call.Machines(token), Function.MACHINES)
        return synchronized(lock) { grants.toList() }
    }

    override suspend fun unpair(grantId: String, token: String) {
        enter(Call.Unpair(grantId, token), Function.UNPAIR)
        synchronized(lock) { grants.removeAll { it.grantId == grantId } }
    }

    override suspend fun pair(offerUri: String, clientKey: ByteArray, token: String): PairedMachine {
        enter(Call.Pair(offerUri, clientKey.hex(), token), Function.PAIR)
        val offer = PairingOffer.parse(offerUri)
        val delay = synchronized(lock) { approvalDelay }
        if (delay > Duration.ZERO) sleep(delay)
        val machine = synchronized(lock) { pairedMachine }
            ?: PairedMachine(offer.machineId, offer.machineName, offer.linkSlot, offer.hostKey.copyOf())
        addGrant(machine)
        return machine
    }

    override suspend fun setPushToken(fcmToken: String, token: String) {
        enter(Call.SetPushToken(fcmToken, token), Function.SET_PUSH_TOKEN)
    }

    override suspend fun unsetPushToken(token: String) {
        enter(Call.UnsetPushToken(token), Function.UNSET_PUSH_TOKEN)
    }
}
