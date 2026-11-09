package com.shellx.link.core

import java.net.URI
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class RelayEndpointTest {
    @Test
    fun plainWebSocketRefusedForRemoteHost() {
        val remote = listOf(
            "ws://relay.example.com", "http://relay.example.com/v2/relay", "relay+ws://relay.example.com",
            "ws://10.0.0.5:8080", "ws://192.168.1.2", "ws://[2001:db8::1]/", "ws://localhost.example.com",
            "ws://127.0.0.1.example.com",
        )
        for (text in remote) {
            assertIs<RelayException.InsecureTransport>(assertFailsWith<RelayException>(text) { RelayEndpoint.control(URI(text)) }, text)
        }
        assertEquals(
            RelayException.InsecureTransport("ws"),
            assertFailsWith<RelayException> { RelayEndpoint.control(URI("ws://relay.example.com")) },
        )
    }

    @Test
    fun loopbackPlainAllowed() {
        for (text in listOf("ws://localhost:1/x", "ws://LOCALHOST", "http://127.0.0.1:9", "relay+ws://127.9.8.7", "ws://[::1]:8080/v1/relay")) {
            assertEquals("ws", RelayEndpoint.control(URI(text)).scheme, text)
        }
        assertEquals("/v1/relay", RelayEndpoint.control(URI("ws://127.0.0.1:9")).path)
        assertEquals(URI("ws://[::1]:8080/v1/relay"), RelayEndpoint.control(URI("ws://[::1]:8080/v1/relay")))
        assertEquals(URI("ws://localhost:1/x"), RelayEndpoint.control(URI("ws://localhost:1/x?q=1#f")))
    }

    @Test
    fun secureSchemesAllowed() {
        for (text in listOf("wss://relay.example.com", "https://relay.example.com", "relay+wss://relay.example.com")) {
            assertEquals("wss", RelayEndpoint.control(URI(text)).scheme, text)
        }
        assertEquals("/v2/relay", RelayEndpoint.control(URI("https://relay.example.com/v2/relay")).path)
        assertEquals(URI("wss://relay.example.com/v1/relay"), RelayEndpoint.control(URI("https://relay.example.com/")))
    }

    @Test
    fun unsupportedOrHostlessUrlsAreProtocolViolations() {
        for (text in listOf("ftp://relay.example.com", "wss:relay", "/v1/relay")) {
            assertIs<RelayException.ProtocolViolation>(assertFailsWith<RelayException>(text) { RelayEndpoint.control(URI(text)) }, text)
        }
    }

    @Test
    fun circuitSocketsOfSlotRoutedRelays() {
        assertEquals(
            URI("wss://r.example/v1/circuits/c%2F1%20x"),
            RelayEndpoint.circuit(URI("wss://r.example/v1/slots/abc"), "c/1 x"),
        )
        assertEquals(URI("wss://r.example/v2/relay"), RelayEndpoint.circuit(URI("wss://r.example/v2/relay"), "c1"))
    }

    @Test
    fun requireHttps() {
        assertEquals(
            RelayException.InsecureTransport("http"),
            assertFailsWith<RelayException> { RelayTransportPolicy.requireHttps(URI("http://api.example.test")) },
        )
        for (text in listOf("http://127.0.0.1:8080", "http://localhost:8080", "https://api.example.test")) {
            RelayTransportPolicy.requireHttps(URI(text))
        }
        assertIs<RelayException.ProtocolViolation>(
            assertFailsWith<RelayException> { RelayTransportPolicy.requireHttps(URI("ftp://x.test")) },
        )
        assertIs<RelayException.ProtocolViolation>(
            assertFailsWith<RelayException> { RelayTransportPolicy.requireHttps(URI("/v1/auth")) },
        )
    }

    @Test
    fun isLoopback() {
        for (host in listOf("127.9.8.7", "LOCALHOST", "[::1]", "::1", "localhost")) assertTrue(RelayTransportPolicy.isLoopback(host), host)
        for (host in listOf("127.0.0.1.example.com", "127.0.0.256", "10.0.0.5", null, "", "127.0.0", "[2001:db8::1]")) {
            assertFalse(RelayTransportPolicy.isLoopback(host), host.toString())
        }
    }

    @Test
    fun lanesAre32Base64UrlCharacters() {
        val lane = RelayLane.random()
        assertTrue(Regex("[A-Za-z0-9_-]{32}").matches(lane), lane)
        assertNotEquals(lane, RelayLane.random())
    }
}
