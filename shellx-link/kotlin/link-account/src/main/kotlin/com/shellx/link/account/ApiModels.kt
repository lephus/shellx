package com.shellx.link.account

import com.shellx.link.core.RelayTicket
import java.net.URI

/** A signed-in phone. The token is a bearer secret and never prints. */
data class AccountSession(val userId: String, val deviceId: String, val token: String) {
    override fun toString(): String = "AccountSession(user=$userId, device=$deviceId, <redacted>)"
}

/**
 * A session the relay handed out for a sign-in (Google, or an emailed code), with the account's email. Neither the
 * token nor the email prints.
 */
data class AccountSignIn(val session: AccountSession, val email: String) {
    override fun toString(): String = "AccountSignIn(user=${session.userId}, device=${session.deviceId}, <redacted>)"
}

/**
 * What the relay answers to a code request (`POST /v1/auth/email/code`): the challenge the mailed code belongs to, how
 * many seconds the code lives ([expiresIn]) and how long until another one may be asked for ([resendIn]), and the
 * address as the relay normalized it. Neither the challenge nor the email prints.
 */
data class EmailChallenge(val challengeId: String, val expiresIn: Int, val resendIn: Int, val email: String) {
    override fun toString(): String = "EmailChallenge(expiresIn=$expiresIn, resendIn=$resendIn, <redacted>)"
}

/** How a phone pairing request stands (`GET /v2/phone-pairings/<id>`). */
sealed interface PhonePairingStatus {
    data object Pending : PhonePairingStatus

    /** The relay's view of the machine. The phone trusts the offer's machine, slot and key, not these. */
    data class Approved(val machineId: String, val name: String, val linkSlot: String) : PhonePairingStatus {
        override fun toString(): String = "Approved(machineId=$machineId, name=<redacted>, linkSlot=$linkSlot)"
    }

    data object Denied : PhonePairingStatus

    data object Expired : PhonePairingStatus
}

/** A machine this phone may connect to, as the relay lists it (`GET /v2/phone-grants`). */
data class PairedMachineListing(
    val grantId: String,
    val machineId: String,
    val name: String,
    val platform: String,
    val online: Boolean,
    val linkSlot: String,
    val fingerprint: String,
) {
    override fun toString(): String = "PairedMachineListing(grantId=$grantId, machineId=$machineId, name=<redacted>, " +
        "platform=$platform, online=$online, linkSlot=$linkSlot, fingerprint=$fingerprint)"
}

/** A link-lane connect ticket and the relay that takes it. The ticket never prints. */
data class MintedTicket(val ticket: RelayTicket, val relayUrl: URI)

/** Errors from the ShellX relay HTTP API. */
sealed class RelayApiException(message: String) : Exception(message) {
    /** A non-2xx answer; [code] is its `error.code`, or `"unknown"` when the body has none. */
    data class Http(val status: Int, val code: String) : RelayApiException("http $status $code")

    /** The answer was not what the API documents, or contradicts what the phone already trusts. */
    class BadResponse : RelayApiException("bad_response")

    /** A minted ticket is for another slot than the machine's link slot. */
    class SlotMismatch : RelayApiException("slot_mismatch")

    /** A minted ticket does not carry the `connect` permission. */
    class NotConnectTicket : RelayApiException("not_connect_ticket")
}
