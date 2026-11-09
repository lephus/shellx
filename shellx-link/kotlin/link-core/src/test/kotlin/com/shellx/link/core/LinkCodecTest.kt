package com.shellx.link.core

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

class LinkCodecTest {
    private fun d(text: String): LinkMessage = LinkCodec.decode(text.encodeToByteArray())
    private fun d(o: JsonObject): LinkMessage = d(Json.encodeToString(JsonObject.serializer(), o))
    private fun badJson(callId: String?, block: () -> Unit) =
        assertEquals(LinkCodecException.BadJson(callId), assertFailsWith<LinkCodecException> { block() })

    @Test
    fun unknownTypeKeepsOnlyAValidCallId() {
        assertEquals(LinkMessage.Unknown("future.call", "c1"), d("""{"v":1,"t":"future.call","call_id":"c1","x":{}}"""))
        val invalid: List<JsonElement> = listOf(
            JsonPrimitive(""), JsonPrimitive("c".repeat(65)), JsonPrimitive(7), JsonNull, buildJsonArray { add(JsonPrimitive("c1")) },
        )
        for (callId in invalid) {
            val frame = buildJsonObject { put("v", 1); put("t", "future.call"); put("call_id", callId) }
            assertEquals(LinkMessage.Unknown("future.call", null), d(frame), callId.toString())
        }
    }

    @Test
    fun badJsonCarriesTheFramesValidCallId() {
        val decision = """"decision":{"kind":"permission","mode":"once"}"""
        badJson("c1") { d("""{"v":1,"t":"agent.reply","call_id":"c1",$decision}""") }
        badJson(null) { d("""{"v":1,"t":"agent.reply",$decision}""") }
        badJson(null) { d("""{"v":1,"t":"agent.reply","request_id":"r",$decision}""") }
        badJson(null) { d("""{"v":1,"t":"agent.snapshot.get","call_id":""}""") }
        badJson(null) { d("""{"v":1,"t":"agent.snapshot.get","call_id":"${"c".repeat(65)}"}""") }
        assertEquals(LinkMessage.SnapshotGet("c".repeat(64)), d("""{"v":1,"t":"agent.snapshot.get","call_id":"${"c".repeat(64)}"}"""))
    }

    @Test
    fun garbageIsBadJsonWithoutCallId() {
        for (text in listOf("", "nope", "[1]", """{"v":"1","t":"ping"}""")) badJson(null) { d(text) }
        badJson(null) { LinkCodec.decode(byteArrayOf(0x7b, 0xff.toByte(), 0x7d)) }
    }

    @Test
    fun invalidJsonInAnIgnoredFieldIsBadJson() {
        // kotlinx's tree parser keeps any bare token as a literal; a frame is strict JSON (PROTOCOL.md section 3).
        for (token in listOf("nope", "01", "1.", "-", "+1", "1e", "tru", "NaN", "0x10")) {
            badJson(null) { d("""{"v":1,"t":"ping","nonce":5,"extra":$token}""") }
            badJson(null) { d("""{"v":1,"t":"ping","nonce":5,"extra":[{"x":$token}]}""") }
        }
        for (token in listOf("0", "-0", "1.5", "-2.5e-3", "1E+9", "true", "false", "null")) {
            assertEquals(LinkMessage.Ping(5u), d("""{"v":1,"t":"ping","nonce":5,"extra":$token}"""), token)
        }
    }

    @Test
    fun integersAreStrictTokens() {
        for (revision in listOf("1.0", "1e3")) {
            badJson(null) { d("""{"v":1,"t":"agent.changed","revision":$revision,"added":[],"resolved":[]}""") }
        }
        for (nonce in listOf("-1", "18446744073709551616", "\"5\"")) {
            badJson(null) { d("""{"v":1,"t":"ping","nonce":$nonce}""") }
        }
        assertEquals(LinkMessage.Ping(ULong.MAX_VALUE), d("""{"v":1,"t":"ping","nonce":18446744073709551615}"""))
    }

    @Test
    fun stringsAndBoolsAreTyped() {
        badJson(null) { d("""{"v":1,"t":"chat.reset","session_id":7}""") }
        badJson("c1") { d("""{"v":1,"t":"chat.interrupt","call_id":"c1","session_id":"s","hard":"true"}""") }
    }

    @Test
    fun nullOptionalIsAbsentNullRequiredIsBadJson() {
        assertEquals(LinkMessage.Error("x", "m", null), d("""{"v":1,"t":"error","code":"x","message":"m","call_id":null}"""))
        badJson(null) { d("""{"v":1,"t":"chat.reset","session_id":null}""") }
    }

    private fun chunk(data: JsonElement) = buildJsonObject {
        put("v", 1); put("t", "attach.chunk"); put("call_id", "c1"); put("attachment_id", "a1"); put("offset", 0); put("data", data)
    }

    @Test
    fun chunkDataMustBeCanonicalBase64() {
        val bad: List<JsonElement> = listOf("%%%", "QQ", "QQ=", "Q Q==", "QQ==\n", "-_8=", "QR==").map { JsonPrimitive(it) } + JsonPrimitive(7)
        for (data in bad) badJson("c1") { d(chunk(data)) }
        assertEquals(LinkMessage.AttachChunk("c1", "a1", 0, byteArrayOf(0x41)), d(chunk(JsonPrimitive("QQ=="))))
        // The empty chunk is a host rule, not a codec rule.
        assertEquals(LinkMessage.AttachChunk("c1", "a1", 0, ByteArray(0)), d(chunk(JsonPrimitive(""))))
    }

    private fun end(sha256: String) = buildJsonObject {
        put("v", 1); put("t", "attach.end"); put("call_id", "c1"); put("attachment_id", "a1"); put("sha256", sha256)
    }

    @Test
    fun endDigestMustBe64LowercaseHex() {
        for (sha in listOf("a".repeat(63), "a".repeat(65), "AB".repeat(32), "zz".repeat(32), "")) badJson("c1") { d(end(sha)) }
        val decoded = d(end("ab".repeat(32)))
        assertIs<LinkMessage.AttachEnd>(decoded)
        assertContentEquals(ByteArray(32) { 0xab.toByte() }, decoded.sha256)
    }

    @Test
    fun encodingValidatesCallIdsAndDigest() {
        badJson(null) { LinkCodec.encode(LinkMessage.SnapshotGet("")) }
        badJson(null) { LinkCodec.encode(LinkMessage.SnapshotGet("c".repeat(65))) }
        badJson(null) { LinkCodec.encode(LinkMessage.Error("x", "m", "")) }
        badJson(null) { LinkCodec.encode(LinkMessage.AttachEnd("c1", "a1", ByteArray(31))) }
        assertFailsWith<LinkCodecException.CannotEncodeUnknown> { LinkCodec.encode(LinkMessage.Unknown("x")) }
    }

    @Test
    fun encodingOmitsEmptyAndAbsentOptionals() {
        val welcome = LinkCodec.encode(LinkMessage.Welcome(1, "h", "m")).decodeToString()
        assertFalse("\"features\"" in welcome, welcome)
        val send = LinkCodec.encode(LinkMessage.ChatSend("c1", "s", "hi")).decodeToString()
        assertFalse("\"attachments\"" in send, send)
        val created = LinkCodec.encode(LinkMessage.WorkspaceCreateResult("c1", WorkspaceControlOutcome.REFUSED)).decodeToString()
        assertFalse("\"workspace_id\"" in created, created)
        val sparse = listOf(
            LinkMessage.Error("x", "m"),
            LinkMessage.ChatHistoryGet("c1", "s", limit = 5),
            LinkMessage.Snapshot("c1", 1, listOf(PendingItem("r", PendingKind.QUESTION, "claude", "w", "t", createdAtMs = 1,
                questions = listOf(PendingQuestion("q", prompt = "p", multiSelect = false, options = listOf(PendingQuestionOption("o", "l"))))))),
            LinkMessage.Sessions("c1", 1, listOf(AgentSession("s", "claude", "w", "t", state = AgentState.IDLE))),
            LinkMessage.ChatEntries("s", listOf(ChatEntry("e", 1, 1, ChatEntryRole.USER, ChatEntryKind.PROSE, "hi", tsMs = 1))),
            LinkMessage.Workspaces("c1", 1, listOf(LinkWorkspace("w", "t", 0, terminals = listOf(LinkTerminal("x", "", 0, true))))),
            LinkMessage.Reply("c1", "r", LinkDecision.ExitPlan(ExitPlanMode.MANUAL)),
        )
        for (m in listOf(welcome, send, created) + sparse.map { LinkCodec.encode(it).decodeToString() }) {
            assertFalse("null" in m, m)
        }
    }

    private fun item(preview: String) = PendingItem(
        "r", PendingKind.PERMISSION, "claude", "w", "t", toolName = "Bash", toolInputPreview = preview, createdAtMs = 1,
    )

    private fun snapshotFits(n: Int): Boolean = try {
        LinkCodec.encode(LinkMessage.Snapshot("c1", 1, listOf(item("a".repeat(n)))))
        true
    } catch (_: LinkCodecException.FrameTooLarge) {
        false
    }

    @Test
    fun frameAtTheLimitIsAccepted() {
        var low = 0
        var high = 70_000
        assertTrue(snapshotFits(low))
        assertFalse(snapshotFits(high))
        while (high - low > 1) {
            val mid = (low + high) / 2
            if (snapshotFits(mid)) low = mid else high = mid
        }
        val message = LinkMessage.Snapshot("c1", 1, listOf(item("a".repeat(low))))
        val frame = LinkCodec.encode(message)
        assertEquals(LinkCodec.MAX_FRAME_BYTES, frame.size)
        assertEquals(message, LinkCodec.decode(frame))
        assertFailsWith<LinkCodecException.FrameTooLarge> {
            LinkCodec.encode(LinkMessage.Snapshot("c1", 1, listOf(item("a".repeat(70_000)))))
        }
        assertFailsWith<LinkCodecException.FrameTooLarge> { LinkCodec.decode(ByteArray(70_000) { 0x20 }) }
    }

    @Test
    fun fullChunkFitsAFrame() {
        val message = LinkMessage.AttachChunk("i".repeat(64), "i".repeat(64), 10_485_760, ByteArray(45_000) { it.toByte() })
        val frame = LinkCodec.encode(message)
        assertTrue(frame.size <= LinkCodec.MAX_FRAME_BYTES, "${frame.size}")
        assertEquals(message, LinkCodec.decode(frame))
    }

    @Test
    fun vietnameseTextCountsBytes() {
        val message = LinkMessage.Error("x", "ệ".repeat(30_000))
        assertEquals(90_000, message.message.utf8Size)
        assertFailsWith<LinkCodecException.FrameTooLarge> { LinkCodec.encode(message) }
    }

    @Test
    fun byteArrayMessagesCompareByContentAndPrintSizes() {
        val a = LinkMessage.AttachChunk("c1", "a1", 0, byteArrayOf(1, 2, 3))
        assertEquals(a, a.copy(data = byteArrayOf(1, 2, 3)))
        assertEquals(a.hashCode(), a.copy(data = byteArrayOf(1, 2, 3)).hashCode())
        assertTrue("<3 bytes>" in a.toString(), a.toString())
        val e = LinkMessage.AttachEnd("c1", "a1", ByteArray(32) { 7 })
        assertEquals(e, e.copy(sha256 = ByteArray(32) { 7 }))
        assertTrue("<32 bytes>" in e.toString(), e.toString())
    }
}
