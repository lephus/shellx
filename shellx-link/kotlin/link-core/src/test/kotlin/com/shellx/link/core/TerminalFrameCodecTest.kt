package com.shellx.link.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlinx.serialization.json.Json
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

    @Test
    fun runsNeverPrintTheirText() {
        assertFalse("secret" in TerminalRun(text = "secret").toString())
        assertFalse("secret" in TerminalLine(0, listOf(TerminalRun(text = "secret"))).toString())
    }
}
