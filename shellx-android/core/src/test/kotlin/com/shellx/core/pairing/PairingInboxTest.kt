package com.shellx.core.pairing

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PairingInboxTest {
    private val link = "shellx-link://pair?v=1&m=m1&s=s1&k=k&c=c&n=Mac"

    @Test fun pairingLinkHeldUntilTaken() {
        val inbox = PairingInbox()
        assertFalse(inbox.hasLink.value)

        assertTrue(inbox.receive(link))

        assertTrue(inbox.hasLink.value)
        assertEquals(link, inbox.take())
        assertFalse(inbox.hasLink.value)
        assertNull(inbox.take(), "a link opens once")
    }

    /** A link opened while an answer or review sheet is up waits: the pairing sheet cannot show over that sheet, and
     *  closing it would lose an answer being typed. */
    @Test fun linkWaitsWhileASheetIsOpen() {
        val inbox = PairingInbox()
        val sheets = SheetPresence()
        sheets.opened()
        assertTrue(inbox.receive(link))

        assertNull(inbox.take(over = sheets))
        assertTrue(inbox.hasLink.value, "the link is kept")

        sheets.closed()
        assertEquals(link, inbox.take(over = sheets))
        assertFalse(inbox.hasLink.value)
        assertNull(inbox.take(over = sheets), "a link opens once")
    }

    @Test fun otherSchemesIgnored() {
        val inbox = PairingInbox()
        assertFalse(inbox.receive("https://shellx.pro/pair"))
        assertFalse(inbox.receive("shellx://pair"))
        assertFalse(inbox.hasLink.value)
    }

    @Test fun newerLinkReplacesOlder() {
        val inbox = PairingInbox()
        val newer = "shellx-link://pair?v=1&m=m2&s=s2&k=k&c=c&n=Mini"
        assertTrue(inbox.receive(link))
        assertTrue(inbox.receive(newer))
        assertEquals(newer, inbox.take())
    }

    /** The system opens the app for the scheme in any case, so the inbox takes any case; PairingModel lowercases the
     *  scheme before parsing (PairingModelTest checks the whole path). */
    @Test fun uppercaseSchemeAccepted() {
        val inbox = PairingInbox()
        assertTrue(inbox.receive("SHELLX-LINK://pair?v=1&m=m1&s=s1&k=k&c=c&n=Mac"))
        assertTrue(inbox.hasLink.value)
    }
}
