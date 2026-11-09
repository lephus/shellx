package com.shellx.link.core

import com.shellx.link.core.TerminalInputUnit.Key
import com.shellx.link.core.TerminalInputUnit.Other
import com.shellx.link.core.TerminalInputUnit.Paste
import com.shellx.link.core.TerminalInputUnit.Scroll
import com.shellx.link.core.TerminalInputUnit.Text
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject

class TerminalInputTest {
    private fun units(m: LinkMessage) = Json.parseToJsonElement(LinkCodec.encode(m).decodeToString()).jsonObject.getValue("units")

    @Test
    fun unitsEncodeTheirWireFormAndEmptyModsAreOmitted() {
        val m = LinkMessage.TerminalViewInput(
            "t-1",
            listOf(
                Text("ls"), Key(TerminalKey.ENTER), Key(TerminalKey.letter('c'), listOf(TerminalModifier.CTRL)),
                Paste("a\nb"), Scroll(-3),
            ),
        )
        assertEquals(
            Json.parseToJsonElement(
                """[{"k":"text","text":"ls"},{"k":"key","key":"enter"},
                {"k":"key","key":"c","mods":["ctrl"]},{"k":"paste","text":"a\nb"},{"k":"scroll","lines":-3}]""",
            ),
            units(m),
        )
    }

    @Test
    fun anUnknownUnitKindKeepsOnlyItsKind() {
        val m = LinkCodec.decode(
            """{"v":1,"t":"terminal.view.input","terminal_id":"t-1","units":[{"k":"gesture","dx":1}]}""".encodeToByteArray(),
        )
        assertEquals(LinkMessage.TerminalViewInput("t-1", listOf(Other("gesture"))), m)
        assertEquals(Json.parseToJsonElement("""[{"k":"gesture"}]"""), units(m))
    }

    @Test
    fun typedAndPastedTextIsNeverPrinted() {
        assertFalse("hunter2" in Text("hunter2").toString())
        assertFalse("hunter2" in Paste("hunter2").toString())
        assertFalse("hunter2" in LinkMessage.TerminalViewInput("t-1", listOf(Text("hunter2"))).toString())
        assertTrue("7 bytes" in Text("hunter2").toString())
    }

    @Test
    fun letterKeysAreLowercaseAsciiOnly() {
        assertEquals("a", TerminalKey.letter('a').wire)
        assertFailsWith<IllegalArgumentException> { TerminalKey.letter('A') }
        assertFailsWith<IllegalArgumentException> { TerminalKey.letter('đ') }
    }
}
