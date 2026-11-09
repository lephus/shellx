package com.shellx.core.link

/** Where the link to one Mac stands. */
sealed interface MachineLinkState {
    /** The first attempt (or the first after the app came back) is under way. */
    data object Connecting : MachineLinkState

    /** A live session, synced. */
    data object Online : MachineLinkState

    /** The live session ended; trying to get it back. Pending items stay, but cannot be acted on. */
    data object Reconnecting : MachineLinkState

    /** Could not reach the Mac since [sinceMs] (epoch ms); still retrying. */
    data class Offline(val sinceMs: Long) : MachineLinkState

    /** The Mac no longer lets this phone in. Stops the reconnect loop. */
    data object Revoked : MachineLinkState

    /** The Mac's key is not the one pinned at pairing. Stops the reconnect loop. */
    data object HostKeyChanged : MachineLinkState

    /** The Mac speaks another protocol version. Stops the reconnect loop. */
    data object NeedsUpdate : MachineLinkState

    /** False for a Mac that removed this phone or whose key changed: it cannot take messages until it is paired
     *  again, so it is not offered as the default Mac. */
    val canBeDefault: Boolean get() = !needsPairing

    /** True for a Mac that removed this phone or whose key changed: nothing reaches it until it is paired again, and
     *  it will not come back by itself, so the app never calls it offline. */
    val needsPairing: Boolean get() = this == Revoked || this == HostKeyChanged

    /** True for the three states that stop the reconnect loop for good. */
    val isTerminal: Boolean get() = this == Revoked || this == HostKeyChanged || this == NeedsUpdate
}
