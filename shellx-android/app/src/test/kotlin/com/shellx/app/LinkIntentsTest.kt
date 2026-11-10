package com.shellx.app

import android.content.Intent
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

/** Which intents carry a pairing link into the app. */
@RunWith(AndroidJUnit4::class)
class LinkIntentsTest {
    @Test
    fun aShellXLinkIsTaken() {
        assertEquals(
            "shellx-link://pair?v=1&m=m1",
            LinkIntents.uri(Intent(Intent.ACTION_VIEW, Uri.parse("shellx-link://pair?v=1&m=m1"))),
        )
        assertEquals(
            "the scheme is compared ignoring case",
            "SHELLX-LINK://pair?v=1",
            LinkIntents.uri(Intent(Intent.ACTION_VIEW, Uri.parse("SHELLX-LINK://pair?v=1"))),
        )
        assertNull(LinkIntents.uri(Intent(Intent.ACTION_VIEW, Uri.parse("https://shellx.pro/pair?v=1"))))
        assertNull(LinkIntents.uri(Intent(Intent.ACTION_MAIN, Uri.parse("shellx-link://pair?v=1"))))
        assertNull(LinkIntents.uri(Intent(Intent.ACTION_MAIN)))
        assertNull(LinkIntents.uri(null))
    }
}
