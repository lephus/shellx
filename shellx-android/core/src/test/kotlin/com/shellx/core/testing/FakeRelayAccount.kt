package com.shellx.core.testing

import com.shellx.core.account.RelayAccountCalling
import com.shellx.link.account.AccountSession
import com.shellx.link.account.AccountSignIn
import com.shellx.link.account.PairedMachine
import com.shellx.link.account.PairedMachineListing
import com.shellx.link.core.PairingOffer
import kotlin.time.Duration
import kotlinx.coroutines.delay

/**
 * A RelayAccountCalling that records every call and answers from presets (port of FakeRelayAccount.swift, without
 * `login`, with 1C's Google and delete presets and hooks). Thread-safe; no lock is held across a suspension.
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
        data class Logout(val token: String) : Call
        data class Machines(val token: String) : Call
        data class Unpair(val grantId: String, val token: String) : Call
        data class Pair(val offerUri: String, val clientKeyHex: String, val token: String) : Call
        data class SetPushToken(val fcmToken: String, val token: String) : Call
        data class UnsetPushToken(val token: String) : Call
    }

    enum class Function { NONCE, SIGN_IN_WITH_GOOGLE, DELETE_ACCOUNT, LOGOUT, MACHINES, UNPAIR, PAIR, SET_PUSH_TOKEN, UNSET_PUSH_TOKEN }

    private val lock = Any()
    private val recorded = ArrayList<Call>()
    private var nonceValue = "nonce-1"
    private var googleSignIn: Result<AccountSignIn> =
        Result.success(AccountSignIn(AccountSession("user", "device", "token"), "user@example.com"))
    private val hooks = HashMap<Function, suspend () -> Unit>()
    private val errors = HashMap<Function, Exception>()
    private val grants = ArrayList<PairedMachineListing>()

    /** null: the machine described by the offer. */
    private var pairedMachine: PairedMachine? = null
    private var approvalDelay: Duration = Duration.ZERO

    val calls: List<Call> get() = synchronized(lock) { recorded.toList() }

    fun setNonce(nonce: String) {
        synchronized(lock) { nonceValue = nonce }
    }

    fun setGoogleSignIn(result: Result<AccountSignIn>) {
        synchronized(lock) { googleSignIn = result }
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
        return synchronized(lock) { nonceValue }
    }

    override suspend fun signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: ByteArray): AccountSignIn {
        enter(Call.SignInWithGoogle(idToken, nonce, deviceName, clientKey.hex()), Function.SIGN_IN_WITH_GOOGLE)
        return synchronized(lock) { googleSignIn }.getOrThrow()
    }

    override suspend fun deleteAccount(idToken: String, nonce: String, token: String) {
        enter(Call.DeleteAccount(idToken, nonce, token), Function.DELETE_ACCOUNT)
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
