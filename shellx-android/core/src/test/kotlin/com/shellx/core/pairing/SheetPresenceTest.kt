package com.shellx.core.pairing

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** The sheets open over the signed-in screens, counted so a pairing link can wait for them. */
class SheetPresenceTest {
    @Test fun countsEachOpenSheet() {
        val sheets = SheetPresence()
        assertFalse(sheets.isAnyOpen.value)

        sheets.opened()
        assertTrue(sheets.isAnyOpen.value)
        // A sheet's content can appear again before the old one went (a new item replaces it).
        sheets.opened()
        sheets.closed()
        assertTrue(sheets.isAnyOpen.value, "one sheet is still up")
        sheets.closed()
        assertFalse(sheets.isAnyOpen.value)

        // An extra close (a disappear without an appear) never goes below none.
        sheets.closed()
        sheets.opened()
        assertTrue(sheets.isAnyOpen.value)
    }
}
