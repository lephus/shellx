package com.shellx.core.link

/** Why a call to a Mac was not sent. The Mac's name never prints. */
sealed class LinkCallException(message: String) : Exception(message) {
    /** The Mac has no live, synced session right now. Nothing was sent. */
    data class Offline(val machineName: String) : LinkCallException("offline") {
        override fun toString(): String = "Offline(machineName=<redacted>)"
    }

    /** The Mac removed this phone, or its key changed: nothing was sent, and nothing can be until it is paired again. */
    data class NeedsPairing(val machineName: String) : LinkCallException("needs_pairing") {
        override fun toString(): String = "NeedsPairing(machineName=<redacted>)"
    }

    /** No paired Mac has that id. */
    class UnknownMachine : LinkCallException("unknown_machine")
}
