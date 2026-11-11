package com.shellx.core.demo

import com.shellx.core.account.RelayAccountCalling
import com.shellx.link.account.AccountSignIn
import com.shellx.link.account.EmailChallenge
import com.shellx.link.account.PairedMachine
import com.shellx.link.account.PairedMachineListing
import com.shellx.link.account.RelayApiException
import com.shellx.link.core.PairingOffer
import kotlin.time.Duration
import kotlinx.coroutines.delay

/**
 * The demo's relay (1C Task 12): no network. [machines] lists one grant per paired Mac in pairing order
 * ("grant-<machineId>", "macos", online, its linkSlot, fingerprint "demo"); [unpair] removes by grantId. [pair] parses
 * the offer (its error is thrown); a machine outside `pairableMachineIds` is `Http(404, "machine_not_found")`;
 * otherwise it waits `approvalDelay` with `sleep`, lists the Mac and returns the offer's PairedMachine. [logout],
 * [setPushToken] and [unsetPushToken] do nothing; [nonce], [signInWithGoogle], [deleteAccount] and the three email-code
 * calls throw [REFUSAL]. Thread-safe.
 */
class DemoRelay(
    paired: List<PairedMachine>,
    private val pairableMachineIds: Set<String>,
    private val approvalDelay: Duration,
    private val sleep: suspend (Duration) -> Unit = { delay(it) },
) : RelayAccountCalling {
    private val lock = Any()
    private val paired = ArrayList(paired)

    override suspend fun machines(token: String): List<PairedMachineListing> = synchronized(lock) {
        paired.map {
            PairedMachineListing(
                grantId = "grant-${it.machineId}", machineId = it.machineId, name = it.name, platform = "macos",
                online = true, linkSlot = it.linkSlot, fingerprint = "demo",
            )
        }
    }

    override suspend fun unpair(grantId: String, token: String) {
        synchronized(lock) { paired.removeAll { "grant-${it.machineId}" == grantId } }
    }

    override suspend fun pair(offerUri: String, clientKey: ByteArray, token: String): PairedMachine {
        val offer = PairingOffer.parse(offerUri)
        if (offer.machineId !in pairableMachineIds) throw RelayApiException.Http(404, "machine_not_found")
        if (approvalDelay > Duration.ZERO) sleep(approvalDelay)
        val machine = PairedMachine(offer.machineId, offer.machineName, offer.linkSlot, offer.hostKey)
        synchronized(lock) { if (paired.none { it.machineId == machine.machineId }) paired += machine }
        return machine
    }

    override suspend fun logout(token: String) {}

    override suspend fun setPushToken(fcmToken: String, token: String) {}

    override suspend fun unsetPushToken(token: String) {}

    override suspend fun nonce(): String = throw REFUSAL

    override suspend fun signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: ByteArray): AccountSignIn =
        throw REFUSAL

    override suspend fun deleteAccount(idToken: String, nonce: String, token: String) {
        throw REFUSAL
    }

    override suspend fun requestEmailCode(email: String, locale: String): EmailChallenge = throw REFUSAL

    override suspend fun signInWithEmailCode(challengeId: String, code: String, deviceName: String, clientKey: ByteArray): AccountSignIn =
        throw REFUSAL

    override suspend fun deleteAccountWithEmailCode(challengeId: String, code: String, token: String) {
        throw REFUSAL
    }

    companion object {
        /** What every account call throws: a new instance each time. */
        val REFUSAL: RelayApiException.Http get() = RelayApiException.Http(403, "demo")
    }
}
