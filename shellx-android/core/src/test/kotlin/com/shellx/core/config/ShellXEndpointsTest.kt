package com.shellx.core.config

import com.shellx.core.platform.CoreLog
import kotlin.test.Test
import kotlin.test.assertEquals

class ShellXEndpointsTest {
    @Test fun releaseIgnoresOverride() {
        for (value in listOf("https://staging.example.com", "http://127.0.0.1:8787", "http://localhost:8787")) {
            val endpoints = ShellXEndpoints.of(false, value)
            assertEquals(ShellXEndpoints.PRODUCTION, endpoints.apiBase, value)
        }
    }

    @Test fun debugUsesLoopbackOverride() {
        val endpoints = ShellXEndpoints.of(true, "http://127.0.0.1:8787")
        assertEquals("http://127.0.0.1:8787", endpoints.apiBase)
    }

    @Test fun debugAcceptsEveryLoopbackForm() {
        for (value in listOf("http://localhost:8787", "http://127.9.8.7:1", "http://[::1]:8787", "HTTP://LOCALHOST:8787")) {
            val endpoints = ShellXEndpoints.of(true, value)
            assertEquals(value, endpoints.apiBase, value)
        }
    }

    @Test fun debugAcceptsHTTPS() {
        val endpoints = ShellXEndpoints.of(true, "https://staging.example.com")
        assertEquals("https://staging.example.com", endpoints.apiBase)
    }

    @Test fun debugRejectsPlainHTTPRemote() {
        val lines = mutableListOf<String>(); CoreLog.sink = { lines += it }
        val endpoints = try { ShellXEndpoints.of(true, "http://192.168.1.5:8787") } finally { CoreLog.sink = {} }
        assertEquals(ShellXEndpoints.PRODUCTION, endpoints.apiBase)
        assertEquals(listOf("api_override_rejected"), lines)
    }

    @Test fun debugRejectsLookalikesAndJunk() {
        val rejected = listOf(
            "http://127.0.0.1.example.com", "http://localhost.example.com", "http://128.0.0.1",
            "http://127.0.0.256", "http://[::2]", "ftp://127.0.0.1", "https://", "not a url", "",
        )
        for (value in rejected) {
            val endpoints = ShellXEndpoints.of(true, value)
            assertEquals(ShellXEndpoints.PRODUCTION, endpoints.apiBase, value)
        }
    }

    @Test fun debugDefaultsToProduction() {
        val endpoints = ShellXEndpoints.of(true, null)
        assertEquals(ShellXEndpoints.PRODUCTION, endpoints.apiBase)
        assertEquals("https://relay.shellx.pro", ShellXEndpoints.PRODUCTION)
    }
}
