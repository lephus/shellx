package com.shellx.link.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.put

/** The vectors of PROTOCOL.md section 11 (`spec/vectors/terminal.json`); the port of 2A's `TerminalVectorTests`. */
class TerminalVectorTest {
    private val file = Vectors.terminal
    private fun JsonObject.ints(k: String) = getValue(k).jsonArray.map { it.jsonPrimitive.int }
    private fun JsonObject.int(k: String) = getValue(k).jsonPrimitive.int
    private fun JsonObject.str(k: String) = getValue(k).jsonPrimitive.content
    private fun JsonObject.bool(k: String) = getValue(k).jsonPrimitive.boolean

    /** The frame with a head `palette` of `"@palette"` replaced by the file's palette. */
    private fun withPalette(frame: JsonObject, palette: JsonElement): JsonObject {
        val head = frame["head"] as? JsonObject ?: return frame
        val marker = head["palette"] as? JsonPrimitive
        if (marker == null || !marker.isString || marker.content != "@palette") return frame
        return JsonObject(frame + ("head" to JsonObject(head + ("palette" to palette))))
    }

    private fun cursor(o: JsonObject) =
        TerminalCursor(o.int("x"), o.int("y"), TerminalCursorShape(o.str("shape")), o.bool("visible"), o.bool("blink"))

    /** 2A's `{x, y, kind}` cell entries; a glyph without `style` has the default style. */
    private fun expectedCell(o: JsonObject): TerminalCell = when (val kind = o.str("kind")) {
        "blank" -> TerminalCell.Blank
        "continuation" -> TerminalCell.Continuation
        "glyph" -> {
            val st = o["style"]?.jsonObject
            val style = if (st == null) {
                TerminalCellStyle.DEFAULT
            } else {
                TerminalCellStyle(
                    st["fg"]?.jsonPrimitive?.int, st["fg_rgb"]?.jsonPrimitive?.content, st["bg"]?.jsonPrimitive?.int,
                    st["bg_rgb"]?.jsonPrimitive?.content,
                    st["attrs"]?.jsonArray?.map { TerminalAttribute(it.jsonPrimitive.content) } ?: emptyList(),
                )
            }
            TerminalCell.Glyph(o.str("t"), o.int("w"), style)
        }
        else -> error("unknown cell kind $kind")
    }

    @Test
    fun limitsMatchTheVectors() {
        val l = file.getValue("limits").jsonObject
        assertEquals(listOf(ShellXLink.TERMINAL_COLUMNS.first, ShellXLink.TERMINAL_COLUMNS.last), l.ints("columns"))
        assertEquals(listOf(ShellXLink.TERMINAL_ROWS.first, ShellXLink.TERMINAL_ROWS.last), l.ints("rows"))
        assertEquals(ShellXLink.TERMINAL_MAX_GRID_SIZE, l.int("max_grid_size"))
        assertEquals(ShellXLink.TERMINAL_MAX_FRAME_PARTS, l.int("max_frame_parts"))
        assertEquals(ShellXLink.TERMINAL_MAX_CELL_TEXT_BYTES, l.int("max_cell_text_bytes"))
        assertEquals(ShellXLink.TERMINAL_SNAPSHOT_HISTORY_ROWS, l.int("snapshot_history_rows"))
        assertEquals(ShellXLink.TERMINAL_HISTORY_ROW_BUDGET, l.int("history_row_budget"))
        assertEquals(ShellXLink.TERMINAL_HISTORY_FILL_MAX_BYTES, l.int("history_fill_max_bytes"))
        assertEquals(ShellXLink.TERMINAL_MAX_DELTA_HISTORY_ROWS, l.int("max_delta_history_rows"))
        assertEquals(ShellXLink.TERMINAL_MAX_INPUT_UNITS, l.int("max_input_units"))
        assertEquals(ShellXLink.TERMINAL_MAX_TEXT_BYTES, l.int("max_text_bytes"))
        assertEquals(ShellXLink.TERMINAL_MAX_PASTE_BYTES, l.int("max_paste_bytes"))
        assertEquals(ShellXLink.TERMINAL_MAX_SCROLL_LINES, l.int("max_scroll_lines"))
        assertEquals(ShellXLink.TERMINAL_MAX_QUEUED_INPUTS, l.int("max_queued_inputs"))
    }

    @Test
    fun keyAndModifierNames() {
        val keys = file.getValue("keys").jsonArray.map { it.jsonPrimitive.content }
        assertEquals(40, keys.size)
        assertEquals(keys, TerminalKey.ALL_KNOWN.map { it.wire })
        for (k in keys) assertTrue(TerminalKey(k).isKnown, k)
        assertEquals(TerminalKey.PAGE_UP, TerminalKey("page_up"))
        assertEquals(TerminalKey.letter('c'), TerminalKey("c"))
        assertEquals('c', TerminalKey("c").letter)
        assertFalse(TerminalKey("C").isKnown)
        assertNull(TerminalKey("C").letter)
        assertFalse(TerminalKey("f13").isKnown)
        assertEquals(
            file.getValue("modifiers").jsonArray.map { it.jsonPrimitive.content },
            listOf(TerminalModifier.CTRL, TerminalModifier.ALT, TerminalModifier.SHIFT).map { it.wire },
        )
        assertNotEquals(TerminalModifier.CTRL, TerminalModifier("cmd"))
    }

    @Test
    fun inputChecks() {
        val checks = file.getValue("input_checks").jsonArray.map { it.jsonObject }
        assertEquals(28, checks.size)
        for (c in checks) {
            val name = c.getValue("name").jsonPrimitive.content
            val frame = buildJsonObject {
                put("v", 1)
                put("t", "terminal.view.input")
                put("terminal_id", "t-1")
                put("units", c.getValue("units"))
            }
            val message = LinkCodec.decode(Json.encodeToString(JsonObject.serializer(), frame).encodeToByteArray())
            val units = assertIs<LinkMessage.TerminalViewInput>(message, name).units
            val passed = try {
                TerminalInputCheck.check(units)
                true
            } catch (_: TerminalInputException) {
                false
            }
            assertEquals(c.getValue("ok").jsonPrimitive.boolean, passed, name)
        }
    }

    @Test
    fun inputErrorNeverQuotesTheText() {
        val e = assertFailsWith<TerminalInputException> { TerminalInputCheck.check(listOf(TerminalInputUnit.Text("hunter2\n"))) }
        assertFalse("hunter2" in e.reason)
        assertFalse("hunter2" in e.message.orEmpty())
    }

    @Test
    fun screens() {
        val palette = file.getValue("palette")
        val screens = file.getValue("screens").jsonArray.map { it.jsonObject }
        assertEquals(17, screens.size)
        for (s in screens) {
            val name = s.getValue("name").jsonPrimitive.content
            val assembler = TerminalFrameAssembler()
            val screen = TerminalScreen(s["max_history_rows"]?.jsonPrimitive?.int ?: TerminalScreen.DEFAULT_MAX_HISTORY_ROWS)
            var resyncs = 0
            for (f in s.getValue("frames").jsonArray) {
                val bytes = Json.encodeToString(JsonObject.serializer(), withPalette(f.jsonObject, palette)).encodeToByteArray()
                val message = assertIs<LinkMessage.TerminalViewFrame>(LinkCodec.decode(bytes), name)
                assertEquals("t-1", message.terminalId, name)
                val result = assembler.receive(message.frame)
                if (result.resync) resyncs++
                result.frame?.let(screen::apply)
            }
            val e = s.getValue("expect").jsonObject
            assertEquals(e.getValue("revision").jsonPrimitive.long, assembler.revision, name)
            assertEquals(e.getValue("resyncs").jsonPrimitive.int, resyncs, name)
            assertEquals(e.getValue("cols").jsonPrimitive.int, screen.cols, name)
            assertEquals(e.getValue("rows").jsonPrimitive.int, screen.rows, name)
            assertEquals(e.getValue("alt").jsonPrimitive.boolean, screen.alt, name)
            e["cursor"]?.let { assertEquals(cursor(it.jsonObject), screen.cursor, name) }
            assertEquals(e.getValue("screen").jsonArray.map { it.jsonPrimitive.content }, screen.screenText(), name)
            assertEquals(e.getValue("history").jsonArray.map { it.jsonPrimitive.content }, screen.historyText(), name)
            e["cells"]?.jsonArray?.forEach { c ->
                val o = c.jsonObject
                assertEquals(expectedCell(o), screen.cell(o.getValue("x").jsonPrimitive.int, o.getValue("y").jsonPrimitive.int), "$name $o")
            }
        }
    }

    @Test
    fun featureNames() {
        assertEquals("terminal_view", ShellXLink.TERMINAL_VIEW_FEATURE)
        assertEquals("terminal_create", ShellXLink.TERMINAL_CREATE_FEATURE)
    }
}
