package com.shellx.app.ui.theme

import android.content.Context
import android.content.res.Resources
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.home.AgentStatusRow
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.SessionRef
import com.shellx.link.core.AgentState
import java.util.Locale
import kotlin.time.Duration
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** The words and tones of a Mac's link state and of an agent's state (MachinesRenderTests, AgentStateStyle.swift). */
@RunWith(AndroidJUnit4::class)
class StylesTest {
    private val res: Resources = ApplicationProvider.getApplicationContext<Context>().resources

    /** MachinesRenderTests.swift's `everyState`. */
    private val everyState: List<Pair<String, MachineLinkState>> = listOf(
        "MacBook Pro" to MachineLinkState.Online,
        "Mac mini" to MachineLinkState.Connecting,
        "iMac" to MachineLinkState.Reconnecting,
        "Mac Studio" to MachineLinkState.Offline(1_700_000_000_000),
        "Mac của Lan" to MachineLinkState.Revoked,
        "Mac Pro" to MachineLinkState.HostKeyChanged,
        "MacBook Air" to MachineLinkState.NeedsUpdate,
    )

    private fun row(state: AgentState, online: Boolean = true, elapsed: Duration? = null) =
        AgentStatusRow(SessionRef("m1", "s1", "claude", "shellx-ios"), "MacBook Pro", state, online, elapsed)

    @Test
    fun everyMacStateHasWordsAndATone() {
        val styles = everyState.map { (name, state) -> MachineStateStyle.of(state, name, res) }
        for (style in styles) assertFalse(style.text.isEmpty())
        assertEquals(StatusTone.DONE, styles[0].tone)
        assertEquals("connecting and reconnecting read the same", styles[1], styles[2])
        assertTrue("offline names the Mac", styles[3].text.contains("Mac Studio"))
        assertEquals(6, styles.map { it.text }.toSet().size)
    }

    @Test
    fun agentStatesReadAsOnTheIPhone() {
        val offline = AgentStateStyle.of(row(AgentState.WORKING, online = false), res)
        assertEquals("Mac offline", offline.text)
        assertEquals("Mac offline", offline.shortText)
        assertEquals(StatusTone.IDLE, offline.tone)

        val needsYou = AgentStateStyle.of(row(AgentState.NEEDS_INPUT), res)
        assertEquals("Needs you", needsYou.text)
        assertEquals(StatusTone.NEEDS_YOU, needsYou.tone)

        val running = AgentStateStyle.of(row(AgentState.WORKING, elapsed = 4.minutes), res)
        assertEquals("Running for 4 minutes", running.text)
        assertEquals("4 minutes", running.shortText)
        assertEquals(StatusTone.RUNNING, running.tone)

        val runningNoTime = AgentStateStyle.of(row(AgentState.WORKING), res)
        assertEquals("Running", runningNoTime.text)
        assertEquals("Running", runningNoTime.shortText)

        val done = AgentStateStyle.of(row(AgentState.IDLE), res)
        assertEquals("Done", done.text)
        assertEquals(StatusTone.DONE, done.tone)

        val ended = AgentStateStyle.of(row(AgentState.ENDED), res)
        assertEquals("Ended", ended.text)
        assertEquals(StatusTone.IDLE, ended.tone)

        val unknown = AgentStateStyle.of(row(AgentState("teleport")), res)
        assertNull(unknown.text)
        assertNull(unknown.shortText)
        assertNull(unknown.tone)
    }

    @Test
    fun durationsAreInTheAppLanguage() {
        val en = Locale.ENGLISH
        assertEquals("8 minutes", AgentStateStyle.elapsedText(8.minutes, en))
        assertEquals("1 minute", AgentStateStyle.elapsedText(1.minutes, en))
        assertEquals("45 seconds", AgentStateStyle.elapsedText(45.seconds, en))
        assertEquals("1 hour, 5 minutes", AgentStateStyle.elapsedText(65.minutes, en))
        assertEquals("2 hours", AgentStateStyle.elapsedText(120.minutes, en))
        assertEquals("8 phút", AgentStateStyle.elapsedText(8.minutes, Locale("vi")))
    }

    @Test
    fun theAppLanguageIsVietnameseOrEnglish() {
        assertEquals("vi", AppLanguage.of(Locale("vi", "VN")).language)
        assertEquals("en", AppLanguage.of(Locale.FRANCE).language)
        assertEquals("en", AppLanguage.of(Locale.UK).language)
    }
}
