package com.shellx.app.ui.agent

import android.content.Context
import android.content.res.Resources
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.ui.agent.AgentFixtures.NOW_MS
import com.shellx.app.ui.agent.AgentFixtures.ref
import com.shellx.app.ui.agent.AgentFixtures.session
import com.shellx.app.ui.theme.AgentStateStyle
import com.shellx.core.agent.AgentSendResult
import com.shellx.core.composer.ComposerDraft
import com.shellx.core.composer.OutgoingAttachment
import com.shellx.core.home.AgentStatusRow
import com.shellx.core.home.ComposerValidation
import com.shellx.core.pending.AgentLabel
import com.shellx.link.core.AgentState
import com.shellx.link.core.AttachmentKind
import com.shellx.link.core.ChatEntry
import com.shellx.link.core.ChatEntryKind
import com.shellx.link.core.ChatEntryKind.Companion.PROSE
import com.shellx.link.core.ChatEntryKind.Companion.STATUS
import com.shellx.link.core.ChatEntryKind.Companion.THOUGHT
import com.shellx.link.core.ChatEntryKind.Companion.TOOL_USE
import com.shellx.link.core.ChatEntryRole.Companion.AGENT
import com.shellx.link.core.ChatEntryRole.Companion.SYSTEM
import com.shellx.link.core.ChatEntryRole.Companion.USER
import com.shellx.link.core.ChatInterruptOutcome
import com.shellx.link.core.ChatSendOutcome
import java.util.Locale
import kotlin.time.Duration.Companion.seconds
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** The agent screen's words: the logic parts of `AgentRenderTests.swift`. */
@RunWith(AndroidJUnit4::class)
class AgentTextsTest {
    private val res: Resources get() = ApplicationProvider.getApplicationContext<Context>().resources

    private fun text(result: AgentSendResult): String? = AgentView.text(result, ref, "MacBook Pro", res)

    @Test
    fun everySendAndStopResultHasItsWords() {
        val results = listOf(
            AgentSendResult.Refused(ComposerValidation.TooLong(16_385)), AgentSendResult.Sent(ChatSendOutcome.SUBMITTED),
            AgentSendResult.Sent(ChatSendOutcome.BUSY), AgentSendResult.Sent(ChatSendOutcome.NOT_FOUND),
            AgentSendResult.Sent(ChatSendOutcome.FAILED), AgentSendResult.Offline, AgentSendResult.NoAnswer,
        )
        val texts = results.mapNotNull(::text)
        assertEquals(results.size, texts.size)
        assertEquals("each result reads differently", results.size, texts.toSet().size)
        assertEquals(res.getString(R.string.agent_busy), texts[2])
        assertEquals(res.getString(R.string.agent_gone), texts[3])
        assertTrue("offline names the Mac", texts[5].contains("MacBook Pro"))
        assertNull(text(AgentSendResult.Refused(ComposerValidation.Empty)))
        // The composer says these under its field; a send that surely did not arrive reads as a failure.
        assertNull(text(AgentSendResult.Refused(ComposerValidation.TooManyAttachments)))
        assertEquals(text(AgentSendResult.Sent(ChatSendOutcome.FAILED)), text(AgentSendResult.NotSent))
        assertEquals(text(AgentSendResult.Sent(ChatSendOutcome.FAILED)), text(AgentSendResult.Sent(ChatSendOutcome("x"))))
        // A Mac that no longer takes photos or files says so, apart from a send to try again.
        val unsupported = text(AgentSendResult.AttachmentsUnsupported)
        assertEquals(res.getString(R.string.home_note_attachments_unsupported, AgentLabel.of(ref.agent).text, ref.workspaceTitle), unsupported)
        assertNotEquals(text(AgentSendResult.NotSent), unsupported)

        val stops = listOf(
            StopButton.text(ChatInterruptOutcome.SENT, false, "MacBook Pro", res),
            StopButton.text(ChatInterruptOutcome.NOT_FOUND, false, "MacBook Pro", res),
            StopButton.text(ChatInterruptOutcome.FAILED, false, "MacBook Pro", res),
            StopButton.text(null, true, "MacBook Pro", res),
            StopButton.text(null, false, "MacBook Pro", res),
        )
        assertEquals(stops.size, stops.toSet().size)
        assertEquals(res.getString(R.string.agent_stop_sent), stops[0])
        assertTrue(stops[3].contains("MacBook Pro"))
        // No answer is final for a stop: not the pending cards' "not yet" line.
        assertEquals(res.getString(R.string.agent_stop_no_answer), stops[4])
        assertNotEquals(res.getString(R.string.pending_status_no_answer), stops[4])
    }

    @Test
    fun headerSaysTheState() {
        val working = AgentStatusRow.of(session, NOW_MS)
        assertEquals(
            res.getString(R.string.agent_state_running_for, AgentStateStyle.elapsedText(240.seconds, Locale.ENGLISH)),
            AgentHeader.status(working, gone = false, offline = false, res = res).text,
        )
        assertEquals(res.getString(R.string.agent_gone), AgentHeader.status(working, gone = true, offline = false, res = res).text)
        assertEquals(res.getString(R.string.agent_state_offline), AgentHeader.status(null, gone = false, offline = true, res = res).text)
        assertNull(AgentHeader.status(null, gone = false, offline = false, res = res).text)
        val ended = session.copy(session = session.session.copy(state = AgentState.ENDED))
        assertEquals(res.getString(R.string.agent_state_ended), AgentHeader.status(AgentStatusRow.of(ended, NOW_MS), false, false, res).text)
    }

    @Test
    fun theCutMarkerIsHeardOncePerEntry() {
        val marker = res.getString(R.string.agent_cut)
        assertTrue(marker.startsWith("…"))
        for ((role, kind) in listOf(USER to PROSE, AGENT to PROSE, SYSTEM to PROSE, AGENT to THOUGHT, AGENT to TOOL_USE, SYSTEM to STATUS, AGENT to ChatEntryKind("x"))) {
            val label = ChatEntryRow.accessibilityText(ChatEntry("e4", 1, 4, role, kind, "abc", truncated = true, toolName = "Bash", tsMs = 1), "Claude Code", res)
            assertEquals("$role $kind: $label", 1, label.split(marker).size - 1)
        }
        assertFalse(marker in ChatEntryRow.accessibilityText(ChatEntry("e5", 1, 5, AGENT, PROSE, "abc", tsMs = 1), "Claude Code", res))
    }

    @Test
    fun aSendKeepsOrClearsTheDraftAsTheResultSays() {
        val photo = OutgoingAttachment(kind = AttachmentKind.IMAGE, name = "photo-1.jpg", data = byteArrayOf(1))
        val empty = ComposerDraft()
        assertEquals("chạy test", AgentView.afterSend(empty, "chạy test", emptyList(), AgentSendResult.Offline).text) // keeps
        assertEquals("", AgentView.afterSend(empty, "chạy test", emptyList(), AgentSendResult.Sent(ChatSendOutcome.SUBMITTED)).text)
        assertEquals("gõ lại", AgentView.afterSend(empty.copy(text = "gõ lại"), "chạy test", emptyList(), AgentSendResult.Offline).text)
        val held = AgentView.beforeSend(empty.copy(attachments = listOf(photo)), listOf(photo))
        assertTrue(held.isSending)
        assertTrue(AgentView.afterSend(held, "", listOf(photo), AgentSendResult.Sent(ChatSendOutcome.SUBMITTED)).attachments.isEmpty())
        assertEquals(listOf(photo), AgentView.afterSend(held, "", listOf(photo), AgentSendResult.NotSent).attachments)
    }
}
