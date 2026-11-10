package com.shellx.app.ui.settings

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/** "Notifications arriving late?": each phone maker that holds FCM back gets its own steps (S3 §7.4c; ledger A-1). */
@RunWith(AndroidJUnit4::class)
class OemGuideTest {
    @Test
    fun makersFindTheirGuide() {
        assertEquals(
            listOf(
                OemGuide.XIAOMI, OemGuide.XIAOMI, OemGuide.XIAOMI, OemGuide.OPPO, OemGuide.OPPO, OemGuide.OPPO, OemGuide.VIVO,
                OemGuide.VIVO, OemGuide.SAMSUNG, OemGuide.OTHER, OemGuide.OTHER,
            ),
            listOf("Xiaomi", "Redmi", "POCO", "OPPO", "realme", "OnePlus", "vivo", "iQOO", "samsung", "Google", "").map(OemGuide::of),
        )
    }

    @Test
    fun everyGuideHasItsOwnWords() {
        assertEquals(5, OemGuide.entries.map { it.text }.toSet().size)
    }
}
