package com.shellx.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.ui.agent.AgentFixtures
import com.shellx.app.ui.agent.AgentFixtures.entry
import com.shellx.app.ui.agent.AgentFixtures.everyKind
import com.shellx.app.ui.agent.AgentNotice
import com.shellx.app.ui.agent.AgentScreen
import com.shellx.app.ui.agent.ChatEntryRow
import com.shellx.app.ui.agent.NewMessagesButton
import com.shellx.core.agent.AgentThreadModel
import com.shellx.core.agent.ChatThread
import com.shellx.core.composer.ComposerDraft
import com.shellx.core.home.AgentStatusRow
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.MachineSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.ChatEntry
import com.shellx.link.core.ChatEntryKind
import com.shellx.link.core.ChatEntryRole
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Every render of `AgentRenderTests.swift`: the entry kinds, cut entries, a long code block, a thought, 500 entries,
 *  the empty, loading, offline, failed and gone states, large text, a workspace's pane and "New messages". */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
class AgentRenderTest {
    @Composable
    private fun Screen(
        session: MachineSession? = AgentFixtures.session,
        entries: List<ChatEntry> = everyKind,
        pending: List<MachinePendingItem> = emptyList(),
        gone: Boolean = false,
        offline: Boolean = false,
        emptyState: AgentThreadModel.EmptyState? = null,
        older: AgentThreadModel.Older = AgentThreadModel.Older.NONE,
        notice: String? = null,
        draft: String = "",
        canRemoveFromPhone: Boolean = false,
        embedded: Boolean = false,
    ) {
        val row = session?.let { AgentStatusRow.of(it, AgentFixtures.NOW_MS) }
        val canStop = row?.let { it.online && (it.state == AgentState.WORKING || it.state == AgentState.NEEDS_INPUT) } ?: false
        AgentScreen(
            ref = AgentFixtures.ref, place = "Claude Code · MacBook Pro", row = { row }, gone = gone, offline = offline,
            pending = pending, showsMachineName = false, entries = entries,
            emptyState = if (entries.isEmpty()) emptyState else null, machineName = "MacBook Pro", older = older,
            loadingOlder = false, canStop = canStop && !gone, notice = notice?.let { AgentNotice(it) },
            draft = ComposerDraft(text = draft), onDraftChange = {}, embedded = embedded, canRemoveFromPhone = canRemoveFromPhone,
        )
    }

    private val offlineSession = AgentFixtures.session.copy(online = false)

    @Test
    fun agentKinds() {
        assertRenders("agent-kinds") {
            Screen(pending = listOf(AgentFixtures.pending), notice = LocalContext.current.getString(R.string.agent_stop_sent))
        }
    }

    @Test
    fun agentCut() {
        val text = "Log rất dài… ".repeat(20)
        val cut = entry(1, ChatEntryRole.AGENT, ChatEntryKind.PROSE, text, truncated = true)
        val whole = entry(1, ChatEntryRole.AGENT, ChatEntryKind.PROSE, text)
        val mine = entry(3, ChatEntryRole.USER, ChatEntryKind.PROSE, text, truncated = true)
        // The Swift test shows the same entry whole and cut; ids differ here, as a lazy list's keys must.
        assertRenders("agent-cut") { Screen(entries = listOf(whole, cut.copy(id = "e2", seq = 2), mine)) }
    }

    @Test
    fun agentCode() {
        val code = entry(1, ChatEntryRole.AGENT, ChatEntryKind.PROSE, AgentFixtures.code)
        val tool = entry(2, ChatEntryRole.AGENT, ChatEntryKind.TOOL_USE, AgentFixtures.longLine + "\n" + AgentFixtures.codeLines.joinToString("\n"), tool = "Bash")
        assertRenders("agent-code") { Screen(entries = listOf(code, tool)) }
    }

    @Test
    fun agentThought() {
        val thought = entry(1, ChatEntryRole.AGENT, ChatEntryKind.THOUGHT, (1..12).joinToString("\n") { "Bước $it: kiểm tra lại giả định." })
        assertRenders("agent-thought") {
            Column(
                Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(top = 60.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                ChatEntryRow(thought, "Claude Code", Modifier.padding(horizontal = 16.dp))
                ChatEntryRow(thought, "Claude Code", Modifier.padding(horizontal = 16.dp), initiallyExpanded = true)
            }
        }
    }

    @Test
    fun agent500() {
        val text = "ệ".repeat(1_365) + "a"
        assertEquals(ChatEntry.MAX_TEXT_BYTES, text.encodeToByteArray().size)
        val entries = (1..ChatThread.MAX_ENTRIES).map { seq ->
            entry(
                seq, if (seq % 7 == 0) ChatEntryRole.USER else ChatEntryRole.AGENT,
                if (seq % 5 == 0) ChatEntryKind.TOOL_USE else ChatEntryKind.PROSE, text, tool = "Bash", truncated = true,
            )
        }
        assertRenders("agent-500") { Screen(entries = entries, older = AgentThreadModel.Older.ONLY_ON_MAC) }
    }

    @Test
    fun agentEmpty() {
        assertRenders("agent-empty") { Screen(entries = emptyList(), emptyState = AgentThreadModel.EmptyState.NO_MESSAGES) }
    }

    @Test
    fun agentLoading() {
        assertRenders("agent-loading") { Screen(entries = emptyList(), emptyState = AgentThreadModel.EmptyState.LOADING) }
    }

    @Test
    fun agentOffline() {
        assertRenders("agent-offline") { Screen(session = offlineSession, offline = true, draft = "Còn đó không?") }
    }

    @Test
    fun agentOfflineEmpty() {
        assertRenders("agent-offline-empty") {
            Screen(session = offlineSession, entries = emptyList(), offline = true, emptyState = AgentThreadModel.EmptyState.OFFLINE)
        }
    }

    @Test
    fun agentFailed() {
        assertRenders("agent-failed") { Screen(entries = emptyList(), emptyState = AgentThreadModel.EmptyState.FAILED) }
    }

    @Test
    fun agentGone() {
        assertRenders("agent-gone") { Screen(session = null, gone = true) }
    }

    @Test
    fun agentGoneEmpty() {
        assertRenders("agent-gone-empty") { Screen(session = null, entries = emptyList(), gone = true, emptyState = AgentThreadModel.EmptyState.GONE) }
    }

    /** Still listed as running by its Mac, which answered `not_found`: it can be removed from the phone. */
    @Test
    fun agentGoneRemovable() {
        assertRenders("agent-gone-removable") { Screen(gone = true, canRemoveFromPhone = true) }
    }

    @Test
    fun agentGoneRemovableEmpty() {
        assertRenders("agent-gone-removable-empty") {
            Screen(entries = emptyList(), gone = true, emptyState = AgentThreadModel.EmptyState.GONE, canRemoveFromPhone = true)
        }
    }

    @Test
    fun agentOlderFailed() {
        assertRenders("agent-older-failed") { Screen(entries = everyKind.take(3), older = AgentThreadModel.Older.FAILED) }
    }

    @Test
    fun agentAx3() {
        assertRenders("agent-ax3") { LargeText { Screen(pending = listOf(AgentFixtures.pending), older = AgentThreadModel.Older.LOADABLE) } }
    }

    @Test
    fun agentGoneRemovableAx3() {
        assertRenders("agent-gone-removable-ax3") { LargeText { Screen(gone = true, canRemoveFromPhone = true) } }
    }

    @Test
    fun agentGonePane() {
        assertRenders("agent-gone-pane") { Screen(gone = true, canRemoveFromPhone = true, embedded = true) }
    }

    @Test
    fun agentNewMessages() {
        assertRenders("agent-new-messages") {
            Column(
                Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Spacer(Modifier.weight(1f))
                NewMessagesButton {}
                Spacer(Modifier.fillMaxWidth().height(120.dp))
            }
        }
    }
}
