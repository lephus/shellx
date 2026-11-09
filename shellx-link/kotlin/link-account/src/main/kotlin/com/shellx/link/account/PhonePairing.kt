package com.shellx.link.account

import com.shellx.link.core.PairingOffer
import java.io.IOException
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

/** A Mac this phone is paired with. [hostKey] comes from the QR offer, never from the relay. The name never prints. */
data class PairedMachine(val machineId: String, val name: String, val linkSlot: String, val hostKey: ByteArray) {
    override fun equals(other: Any?): Boolean = other is PairedMachine && machineId == other.machineId &&
        name == other.name && linkSlot == other.linkSlot && hostKey.contentEquals(other.hostKey)

    override fun hashCode(): Int = ((machineId.hashCode() * 31 + name.hashCode()) * 31 + linkSlot.hashCode()) * 31 +
        hostKey.contentHashCode()

    override fun toString(): String =
        "PairedMachine(machineId=$machineId, name=<redacted>, linkSlot=$linkSlot, hostKey=<${hostKey.size} bytes>)"
}

sealed class PhonePairingException(message: String) : Exception(message) {
    /** The user pressed Deny on the Mac. */
    class Denied : PhonePairingException("denied")

    /** Nobody approved within the timeout, or the relay reports the request expired. */
    class Expired : PhonePairingException("expired")
}

object PhonePairing {
    /**
     * Sends a pairing request for the scanned offer and waits, up to [timeout], for the user to approve it on the Mac.
     * [clientKey] is the phone's Noise static **public** key (`NoiseStaticKey.publicKey`), never its private key.
     *
     * Trust comes from the offer: the host key and name are the offer's, and the machine id and link slot the relay
     * reports on approval must equal the offer's, otherwise [RelayApiException.BadResponse]. A bad offer throws its
     * `PairingOfferException` before anything reaches the relay. Network errors and 5xx answers while polling are
     * retried until the deadline; other errors are rethrown.
     *
     * [onRequested] gets the relay's pairing id once the request is sent, before the first poll: the moment a UI
     * switches to "approve on the Mac". Unless the relay itself ended the request (denied or expired), every failure,
     * cancellation included, withdraws it once, so nothing is left pending for a phone that will not pin the key.
     */
    suspend fun pair(
        offerUri: String,
        clientKey: ByteArray,
        api: RelayApi,
        token: String,
        pollInterval: Duration = 2.seconds,
        timeout: Duration = PairingOffer.LIFETIME,
        onRequested: (pairingId: String) -> Unit = {},
    ): PairedMachine {
        val offer = PairingOffer.parse(offerUri)
        val id = api.requestPairing(offer, clientKey, token)
        var relayDecided = false
        try {
            onRequested(id)
            val deadline = TimeSource.Monotonic.markNow() + timeout
            while (true) {
                currentCoroutineContext().ensureActive()
                when (val status = pollOrNull(api, id, token)) {
                    null, PhonePairingStatus.Pending -> Unit
                    PhonePairingStatus.Denied -> {
                        relayDecided = true
                        throw PhonePairingException.Denied()
                    }
                    PhonePairingStatus.Expired -> {
                        relayDecided = true
                        throw PhonePairingException.Expired()
                    }
                    is PhonePairingStatus.Approved -> {
                        if (status.machineId != offer.machineId || status.linkSlot != offer.linkSlot) {
                            throw RelayApiException.BadResponse()
                        }
                        return PairedMachine(offer.machineId, offer.machineName, offer.linkSlot, offer.hostKey.copyOf())
                    }
                }
                if (deadline.hasPassedNow()) throw PhonePairingException.Expired()
                delay(pollInterval)
            }
        } catch (e: Throwable) {
            if (!relayDecided) {
                withContext(NonCancellable) {
                    try {
                        api.cancelPairing(id, token)
                    } catch (_: Exception) {
                        // Best effort: the request expires on the relay anyway.
                    }
                }
            }
            throw e
        }
    }

    /** One poll; null for a transient failure (the network, or the relay answering 5xx). */
    private suspend fun pollOrNull(api: RelayApi, id: String, token: String): PhonePairingStatus? = try {
        api.pairingStatus(id, token)
    } catch (_: IOException) {
        null
    } catch (e: RelayApiException.Http) {
        if (e.status < 500) throw e
        null
    }
}
