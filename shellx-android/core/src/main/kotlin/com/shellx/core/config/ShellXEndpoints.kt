package com.shellx.core.config

import com.shellx.core.platform.CoreLog
import com.shellx.link.core.RelayTransportPolicy
import java.net.URI
import java.net.URISyntaxException

/** The ShellX servers the app talks to. */
data class ShellXEndpoints(val apiBase: String) {
    companion object {
        const val PRODUCTION = "https://relay.shellx.pro"

        /**
         * Release builds always use PRODUCTION. A debug build takes [override] (3D passes BuildConfig.SHELLX_API_BASE
         * from the Gradle property `shellxApiBase`) when it is an `https` URL, or an `http` URL to the loopback host
         * (`localhost`, `127.0.0.0/8`, `::1`), so a relay on the Mac is reachable through `adb reverse`. Any other value
         * is dropped with the log line `api_override_rejected`; an empty or absent one gives PRODUCTION silently.
         *
         * The loopback rule is 3B's `RelayTransportPolicy.isLoopback`, the rule `RelayApi` applies, so an override
         * accepted here never makes `RelayClientFactory.make` throw for its transport.
         */
        fun of(debugBuild: Boolean, override: String?): ShellXEndpoints {
            if (!debugBuild || override.isNullOrEmpty()) return ShellXEndpoints(PRODUCTION)
            if (!accepted(override)) {
                CoreLog.log("api_override_rejected")
                return ShellXEndpoints(PRODUCTION)
            }
            return ShellXEndpoints(override)
        }

        private fun accepted(raw: String): Boolean {
            val url = try {
                URI(raw)
            } catch (_: URISyntaxException) {
                return false
            }
            val host = url.host?.takeIf { it.isNotEmpty() } ?: return false
            return when (url.scheme?.lowercase()) {
                "https" -> true
                "http" -> RelayTransportPolicy.isLoopback(host)
                else -> false
            }
        }
    }
}
