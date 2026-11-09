package com.shellx.link.account

import com.shellx.link.core.RelayException
import java.net.URI
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class HttpSupportTest {
    @Test
    fun checkedUrlKeepsTheHostTheUriParsed() {
        assertEquals("http://127.0.0.1:9/v1/relay", URI("ws://127.0.0.1:9/v1/relay").toCheckedHttpUrl().toString())
        assertEquals("https://relay.example.test/v2/relay", URI("WSS://Relay.Example.Test/v2/relay").toCheckedHttpUrl().toString())
        assertEquals("::1", URI("http://[::1]:8080/").toCheckedHttpUrl().host)
        assertEquals("/api/", URI("https://api.example.test/api/#frag").toCheckedHttpUrl().encodedPath)
    }

    @Test
    fun checkedUrlRefusesWhatOkHttpWouldReadDifferently() {
        // OkHttp writes this host as "::1"; a host that does not compare equal as text is refused, not reinterpreted.
        for (bad in listOf("https://[0:0:0:0:0:0:0:1]/", "shellx-link://pair", "mailto:a@b.c", "https:///nohost")) {
            assertFailsWith<RelayException.ProtocolViolation>(bad) { URI(bad).toCheckedHttpUrl() }
        }
    }

    @Test
    fun safeSegmentsAreRelayIds() {
        for (good in listOf("p-1", "6f1c2b7e-0d4a-4c1e-9a53-3b8e5d2f7a10", "a_B", "a".repeat(64))) assertTrue(isSafeSegment(good), good)
        for (bad in listOf("", "a".repeat(65), "../x", "a/b", "a b", "a.b", "é", "%2e")) assertFalse(isSafeSegment(bad), bad)
    }
}
