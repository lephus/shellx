package com.shellx.app.ui.pending

import android.content.Context
import android.content.res.Resources
import androidx.compose.ui.graphics.Color
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.ui.home.NeedsYouBar
import com.shellx.app.ui.pending.PendingFixtures.edit
import com.shellx.app.ui.pending.PendingFixtures.mac
import com.shellx.app.ui.pending.PendingFixtures.permission
import com.shellx.app.ui.pending.PendingFixtures.plan
import com.shellx.app.ui.pending.PendingFixtures.question
import com.shellx.app.ui.pending.PendingFixtures.unknown
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.pending.DecisionFailure
import com.shellx.core.pending.DecisionStatus
import com.shellx.core.pending.PendingSheetModel
import com.shellx.core.text.cutToUtf8
import com.shellx.core.text.graphemeCount
import com.shellx.core.text.utf8Size
import com.shellx.link.core.PendingItem
import com.shellx.link.core.PendingKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** The words of the Needs-you cards: the logic parts of `PendingCardRenderTests.swift`. */
@RunWith(AndroidJUnit4::class)
class PendingTextsTest {
    private val res: Resources get() = ApplicationProvider.getApplicationContext<Context>().resources

    private fun line(status: DecisionStatus?, actionable: Boolean, linkNote: PendingSheetModel.LinkNote? = null) =
        PendingCardStatusLine.line(status, actionable, "Studio", linkNote, res = res)

    @Test
    fun statusLinesSayDifferentThings() {
        val statuses = listOf(
            DecisionStatus.Sending, DecisionStatus.HandledElsewhere, DecisionStatus.Failed(DecisionFailure.OFFLINE),
            DecisionStatus.Failed(DecisionFailure.NO_ANSWER), DecisionStatus.Failed(DecisionFailure.REJECTED),
        )
        val lines = statuses.mapNotNull { line(it, actionable = true) }
        assertEquals(statuses.size, lines.size)
        val reconnecting = line(null, actionable = false)
        assertEquals(6, (lines + listOfNotNull(reconnecting)).map { it.text }.toSet().size)
        assertTrue("offline names the Mac", lines[2].text.contains("Studio"))
        assertNull(line(null, actionable = true))
        assertNull(line(DecisionStatus.Done, actionable = true))
        assertTrue(lines[3].offersRetry)
        assertEquals("no retry while reconnecting", false, line(DecisionStatus.Failed(DecisionFailure.NO_ANSWER), actionable = false)?.offersRetry)
    }

    /** An open sheet whose item went because the Mac went offline or removed this phone says so, not "handled
     *  elsewhere" or a spinner that never ends. */
    @Test
    fun sheetLinkNotesSayWhyNothingIsSent() {
        val notes = listOf(
            PendingSheetModel.LinkNote.RECONNECTING, PendingSheetModel.LinkNote.OFFLINE, PendingSheetModel.LinkNote.NEEDS_PAIRING,
            PendingSheetModel.LinkNote.NEEDS_UPDATE,
        )
        val lines = notes.map { assertNotNull("$it has a line", line(null, actionable = false, linkNote = it)); line(null, false, it)!! }
        assertEquals(4, lines.map { it.text }.toSet().size)
        assertEquals(line(null, actionable = false), lines[0])
        assertEquals(line(DecisionStatus.Failed(DecisionFailure.OFFLINE), actionable = true), lines[1])
        assertTrue("names the Mac to pair again", lines[2].text.contains("Studio"))
        val handled = line(DecisionStatus.HandledElsewhere, actionable = false)
        assertFalse("never says handled elsewhere", lines.any { it == handled })
        assertNull(line(null, actionable = true, linkNote = PendingSheetModel.LinkNote.OFFLINE))
    }

    @Test
    fun headlineNamesWorkspaceAgentMacAndKind() {
        val item = mac(permission())
        assertEquals(
            "shellx, Claude Code, " + res.getString(R.string.pending_kind_permission, "Bash"),
            PendingCardView.spokenHeadline(item, false, res),
        )
        assertTrue(PendingCardView.spokenHeadline(item, true, res).contains("MacBook Pro"))
        assertTrue(PendingCardView.spokenHeadline(mac(edit), false, res).contains("Codex"))
    }

    @Test
    fun sheetKindFollowsTheItem() {
        assertEquals(PendingRoute.Kind.QUESTION, PendingRoute.kind(question()))
        assertEquals(PendingRoute.Kind.PLAN, PendingRoute.kind(plan()))
        assertEquals(PendingRoute.Kind.FULL_TEXT, PendingRoute.kind(permission()))
        assertEquals("no plan button: show the text", PendingRoute.Kind.FULL_TEXT, PendingRoute.kind(plan(modes = emptyList())))
        assertEquals(PendingRoute.Kind.FULL_TEXT, PendingRoute.kind(unknown))
    }

    /** The `CommandPreview.collapsed` part of `testLongPreviewRendersCollapsed` (the heights are the render's). */
    @Test
    fun longPreviewRendersCollapsed() {
        // 8192 bytes of short lines mixing a command, Arabic (right to left) and emoji.
        val text = StringBuilder()
        var line = 0
        while (text.toString().utf8Size < 9000) {
            line += 1
            text.append("echo 'مرحبا' 🚀👩‍💻 ẩn $line\n")
        }
        val preview = text.toString().cutToUtf8(PendingItem.MAX_PREVIEW_BYTES)
        assertTrue(preview.utf8Size > 8180)
        assertTrue(preview.split("\n").filter { it.isNotEmpty() }.size > 150)
        val (shown, cut) = CommandPreview.collapsed(preview)
        assertTrue(shown.graphemeCount() <= CommandPreview.COLLAPSED_CHARACTERS)
        assertTrue(cut)
        assertEquals("a short text is not cut", "echo" to false, CommandPreview.collapsed("echo"))
    }

    @Test
    fun theNeedsYouBarLeavesOutTheAgent() {
        val item = MachinePendingItem(
            "m1", "MacBook Pro",
            PendingItem(
                requestId = "p1", kind = PendingKind.PERMISSION, agent = "claude", workspaceId = "ws", workspaceTitle = "shellx",
                toolName = "Bash", createdAtMs = 1, modes = listOf("once"),
            ),
            true,
        )
        assertEquals("shellx · " + res.getString(R.string.pending_kind_permission, "Bash"), NeedsYouBar.headline(item, false, res, Color.Gray).text)
        assertEquals(
            "shellx · MacBook Pro · " + res.getString(R.string.pending_kind_permission, "Bash"),
            NeedsYouBar.headline(item, true, res, Color.Gray).text,
        )
    }
}
