package com.shellx.link.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs

class RelayControlTest {
    private fun samples() = javaClass.getResource("/relay-control-samples.jsonl")!!.readText().lines().filter { it.isNotEmpty() }

    @Test
    fun sampleLinesDecodeAndEncodeByteForByte() {
        val lines = samples()
        assertEquals(10, lines.size)
        for (line in lines) assertEquals(line, RelayControl.decode(line).encodeText(), line)
        assertEquals(RelayControl.Register(5, "slot-k1", "t-register"), RelayControl.decode(lines[0]))
        assertEquals(RelayControl.Registered(45), RelayControl.decode(lines[1]))
        assertEquals(RelayControl.Connect(5, "slot-k1", "t-connect", "lane-k1", 3u), RelayControl.decode(lines[2]))
        assertEquals(RelayControl.Allocated("circuit-k1", "lane-k1", 3u, "t-client-join"), RelayControl.decode(lines[3]))
        assertEquals(RelayControl.Incoming("circuit-k1", "lane-k1", 3u, "t-daemon-join"), RelayControl.decode(lines[4]))
        assertEquals(
            RelayControl.Join(5, "slot-k1", "circuit-k1", "lane-k1", 3u, "t-client-join", RelayRole.CLIENT),
            RelayControl.decode(lines[5]),
        )
        assertEquals(RelayControl.Ready("circuit-k1", "lane-k1", 3u), RelayControl.decode(lines[6]))
        assertEquals(RelayControl.Ping(7u), RelayControl.decode(lines[7]))
        assertEquals(RelayControl.Pong(7u), RelayControl.decode(lines[8]))
        assertEquals(RelayControl.Error("slot-offline", "the host is offline", true), RelayControl.decode(lines[9]))
    }

    @Test
    fun uint64FieldsKeepTheirFullRange() {
        assertEquals(RelayControl.Ping(ULong.MAX_VALUE), RelayControl.decode("""{"type":"ping","nonce":18446744073709551615}"""))
        assertEquals("""{"type":"pong","nonce":18446744073709551615}""", RelayControl.Pong(ULong.MAX_VALUE).encodeText())
        assertEquals(
            RelayControl.Ready("c", "l", ULong.MAX_VALUE),
            RelayControl.decode("""{"type":"ready","circuit":"c","lane":"l","generation":18446744073709551615}"""),
        )
    }

    @Test
    fun anythingElseIsAProtocolViolation() {
        val bad = listOf(
            """{"type":"teleport"}""",
            """{"type":"ping"}""",
            """{"type":"register","protocol":256,"slot":"s","ticket":"t"}""",
            """{"type":"ready","circuit":"c","lane":"l","generation":-1}""",
            """{"type":"error","code":"x","message":"m","retryable":"yes"}""",
            "nope",
            // Not in the plan's list: the other decode limits.
            """{"type":"registered","lease_seconds":4294967296}""",
            """{"type":"join","protocol":5,"slot":"s","circuit":"c","lane":"l","generation":0,"ticket":"t","role":"admin"}""",
            """{"type":"ping","nonce":1.0}""",
            """[{"type":"ping","nonce":1}]""",
        )
        for (text in bad) {
            val error = assertFailsWith<RelayException>(text) { RelayControl.decode(text) }
            assertEquals(RelayException.ProtocolViolation("invalid relay control message"), assertIs<RelayException.ProtocolViolation>(error, text))
        }
    }

    @Test
    fun ticketsNeverPrint() {
        val controls = listOf(
            RelayControl.Register(5, "s", "secret-ticket"),
            RelayControl.Connect(5, "s", "secret-ticket", "l", 0u),
            RelayControl.Join(5, "s", "c", "l", 0u, "secret-ticket", RelayRole.CLIENT),
            RelayControl.Allocated("c", "l", 0u, "secret-ticket"),
            RelayControl.Incoming("c", "l", 0u, "secret-ticket"),
        )
        for (c in controls) assertFalse("secret-ticket" in c.toString(), c::class.simpleName)
    }
}
