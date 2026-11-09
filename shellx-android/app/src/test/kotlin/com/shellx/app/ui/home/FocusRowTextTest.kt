package com.shellx.app.ui.home

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.testing.HomeFixtures
import com.shellx.app.testing.HomeFixtures.NOW_MS
import com.shellx.app.testing.HomeFixtures.mockup
import com.shellx.app.ui.theme.AgentStateStyle
import com.shellx.app.ui.workspaces.OtherSessionsModel
import com.shellx.core.home.FocusItem
import com.shellx.core.home.HomeFocus
import com.shellx.core.link.MachineSession
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import java.util.Locale
import kotlin.time.Duration.Companion.minutes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** What the home's cards say (WorkspaceListRenderTests' word checks, WaitingBorderRenderTests' border rule). */
@RunWith(AndroidJUnit4::class)
class FocusRowTextTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val text = FocusRowText(context.resources, Locale.ENGLISH)

    private fun minutes(n: Int): String = AgentStateStyle.elapsedText(n.minutes, Locale.ENGLISH)

    private fun ago(n: Int): String = context.getString(R.string.home_ago, minutes(n))

    private fun line(item: FocusItem, kind: FocusKind): String = text.subLine(item, kind, NOW_MS, showsMachineName = false)

    private fun FocusItem.withSession(change: (AgentSession) -> AgentSession): FocusItem =
        copy(session = session.copy(session = change(session.session)))

    @Test
    fun theMockupCardsSayWhatTheIPhoneSays() {
        assertEquals(
            listOf(context.getString(R.string.agent_state_needs_you)),
            mockup.needsYou.map { text.tag(it, FocusKind.NEEDS_YOU, NOW_MS) },
        )
        assertEquals(listOf(minutes(8), minutes(1)), mockup.running.map { text.tag(it, FocusKind.RUNNING, NOW_MS) })
        assertEquals(
            listOf(context.getString(R.string.agent_state_done)),
            mockup.justDone.map { text.tag(it, FocusKind.JUST_DONE, NOW_MS) },
        )
        assertEquals(listOf(null, null, null), mockup.ended.map { text.tag(it, FocusKind.ENDED, NOW_MS) })

        assertEquals("toknix · Codex", text.subLine(mockup.running[1], FocusKind.RUNNING, NOW_MS, showsMachineName = false))
        assertEquals(
            "shellx · Claude Code · MacBook Pro · " + ago(12),
            text.subLine(mockup.justDone[0], FocusKind.JUST_DONE, NOW_MS, showsMachineName = true),
        )
        assertEquals(
            "“Cho phép chạy xcodebuild?”",
            FocusRowText.quotedQuestion(mockup.needsYou[0], FocusKind.NEEDS_YOU),
        )
        assertNull(FocusRowText.quotedQuestion(mockup.running[0], FocusKind.RUNNING))
    }

    @Test
    fun everySubLineEndsWithATimeExceptRunning() {
        assertEquals("shellx · Claude Code · ${minutes(2)}", line(mockup.needsYou[0], FocusKind.NEEDS_YOU))
        assertEquals("shellx · Claude Code", line(mockup.running[0], FocusKind.RUNNING))
        assertEquals("shellx · Claude Code · ${ago(12)}", line(mockup.justDone[0], FocusKind.JUST_DONE))
        assertEquals("shellx · Claude Code · ${ago(30)}", line(mockup.ended[0], FocusKind.ENDED))
        assertEquals("relay · Claude Code · ${ago(95)}", line(mockup.ended[1], FocusKind.IDLE))

        // Without the Mac's time there is none; needs you falls back to the last activity.
        val bare = mockup.ended[0].withSession { it.copy(stateSinceMs = null, lastActivityMs = null) }
        assertEquals("shellx · Claude Code", line(bare, FocusKind.ENDED))
        assertEquals("shellx · Claude Code", line(bare, FocusKind.IDLE))
        var waiting = mockup.needsYou[0].withSession { it.copy(stateSinceMs = null) }
        assertEquals("shellx · Claude Code · ${minutes(2)}", line(waiting, FocusKind.NEEDS_YOU))
        waiting = waiting.withSession { it.copy(lastActivityMs = null) }
        assertEquals("shellx · Claude Code", line(waiting, FocusKind.NEEDS_YOU))
        val unfinished = mockup.justDone[0].copy(finishedAtMs = null)
        assertEquals("shellx · Claude Code", line(unfinished, FocusKind.JUST_DONE))
    }

    @Test
    fun timesUnderAMinuteAreOneMinuteAndNeverNegative() {
        val oneMinute = minutes(1)
        // The clock behind the finish, at it, and under a minute after.
        for (offsetSeconds in listOf(-30L, 0L, 20L, 59L)) {
            val finished = mockup.justDone[0].copy(finishedAtMs = NOW_MS - offsetSeconds * 1000)
            assertEquals(
                "offset $offsetSeconds",
                "shellx · Claude Code · " + context.getString(R.string.home_ago, oneMinute),
                text.subLine(finished, FocusKind.JUST_DONE, NOW_MS, showsMachineName = false),
            )
        }
        var running = mockup.running[1].withSession { it.copy(stateSinceMs = NOW_MS - 25_000) }
        assertEquals(oneMinute, text.tag(running, FocusKind.RUNNING, NOW_MS))
        running = running.withSession { it.copy(stateSinceMs = NOW_MS + 5_000) }
        assertEquals(oneMinute, text.tag(running, FocusKind.RUNNING, NOW_MS))
        assertNull(text.tag(running, FocusKind.IDLE, NOW_MS))
    }

    @Test
    fun anOtherSessionIsDrawnByItsState() {
        fun session(state: AgentState) = AgentSession("s", "claude", "", "", state = state)
        val fresh = NOW_MS - 10 * 60_000
        val old = NOW_MS - (HomeFocus.JUST_DONE_FOR.inWholeMilliseconds + 60_000)
        assertEquals(FocusKind.NEEDS_YOU, OtherSessionsModel.kind(session(AgentState.NEEDS_INPUT), null, NOW_MS))
        assertEquals(FocusKind.RUNNING, OtherSessionsModel.kind(session(AgentState.WORKING), null, NOW_MS))
        assertEquals(FocusKind.JUST_DONE, OtherSessionsModel.kind(session(AgentState.IDLE), fresh, NOW_MS))
        assertEquals("an hour on, it is idle", FocusKind.IDLE, OtherSessionsModel.kind(session(AgentState.IDLE), old, NOW_MS))
        assertEquals(FocusKind.IDLE, OtherSessionsModel.kind(session(AgentState.IDLE), null, NOW_MS))
        assertEquals(FocusKind.ENDED, OtherSessionsModel.kind(session(AgentState.ENDED), null, NOW_MS))
        assertEquals(
            "a finish newer than the clock is not an error",
            FocusKind.JUST_DONE,
            OtherSessionsModel.kind(session(AgentState.IDLE), NOW_MS + 5_000, NOW_MS),
        )
    }

    @Test
    fun onlyANeedsYouCardOfAnOnlineMacHasTheWaitingBorder() {
        fun item(state: AgentState, online: Boolean = true) = FocusItem(
            MachineSession("m1", "MacBook Pro", online, AgentSession("s1", "claude", "ws-x", "x", state = state)),
            name = "x",
        )
        for (kind in FocusKind.entries) {
            assertEquals("$kind", kind == FocusKind.NEEDS_YOU, FocusRowText.showsWaitingBorder(item(AgentState.NEEDS_INPUT), kind))
        }
        // The group decides: a session with a request waiting is in "needs you" whatever state it reports.
        assertTrue(FocusRowText.showsWaitingBorder(item(AgentState.WORKING), FocusKind.NEEDS_YOU))
        assertFalse(
            "a card of a Mac that is not online fades and has no border",
            FocusRowText.showsWaitingBorder(item(AgentState.NEEDS_INPUT, online = false), FocusKind.NEEDS_YOU),
        )
        // The fixtures stay the mockup's.
        assertEquals("Sửa nút ＋ trên iOS", HomeFixtures.mockup.needsYou[0].name)
    }
}
