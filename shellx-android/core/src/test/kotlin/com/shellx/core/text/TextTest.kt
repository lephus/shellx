package com.shellx.core.text

import java.text.Normalizer
import kotlin.test.Test
import kotlin.test.assertEquals

class TextTest {
    private val family = "👨‍👩‍👧‍👦"

    @Test fun clustersAreWhatAPersonCounts() {
        assertEquals(listOf("a", "b"), "ab".graphemes())
        assertEquals(25, family.utf8Size); assertEquals(listOf(family), family.graphemes())
        assertEquals(listOf("🇻🇳", "🇺🇸"), "🇻🇳🇺🇸".graphemes())
        val decomposed = Normalizer.normalize("ệ", Normalizer.Form.NFD)
        assertEquals(1, decomposed.graphemeCount()); assertEquals(5, decomposed.utf8Size)
        assertEquals(listOf("👍🏽", "x"), "👍🏽x".graphemes()); assertEquals(listOf("\r\n", "a"), "\r\na".graphemes())
        assertEquals(1, "❤️".graphemeCount())
    }

    @Test fun cutsKeepWholeClusters() {
        assertEquals("a".repeat(1020), ("a".repeat(1020) + "🇻🇳").cutToUtf8(1024))
        assertEquals("ệ".nfc().repeat(341), "ệ".nfc().repeat(400).cutToUtf8(1024))
        assertEquals("ab", "abc".dropLastGrapheme()); assertEquals("", "".dropLastGrapheme())
        assertEquals("x", ("x" + family).dropLastGrapheme()); assertEquals(family.repeat(2), family.repeat(5).takeGraphemes(2))
    }

    @Test fun composedFormIsNfc() {
        assertEquals(Normalizer.normalize("Tiếng Việt", Normalizer.Form.NFC),
            Normalizer.normalize("Tiếng Việt", Normalizer.Form.NFD).nfc())
    }
}
