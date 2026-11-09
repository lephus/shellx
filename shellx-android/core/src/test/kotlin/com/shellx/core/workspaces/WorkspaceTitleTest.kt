package com.shellx.core.workspaces

import com.shellx.core.text.nfc
import com.shellx.core.text.utf8Size
import com.shellx.link.core.ShellXLink
import java.text.Normalizer
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/** A rename the Mac would refuse for its size (more than `ShellXLink.MAX_WORKSPACE_TITLE_BYTES` UTF-8 bytes) is
 *  answered `bad_request`, which the phone can only show as "try again later": what the phone sends must fit. */
class WorkspaceTitleTest {
    private fun bytes(text: String): List<Byte> = text.encodeToByteArray().toList()

    @Test fun aDecomposedVietnameseNameIsSentComposed() {
        // `==` on a String compares UTF-16 units, but compare the bytes that go on the wire, as the iPhone test does.
        val composed = "Tiếng Việt".nfc()
        val decomposed = Normalizer.normalize(composed, Normalizer.Form.NFD)
        assertNotEquals(bytes(composed), bytes(decomposed))

        assertEquals(bytes(composed), bytes(WorkspaceTitle.cleaned(" $decomposed ")))
    }

    @Test fun aLongDecomposedNameFitsOnceComposed() {
        // "ệ" is 5 bytes decomposed, 3 composed: 128 of them are 640 bytes, or 384.
        val composed = "ệ".repeat(WorkspaceTitle.MAX_CHARACTERS)
        val decomposed = Normalizer.normalize(composed, Normalizer.Form.NFD)
        assertTrue(decomposed.utf8Size > ShellXLink.MAX_WORKSPACE_TITLE_BYTES)

        val sent = WorkspaceTitle.cleaned(decomposed)

        assertEquals(bytes(composed), bytes(sent), "every character kept, composed")
        assertTrue(sent.utf8Size <= ShellXLink.MAX_WORKSPACE_TITLE_BYTES)
    }

    @Test fun anEmojiNameIsCutToTheByteLimitOnACharacterBoundary() {
        val family = "👨‍👩‍👧‍👦"
        assertEquals(25, family.utf8Size)
        val title = family.repeat(WorkspaceTitle.MAX_CHARACTERS)

        val sent = WorkspaceTitle.cleaned(title)

        assertTrue(sent.utf8Size <= ShellXLink.MAX_WORKSPACE_TITLE_BYTES)
        assertEquals(family.repeat(ShellXLink.MAX_WORKSPACE_TITLE_BYTES / 25), sent, "whole emoji only")
    }

    @Test fun theCharacterCapStillHoldsAndTheCutLeavesNoSpaceAtTheEnd() {
        assertEquals("a".repeat(128), WorkspaceTitle.cleaned("a".repeat(200)))
        val spaceAtTheCut = "x".repeat(127) + " " + "y".repeat(10)
        assertEquals("x".repeat(127), WorkspaceTitle.cleaned(spaceAtTheCut))
    }

    @Test fun aNameNeedsSomethingBesidesSpaces() {
        assertFalse(WorkspaceTitle.canSave(""))
        assertFalse(WorkspaceTitle.canSave("  \n\t "))
        assertTrue(WorkspaceTitle.canSave(" relay "))
        assertEquals("relay", WorkspaceTitle.cleaned("  relay \n"))
    }
}
