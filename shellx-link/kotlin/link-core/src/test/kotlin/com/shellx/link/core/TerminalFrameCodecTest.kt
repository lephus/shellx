package com.shellx.link.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonUnquotedLiteral
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject

/** The port of 2A's `TerminalFrameCodecTests`, then one Kotlin test. */
class TerminalFrameCodecTest {
    private val palette = TerminalPalette("#d0d0d0", "#101010", "#ff8800", (0 until 256).map { "#%02x%02x%02x".format(it, it, it) })
    private fun json(m: LinkMessage) = Json.parseToJsonElement(LinkCodec.encode(m).decodeToString()).jsonObject

    @Test
    fun paletteRoundTrips() {
        val head = TerminalFrameHead(TerminalFrameKind.SNAPSHOT, 80, 24, cursor = TerminalCursor(0, 0), palette = palette, history = 3)
        val m = LinkMessage.TerminalViewFrame("t-1", TerminalFramePart(revision = 1, head = head))
        assertEquals(m, LinkCodec.decode(LinkCodec.encode(m)))
    }

    @Test
    fun emptyFieldsAreOmitted() {
        val o = json(LinkMessage.TerminalViewFrame("t-1", TerminalFramePart(2, part = 1, parts = 2, lines = listOf(TerminalLine(0)))))
        assertEquals(setOf("v", "t", "terminal_id", "revision", "part", "parts", "lines"), o.keys)
        assertEquals(setOf("y"), o.getValue("lines").jsonArray[0].jsonObject.keys)
        val head = TerminalFrameHead(TerminalFrameKind.DELTA, 2, 1, cursor = TerminalCursor(0, 0))
        val h = json(LinkMessage.TerminalViewFrame("t-1", TerminalFramePart(1, head = head))).getValue("head").jsonObject
        assertEquals(setOf("kind", "cols", "rows", "alt", "cursor"), h.keys)
    }

    @Test
    fun encodingChecksTheSameRulesAsDecoding() {
        val bad = listOf(
            TerminalFramePart(0),
            TerminalFramePart(1, part = 1, parts = 1),
            TerminalFramePart(1, 1, 2, styles = listOf(TerminalStyle(1, fg = 256))),
            TerminalFramePart(1, 1, 2, styles = listOf(TerminalStyle(1, bgRgb = "336699"))),
            TerminalFramePart(1, 1, 2, lines = listOf(TerminalLine(0, listOf(TerminalRun(text = "x", width = 3))))),
            TerminalFramePart(1, 1, 2, lines = listOf(TerminalLine(0, listOf(TerminalRun(text = ""))))),
        )
        for (p in bad) {
            val e = assertFailsWith<LinkCodecException>(p.toString()) { LinkCodec.encode(LinkMessage.TerminalViewFrame("t-1", p)) }
            assertEquals(LinkCodecException.BadJson(null), e)
        }
    }

    /**
     * Review A, m7: Swift reads a frame's integers as a 64-bit Int, so a value of 2^32 decodes there. It decodes here
     * too and meets the same rules: a grid that wide is a gap, a line that far down is ignored, and a run that far
     * right is refused, as Swift's `isValid` refuses it. Past 64 bits both refuse the frame.
     */
    @Test
    fun integersBeyond32BitsAreReadAsSwiftReadsThem() {
        val big = "4294967296"
        val head = TerminalFrameHead(TerminalFrameKind.SNAPSHOT, 80, 24, cursor = TerminalCursor(0, 0), palette = palette)
        val snapshot = json(LinkMessage.TerminalViewFrame("t-1", TerminalFramePart(1, head = head)))
        fun JsonObject.with(key: String, value: JsonElement) = JsonObject(this + (key to value))
        fun JsonObject.headWith(key: String, value: String) = with("head", getValue("head").jsonObject.with(key, number(value)))
        fun decode(o: JsonObject) = LinkCodec.decode(Json.encodeToString(JsonObject.serializer(), o).encodeToByteArray())

        val wide = assertIs<LinkMessage.TerminalViewFrame>(decode(snapshot.headWith("cols", big))).frame
        assertTrue(TerminalFrameAssembler().receive(wide).resync)
        assertEquals(Int.MAX_VALUE, assertIs<LinkMessage.TerminalViewFrame>(decode(snapshot.headWith("history", big))).frame.head?.history)
        val farLine = snapshot.with("lines", Json.parseToJsonElement("""[{"y":$big,"runs":[{"t":"x"}]}]"""))
        val far = assertIs<LinkMessage.TerminalViewFrame>(decode(farLine)).frame
        val screen = TerminalScreen()
        TerminalFrameAssembler().receive(far).frame?.let(screen::apply)
        assertEquals(List(24) { "" }, screen.screenText())

        val farRun = snapshot.with("lines", Json.parseToJsonElement("""[{"y":0,"runs":[{"x":$big,"t":"x"}]}]"""))
        assertEquals(LinkCodecException.BadJson(null), assertFailsWith<LinkCodecException> { decode(farRun) })
        assertEquals(LinkCodecException.BadJson(null), assertFailsWith<LinkCodecException> { decode(snapshot.headWith("rows", "-$big")) })
        assertEquals(
            LinkCodecException.BadJson(null),
            assertFailsWith<LinkCodecException> { decode(snapshot.headWith("cols", "100000000000000000000")) },
        )
    }

    @OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
    private fun number(text: String): JsonPrimitive = JsonUnquotedLiteral(text)

    @Test
    fun runsNeverPrintTheirText() {
        assertFalse("secret" in TerminalRun(text = "secret").toString())
        assertFalse("secret" in TerminalLine(0, listOf(TerminalRun(text = "secret"))).toString())
    }
}
