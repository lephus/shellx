package com.shellx.core.pairing

import java.util.Locale

/**
 * Sorts what the QR scanner reads. The camera reports a code in view many times a second and sees every QR code
 * around, so the scanner keeps running until a ShellX code shows up: other codes only raise a hint, and a code seen
 * again in a row is ignored. Mutable (Conventions): one owner, not thread-safe.
 */
class PairingScanFilter {
    sealed interface Verdict {
        /** A `shellx-link:` code (trimmed), for [PairingModel.begin] to check in full. Never prints the code. */
        data class Pairing(val text: String) : Verdict {
            override fun toString(): String = "Pairing(<redacted>)"
        }

        /** Some other QR code: say so, keep scanning. */
        data object NotShellX : Verdict

        /** The same code as the last one. */
        data object Ignored : Verdict
    }

    private var last: String? = null

    fun accept(payload: String): Verdict {
        val text = payload.trim()
        if (text == last) return Verdict.Ignored
        last = text
        return if (isPairingText(text)) Verdict.Pairing(text) else Verdict.NotShellX
    }

    companion object {
        /** True when [text] (blanks around it aside) starts with the `shellx-link:` scheme. */
        fun isPairingText(text: String): Boolean =
            text.trim().lowercase(Locale.ROOT).startsWith("${PairingInbox.SCHEME}:")
    }
}
