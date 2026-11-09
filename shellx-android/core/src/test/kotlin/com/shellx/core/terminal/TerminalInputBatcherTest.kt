package com.shellx.core.terminal

import com.shellx.core.text.graphemeCount
import com.shellx.core.text.utf8Size
import com.shellx.link.core.TerminalInputCheck
import com.shellx.link.core.TerminalInputUnit
import com.shellx.link.core.TerminalInputUnit.Key
import com.shellx.link.core.TerminalInputUnit.Paste
import com.shellx.link.core.TerminalInputUnit.Scroll
import com.shellx.link.core.TerminalInputUnit.Text
import com.shellx.link.core.TerminalKey
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TerminalInputBatcherTest {
    @Test fun smallInputIsOneMessage() {
        assertEquals(
            listOf(listOf(Text("ls"), Key(TerminalKey.ENTER))),
            TerminalInputBatcher.messages(listOf(Text("ls"), Key(TerminalKey.ENTER))),
        )
    }

    @Test fun everyMessagePassesTheProtocolCheck() {
        val units: List<TerminalInputUnit> = List(100) { Key(TerminalKey.TAB) } + Text("é".repeat(10_000)) +
            TerminalInputBatcher.pasteUnits("a".repeat(40_000))
        val messages = TerminalInputBatcher.messages(units)
        for (message in messages) TerminalInputCheck.check(message)
        val typed = messages.flatten().filterIsInstance<Text>().joinToString("") { it.text }
        assertEquals("é".repeat(10_000), typed)
    }

    @Test fun typedTextSplitsAt4096Utf8Bytes() {
        assertEquals(
            listOf(listOf(Text("é".repeat(2048))), listOf(Text("é".repeat(952)))),
            TerminalInputBatcher.messages(listOf(Text("é".repeat(3000)))),
        )
    }

    @Test fun noMessageHoldsMoreThan64Units() {
        assertEquals(listOf(64, 36), TerminalInputBatcher.messages(List(100) { Key(TerminalKey.TAB) }).map { it.size })
    }

    @Test fun aClusterIsNeverCut() {
        val family = "👨‍👩‍👧‍👦"   // 25 UTF-8 bytes, one grapheme
        val text = family.repeat(200)
        val pieces = TerminalInputBatcher.messages(listOf(Text(text))).flatten().filterIsInstance<Text>().map { it.text }
        assertEquals(text, pieces.joinToString(""))
        assertTrue(pieces.all { it.utf8Size == it.graphemeCount() * 25 }, "every piece is whole families")
    }

    @Test fun pasteLimitIs256KiB() {
        assertEquals(262_144, TerminalInputBatcher.MAX_PASTE_BYTES)
        assertTrue(TerminalInputBatcher.pasteFits("a".repeat(262_144)))
        assertFalse(TerminalInputBatcher.pasteFits("a".repeat(262_145)))
        // Dropped controls do not count.
        assertTrue(TerminalInputBatcher.pasteFits("a".repeat(262_144) + "\u001b"))
    }

    @Test fun pasteSplitsAt16384BytesAndDropsWhatTheProtocolRefuses() {
        assertEquals(listOf(Paste("a[201~b\r\n\tc")), TerminalInputBatcher.pasteUnits("a\u001b[201~b\r\n\tc\u007f"))
        assertEquals(emptyList(), TerminalInputBatcher.pasteUnits("")); assertEquals(emptyList(), TerminalInputBatcher.pasteUnits("\u001b"))
        assertEquals(
            listOf(listOf(Paste("a".repeat(16_384))), listOf(Paste("a".repeat(3_616)))),
            TerminalInputBatcher.messages(TerminalInputBatcher.pasteUnits("a".repeat(20_000))),
        )
    }

    @Test fun scrollUnitsHoldAtMost100Lines() {
        assertEquals(listOf(Scroll(100), Scroll(100), Scroll(50)), TerminalInputBatcher.scrollUnits(250))
        assertEquals(listOf(Scroll(-3)), TerminalInputBatcher.scrollUnits(-3))
        assertEquals(emptyList(), TerminalInputBatcher.scrollUnits(0))
    }
}
