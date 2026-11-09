package com.shellx.core.pairing

import java.util.Locale
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Holds a `shellx-link://` link the system opened the app with (Android: the shellx-link intent filter, 3D) until a
 * signed-in screen takes it, so a link opened before sign-in still reaches the pairing sheet afterwards. Only the
 * newest link is kept, in memory only: it carries a one-time code.
 *
 * Main-confined.
 */
class PairingInbox {
    private var held: String? = null
    private val _hasLink = MutableStateFlow(false)

    /** True while a link waits to be taken. */
    val hasLink: StateFlow<Boolean> = _hasLink.asStateFlow()

    /** Keeps [url] when its scheme is `shellx-link` in any case. Returns false (and keeps nothing) otherwise. */
    fun receive(url: String): Boolean {
        val scheme = url.substringBefore(':', missingDelimiterValue = "")
        if (!SCHEME_SYNTAX.matches(scheme) || scheme.lowercase(Locale.ROOT) != SCHEME) return false
        held = url
        _hasLink.value = true
        return true
    }

    /** The waiting link, once. */
    fun take(): String? {
        val link = held
        held = null
        _hasLink.value = false
        return link
    }

    /**
     * The waiting link, once, when the pairing sheet can show: while another sheet is up (an answer being typed, a plan
     * being read) it stays here and null is returned. The caller asks again when that sheet closes.
     */
    fun take(over: SheetPresence): String? = if (over.isAnyOpen.value) null else take()

    companion object {
        const val SCHEME = "shellx-link"

        /** RFC 3986: a letter, then letters, digits, "+", "-" or ".". */
        private val SCHEME_SYNTAX = Regex("[A-Za-z][A-Za-z0-9+.-]*")
    }

    override fun toString(): String = "PairingInbox(hasLink=${held != null})"
}
