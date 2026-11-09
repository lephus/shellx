package com.shellx.core.pairing

import com.shellx.core.account.AccountVault
import com.shellx.core.account.RelayAccountCalling
import com.shellx.core.link.LinkFailure
import com.shellx.core.link.MachineHub
import com.shellx.core.platform.CoreLog
import com.shellx.core.platform.rethrowIfCancelled
import com.shellx.link.account.PairedMachine
import com.shellx.link.core.PairingOffer
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Pairing this phone with a Mac from its QR code (or a pasted or opened `shellx-link://` code).
 *
 * A code is only read by [begin]; nothing reaches the network until the user confirms the Mac's name, so a link opened
 * from elsewhere can never pair by itself. [confirm] then asks the relay, waits for the user to press Allow on the Mac,
 * and hands the Mac to the hub, which saves it and connects.
 *
 * The code holds a one-time secret: it is kept in memory only until the attempt ends, and never logged.
 *
 * Main-confined. The attempt runs in [scope] and [confirm] only waits for it: cancelling the caller (the screen went
 * away) never loses a Mac that said Allow.
 */
class PairingModel(
    private val hub: MachineHub,
    private val relay: RelayAccountCalling,
    private val vault: AccountVault,
    private val scope: CoroutineScope,
) {
    sealed interface Step {
        /** Waiting for a code (the scanner is showing). */
        data object Idle : Step

        /** A valid code: ask "Pair with <name>?" before anything else happens. */
        data class Confirm(val machineName: String) : Step {
            override fun toString(): String = "Confirm(machineName=<redacted>)"
        }

        /** The request is with the Mac; the user must press Allow there. */
        data class WaitingForMac(val machineName: String) : Step {
            override fun toString(): String = "WaitingForMac(machineName=<redacted>)"
        }

        data class Paired(val machineName: String) : Step {
            override fun toString(): String = "Paired(machineName=<redacted>)"
        }

        data class Failed(val failure: PairingFailure) : Step
    }

    private val _step = MutableStateFlow<Step>(Step.Idle)
    val step: StateFlow<Step> = _step.asStateFlow()

    /** The code being confirmed or paired; null otherwise. */
    private var offerUri: String? = null

    /** The current attempt; replaced or dropped when it ends. */
    private var attempt: Job? = null

    /**
     * Reads a code from the scanner, the clipboard or an opened link. A valid one moves to Confirm; anything else to
     * Failed. Never touches the network. A code arriving while an attempt is under way replaces it.
     */
    fun begin(uri: String) {
        reset()
        val text = lowercasingScheme(uri.trim())
        try {
            val offer = PairingOffer.parse(text)
            offerUri = text
            _step.value = Step.Confirm(offer.machineName)
        } catch (e: Exception) {
            val failure = PairingFailure.of(e)
            CoreLog.log("pairing_code_refused $failure")
            _step.value = Step.Failed(failure)
        }
    }

    /**
     * The user confirmed the Mac: sends the request with this phone's key and waits for the Mac's answer. Returns when
     * the attempt ended (paired, failed, or cancelled by [cancel]). Cancelling the caller only ends its wait: the
     * attempt goes on in the model's scope.
     */
    suspend fun confirm() {
        val name = (_step.value as? Step.Confirm)?.machineName ?: return
        val uri = offerUri ?: return
        _step.value = Step.WaitingForMac(name)
        val job = scope.launch(start = CoroutineStart.UNDISPATCHED) {
            // Set before the first suspension, so the attempt is current from its first line.
            attempt = coroutineContext.job
            runAttempt(uri, coroutineContext.job)
        }
        job.join()
    }

    /** Stops waiting for the Mac (the relay request is withdrawn) and goes back to Idle. Also what closing the sheet
     *  does, whatever the step. */
    fun cancel() {
        reset()
        _step.value = Step.Idle
    }

    /**
     * Kotlin discards the result of a cancelled coroutine, so Swift's "take the late approval, then withdraw it" is
     * explicit: an approval that comes back to a cancelled or replaced attempt is withdrawn here.
     */
    private suspend fun runAttempt(uri: String, thisJob: Job) {
        val approval = try {
            val clientKey = vault.phoneKey().publicKey
            val token = vault.session()?.token ?: throw MachineHub.AddException.NotSignedIn()
            Approval(relay.pair(uri, clientKey, token), token)
        } catch (e: Exception) {
            // A CancellationException of the attempt itself ends it; one the call threw of its own is a failure.
            rethrowIfCancelled(e)
            if (attempt === thisJob) fail(e)
            return
        }
        // Cancelled or replaced while the Mac answered: this attempt no longer speaks, and the grant the relay just
        // made would be left behind.
        if (attempt !== thisJob || !thisJob.isActive) {
            withContext(NonCancellable) { withdraw(approval) }
            return
        }
        try {
            withContext(NonCancellable) { hub.add(approval.machine) }
        } catch (e: Exception) {
            withContext(NonCancellable) { withdraw(approval) }
            rethrowIfCancelled(e)
            if (attempt === thisJob) fail(e)
            return
        }
        if (attempt === thisJob) finish(Step.Paired(approval.machine.name))
    }

    private suspend fun fail(error: Exception) {
        val failure = PairingFailure.of(error)
        CoreLog.log("pairing_failed $failure")
        finish(Step.Failed(failure))
        // A refused token cannot pair, however often the user retries: back to the "session expired" sign-in, the way
        // the hub handles a 401 anywhere else.
        if (LinkFailure.of(error) == LinkFailure.SIGNED_OUT) hub.reportUnauthorized()
    }

    /**
     * The relay granted this phone a Mac it is not keeping (the attempt was cancelled or replaced, or saving the Mac
     * failed): takes the grant back, so the Mac does not list a phone that does not know it. Best effort, errors only
     * logged. A Mac this phone already keeps (a cancelled re-pair) keeps its grant: it is not an orphan.
     */
    private suspend fun withdraw(approval: Approval) {
        val machineId = approval.machine.machineId
        if (hub.machines.any { it.id == machineId }) return
        try {
            for (grant in relay.machines(approval.token)) {
                if (grant.machineId == machineId) relay.unpair(grant.grantId, approval.token)
            }
        } catch (e: Exception) {
            rethrowIfCancelled(e)
            CoreLog.log("pairing_withdraw_failed")
        }
    }

    private fun finish(outcome: Step) {
        attempt = null
        offerUri = null
        _step.value = outcome
    }

    private fun reset() {
        attempt?.cancel()
        attempt = null
        offerUri = null
    }

    /** What the relay answered for an attempt, with the token it was made with. Never prints the token. */
    private class Approval(val machine: PairedMachine, val token: String) {
        override fun toString(): String = "Approval(machine=$machine, <redacted>)"
    }

    companion object {
        /**
         * The system opens the app for `SHELLX-LINK://…` too, and a QR code may carry the scheme in capitals, but
         * PairingOffer parses only the lowercase scheme: lowercase it first, so every way in (link, scan, paste) agrees
         * with the parser.
         */
        internal fun lowercasingScheme(text: String): String {
            val colon = text.indexOf(':')
            if (colon < 0 || text.substring(0, colon).lowercase(Locale.ROOT) != PairingInbox.SCHEME) return text
            return PairingInbox.SCHEME + text.substring(colon)
        }
    }
}
