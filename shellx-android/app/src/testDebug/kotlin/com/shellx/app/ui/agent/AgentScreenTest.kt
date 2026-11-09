package com.shellx.app.ui.agent

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.ui.agent.AgentFixtures.entry
import com.shellx.app.ui.agent.AgentFixtures.everyKind
import com.shellx.app.ui.agent.AgentFixtures.ref
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.agent.AgentThreadModel
import com.shellx.core.composer.ComposerDraft
import com.shellx.core.home.AgentStatusRow
import com.shellx.link.core.ChatEntry
import com.shellx.link.core.ChatEntryKind
import com.shellx.link.core.ChatEntryRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** The agent screen from plain values (`AgentRenderTests.swift`' fixtures): the entries, following the newest, older
 *  entries, Stop and Force Stop, Close Agent and Remove from This Phone. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w393dp-h2400dp")
class AgentScreenTest {
    @get:Rule val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private var entries by mutableStateOf(everyKind)
    private var stops = 0
    private var forceStops = 0
    private var olderAsks = 0
    private var closes = 0
    private var removes = 0

    private fun show(
        older: AgentThreadModel.Older = AgentThreadModel.Older.NONE,
        canStop: Boolean = false,
        closeAgentName: String? = null,
        canRemoveFromPhone: Boolean = false,
        embedded: Boolean = false,
        gone: Boolean = false,
    ) = compose.setContent {
        ShellXTheme {
            val row = AgentStatusRow.of(AgentFixtures.session, AgentFixtures.NOW_MS)
            AgentScreen(
                ref = ref, place = "Claude Code · MacBook Pro", row = { row }, gone = gone, offline = false, pending = emptyList(),
                showsMachineName = false, entries = entries, emptyState = null, machineName = "MacBook Pro", older = older,
                loadingOlder = false, canStop = canStop, notice = null, draft = ComposerDraft(), onDraftChange = {},
                embedded = embedded, closeAgentName = closeAgentName, canRemoveFromPhone = canRemoveFromPhone,
                actions = AgentScreenActions(
                    stop = { stops++ }, forceStop = { forceStops++ }, loadOlder = { olderAsks++ }, closeAgent = { closes++ },
                    removeFromPhone = { removes++ },
                ),
            )
        }
    }

    private fun until(condition: () -> Boolean) = compose.waitUntil(10_000) {
        compose.waitForIdle()
        condition()
    }

    private fun count(tag: String): Int = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().size

    private fun exists(tag: String): Boolean = compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()

    private fun height(tag: String): Float = compose.onNodeWithTag(tag).getUnclippedBoundsInRoot().height.value

    @Test
    fun aCutEntryShowsTheMarkerInEveryKind() {
        val kinds = listOf(
            ChatEntryRole.USER to ChatEntryKind.PROSE, ChatEntryRole.AGENT to ChatEntryKind.PROSE, ChatEntryRole.SYSTEM to ChatEntryKind.PROSE,
            ChatEntryRole.AGENT to ChatEntryKind.THOUGHT, ChatEntryRole.AGENT to ChatEntryKind.TOOL_USE,
            ChatEntryRole.SYSTEM to ChatEntryKind.STATUS, ChatEntryRole.AGENT to ChatEntryKind("x"),
        )
        entries = kinds.mapIndexed { i, (role, kind) -> entry(i + 1, role, kind, "abc", tool = "Bash", truncated = true) }
        show()
        until { count("agent.entry.cut") == 7 }
        entries = kinds.mapIndexed { i, (role, kind) -> entry(i + 1, role, kind, "abc", tool = "Bash") }
        until { count("agent.entry.cut") == 0 }
    }

    @Test
    fun aThoughtStartsCollapsedAndOpensOnTap() {
        val text = (1..12).joinToString("\n") { "Bước $it: kiểm tra lại giả định." }
        entries = listOf(entry(1, ChatEntryRole.AGENT, ChatEntryKind.THOUGHT, text))
        show()
        val collapsed = height("agent.entry.thought")
        assertTrue("collapsed: only the Thinking row, a full tap target ($collapsed)", collapsed >= 48f && collapsed < 64f)
        compose.onNodeWithTag("agent.entry.thought").performClick()
        compose.waitForIdle()
        assertTrue(height("agent.entry.thought") > collapsed + 100f)
    }

    @Test
    fun aToolCallStaysOnOneLineUntilTapped() {
        val tool = entry(1, ChatEntryRole.AGENT, ChatEntryKind.TOOL_USE, AgentFixtures.longLine + "\n" + AgentFixtures.codeLines.joinToString("\n"), tool = "Bash")
        entries = listOf(tool)
        show()
        val collapsed = height("agent.entry.tool")
        assertTrue("one line ($collapsed)", collapsed < 80f)
        compose.onNodeWithTag("agent.entry.tool").performClick()
        compose.waitForIdle()
        assertTrue(height("agent.entry.tool") > collapsed * 5)
    }

    @Test
    fun aLongCodeBlockWrapsWithinTheScreen() {
        entries = listOf(entry(1, ChatEntryRole.AGENT, ChatEntryKind.PROSE, AgentFixtures.code))
        assertTrue(AgentFixtures.code.encodeToByteArray().size <= ChatEntry.MAX_TEXT_BYTES)
        show()
        val bounds = compose.onNodeWithTag("agent.entry.e1").getUnclippedBoundsInRoot()
        assertTrue("a long line wraps, it never widens the chat (${bounds.width})", bounds.width <= 393.dp)
        assertTrue("every line shows (${bounds.height})", bounds.height > 600.dp)
    }

    private fun displayed(tag: String): Boolean = try {
        compose.onNodeWithTag(tag).assertIsDisplayed()
        true
    } catch (e: AssertionError) {
        false
    }

    @Test
    fun newEntriesAreFollowedOnlyAtTheBottom() {
        entries = (1..40).map { entry(it, ChatEntryRole.AGENT, ChatEntryKind.PROSE, "Dòng $it của câu trả lời.\nThêm một dòng nữa.") }
        show()
        until { displayed("agent.entry.e40") }
        compose.onNodeWithTag("agent.chat").performScrollToIndex(0)
        compose.waitForIdle()
        entries = entries + entry(41, ChatEntryRole.AGENT, ChatEntryKind.PROSE, "Dòng 41 mới.")
        until { exists("agent.newMessages") }
        assertTrue("never pulled down while reading older entries", !displayed("agent.entry.e41"))
        compose.onNodeWithTag("agent.newMessages").performClick()
        until { !exists("agent.newMessages") && displayed("agent.entry.e41") }
        entries = entries + entry(42, ChatEntryRole.AGENT, ChatEntryKind.PROSE, "Dòng 42 mới.")
        until { displayed("agent.entry.e42") }
        compose.waitForIdle()
        assertTrue("at the bottom, a new entry is followed", !exists("agent.newMessages"))
    }

    @Test
    fun theTopAsksForOlderEntries() {
        entries = everyKind.take(3)
        show(older = AgentThreadModel.Older.LOADABLE)
        until { olderAsks > 0 }
        compose.waitForIdle()
        assertEquals(1, olderAsks)
    }

    @Test
    fun stopTapsAndForceStopAsksFirst() {
        show(canStop = true)
        compose.onNodeWithTag("agent.stop").performClick()
        assertEquals(1, stops)
        compose.onNodeWithTag("agent.stop").performTouchInput { longClick() }
        compose.onNodeWithText(context.getString(R.string.agent_force_stop_menu)).performClick()
        compose.onNodeWithText(context.getString(R.string.agent_force_stop_title, "Claude Code", "shellx")).assertExists()
        assertEquals(0, forceStops)
        compose.onNodeWithText(context.getString(R.string.agent_force_stop)).performClick()
        assertEquals(1, forceStops)
        assertEquals(1, stops)
    }

    @Test
    fun closeAndRemoveSitWhereTheySay() {
        var embedded by mutableStateOf(false)
        compose.setContent {
            ShellXTheme {
                AgentScreen(
                    ref = ref, place = "Claude Code · MacBook Pro", row = { null }, gone = true, offline = false, pending = emptyList(),
                    showsMachineName = false, entries = everyKind, emptyState = null, machineName = "MacBook Pro",
                    older = AgentThreadModel.Older.NONE, loadingOlder = false, canStop = false, notice = null, draft = ComposerDraft(),
                    onDraftChange = {}, embedded = embedded, closeAgentName = "claude 12:00", canRemoveFromPhone = true,
                    actions = AgentScreenActions(closeAgent = { closes++ }, removeFromPhone = { removes++ }),
                )
            }
        }
        compose.onNodeWithTag("agent.menu").performClick()
        compose.onNodeWithText(context.getString(R.string.agent_close_menu)).performClick()
        compose.onNodeWithText(context.getString(R.string.agent_close_title, "claude 12:00")).assertExists()
        compose.onNodeWithText(context.getString(R.string.agent_close)).performClick()
        assertEquals(1, closes)
        assertTrue("a full tap target", height("agent.removeFromPhone") >= 48f)
        compose.onNodeWithTag("agent.removeFromPhone").performClick()
        assertEquals(1, removes)
        embedded = true
        compose.waitForIdle()
        assertTrue(!exists("agent.menu") && !exists("agent.removeFromPhone"))
    }
}
