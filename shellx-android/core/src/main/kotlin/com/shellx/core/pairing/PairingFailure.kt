package com.shellx.core.pairing

import com.shellx.core.account.SecretStoreException
import com.shellx.core.link.MachineHub
import com.shellx.link.account.PhonePairingException
import com.shellx.link.account.RelayApiException
import com.shellx.link.core.PairingOfferException
import java.io.IOException

/** Why pairing with a Mac did not work, as the pairing sheet tells it. */
sealed interface PairingFailure {
    /** The text or QR code is not a `shellx-link://pair` code. */
    data object NotShellXCode : PairingFailure

    /** The code is from a newer ShellX (another `v`): this app needs an update. */
    data object NeedsUpdate : PairingFailure

    /** A ShellX code with a missing or malformed field. */
    data object DamagedCode : PairingFailure

    /** The user pressed Deny on the Mac. */
    data object Denied : PairingFailure

    /** Nobody pressed Allow on the Mac in time. */
    data object Expired : PairingFailure

    /** The relay does not know the Mac under this account: it belongs to another one. */
    data object OtherAccount : PairingFailure

    /** The relay could not be reached. */
    data object Network : PairingFailure

    /** Anything else; [code] is the relay's error code (never a secret). */
    data class Server(val code: String) : PairingFailure

    companion object {
        /**
         * PairingOfferException BadUri / UnsupportedVersion / BadField → NotShellXCode / NeedsUpdate / DamagedCode;
         * PhonePairingException Denied / Expired → Denied / Expired; Http(_, "machine_not_found") → OtherAccount;
         * IOException → Network; Http(_, code) → Server(code); BadResponse → Server("bad_response");
         * SecretStoreException → Server("keychain"); MachineHub.AddException.NotSignedIn → Server("signed_out");
         * else Server("unknown").
         */
        fun of(error: Throwable): PairingFailure = when (error) {
            is PairingOfferException.BadUri -> NotShellXCode
            is PairingOfferException.UnsupportedVersion -> NeedsUpdate
            is PairingOfferException.BadField -> DamagedCode
            is PhonePairingException.Denied -> Denied
            is PhonePairingException.Expired -> Expired
            is RelayApiException.Http -> if (error.code == "machine_not_found") OtherAccount else Server(error.code)
            is IOException -> Network
            is RelayApiException.BadResponse -> Server("bad_response")
            is SecretStoreException -> Server("keychain")
            is MachineHub.AddException.NotSignedIn -> Server("signed_out")
            else -> Server("unknown")
        }
    }
}
