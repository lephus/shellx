package com.shellx.core.link

import com.shellx.link.account.RelayApiException
import com.shellx.link.core.LinkClientException
import com.shellx.link.core.NoiseException

/** Why a connection to a Mac failed, as far as the reconnect loop cares (3B's `LinkConnector` failure mapping). */
enum class LinkFailure {
    /** Network, relay or session trouble: try again later. */
    OFFLINE,

    /** The relay refused the account token (401): the user must sign in again. */
    SIGNED_OUT,

    /** The Mac no longer lets this phone in (its grant is gone, or the Mac was removed). */
    REVOKED,

    /** The Mac is not the one pinned at pairing: it answered with another key, or the relay hands out tickets for
     *  another slot. */
    HOST_KEY_CHANGED,

    /** The Mac speaks another protocol version: one of the two apps needs an update. */
    NEEDS_UPDATE,
    ;

    /** True when retrying cannot help, so the reconnect loop stops. */
    val stopsReconnecting: Boolean get() = this != OFFLINE

    companion object {
        /**
         * Http(401, _) → SIGNED_OUT; Http(_, "not_granted" | "machine_not_found") → REVOKED;
         * NoiseException.UntrustedPeer, RelayApiException.SlotMismatch → HOST_KEY_CHANGED;
         * LinkClientException.ProtocolMismatch → NEEDS_UPDATE; anything else → OFFLINE.
         */
        fun of(error: Throwable): LinkFailure = when {
            error is RelayApiException.Http && error.status == 401 -> SIGNED_OUT
            error is RelayApiException.Http && (error.code == "not_granted" || error.code == "machine_not_found") -> REVOKED
            error is NoiseException.UntrustedPeer || error is RelayApiException.SlotMismatch -> HOST_KEY_CHANGED
            error is LinkClientException.ProtocolMismatch -> NEEDS_UPDATE
            else -> OFFLINE
        }
    }
}
