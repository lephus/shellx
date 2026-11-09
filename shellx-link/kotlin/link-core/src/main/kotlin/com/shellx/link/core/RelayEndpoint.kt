package com.shellx.link.core

import java.net.URI
import java.security.SecureRandom

/**
 * The rule that keeps tickets and tokens off unencrypted links: only loopback hosts may use a plain-text scheme.
 * Shared by the relay sockets and the ShellX account API.
 */
object RelayTransportPolicy {
    /**
     * `localhost`, `127.0.0.0/8` and `::1`, in any case and with or without IPv6 brackets. Each IPv4 octet must be
     * canonical decimal (0–255, no sign and no leading zero): Android's resolver does not read `127.0.0.01` as an
     * address, so such a name would go to DNS.
     */
    fun isLoopback(host: String?): Boolean {
        var h = host?.lowercase() ?: return false
        if (h.length >= 2 && h.startsWith("[") && h.endsWith("]")) h = h.substring(1, h.length - 1)
        if (h == "localhost" || h == "::1") return true
        val octets = h.split('.')
        if (octets.size != 4 || octets.any { !CANONICAL_OCTET.matches(it) || it.toInt() > 255 }) return false
        return octets[0] == "127"
    }

    private val CANONICAL_OCTET = Regex("0|[1-9][0-9]{0,2}")

    /**
     * Accepts `https`, and `http` only to a loopback host. Plain `http` to any other host is
     * [RelayException.InsecureTransport]; a URL without a scheme or host, or another scheme, is
     * [RelayException.ProtocolViolation].
     */
    fun requireHttps(url: URI) {
        val scheme = url.scheme?.lowercase()
        if (scheme == null || url.host == null) throw RelayException.ProtocolViolation("URL is invalid")
        when (scheme) {
            "https" -> Unit
            "http" -> if (!isLoopback(url.host)) throw RelayException.InsecureTransport(scheme)
            else -> throw RelayException.ProtocolViolation("URL scheme $scheme is unsupported")
        }
    }
}

/** URL rules for the relay control socket and the circuit sockets. */
object RelayEndpoint {
    /**
     * The control WebSocket URL of a configured relay URL. `ws`, `relay+ws` and `http` become `ws` and are accepted
     * only for a loopback host ([RelayException.InsecureTransport] otherwise); `wss`, `relay+wss` and `https` become
     * `wss`. An empty or `/` path becomes `/v1/relay`; any other path is kept. The query and fragment are dropped.
     */
    fun control(url: URI): URI {
        val scheme = url.scheme?.lowercase()
        if (scheme == null || url.host == null) throw RelayException.ProtocolViolation("relay URL is invalid")
        val target = when (scheme) {
            "ws", "relay+ws", "http" -> {
                if (!RelayTransportPolicy.isLoopback(url.host)) throw RelayException.InsecureTransport(scheme)
                "ws"
            }
            "wss", "relay+wss", "https" -> "wss"
            else -> throw RelayException.ProtocolViolation("relay URL scheme $scheme is unsupported")
        }
        val path = url.rawPath.let { if (it.isNullOrEmpty() || it == "/") "/v1/relay" else it }
        return URI("$target://${url.rawAuthority}$path")
    }

    /**
     * The URL a circuit socket joins on. The native relay takes joins on the control URL; slot-routed relays
     * (`/v1/slots/…`) take them on `/v1/circuits/<percent-encoded circuit>`.
     */
    fun circuit(control: URI, circuit: String): URI {
        if (control.rawPath?.startsWith("/v1/slots/") != true) return control
        return URI("${control.scheme}://${control.rawAuthority}/v1/circuits/${encodeSegment(circuit)}")
    }

    /** Percent-encodes a path segment: Foundation's `urlPathAllowed` set without `/`, upper-case hex. */
    private fun encodeSegment(text: String): String {
        val out = StringBuilder()
        for (byte in text.encodeToByteArray()) {
            val b = byte.toInt() and 0xFF
            val c = b.toChar()
            if (b < 0x80 && (c.isLetterOrDigit() || c in PATH_ALLOWED)) {
                out.append(c)
            } else {
                out.append('%').append(HEX[b ushr 4]).append(HEX[b and 0x0F])
            }
        }
        return out.toString()
    }

    private const val PATH_ALLOWED = "!$&'()*+,-.:=@_~"
    private const val HEX = "0123456789ABCDEF"
}

/** Client-chosen lane tokens: 24 random bytes, base64url without padding (32 characters). */
internal object RelayLane {
    fun random(random: SecureRandom = SecureRandom()): String = ByteArray(24).also(random::nextBytes).toBase64Url()
}
