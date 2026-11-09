package com.shellx.core.home

import com.shellx.core.link.MachineSession
import com.shellx.core.testing.agentSession
import com.shellx.link.core.AgentSession
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** The name each session row shows: its own title, de-duplicated within one list. */
class SessionNameTest {
    private fun titled(id: String, title: String?): AgentSession = agentSession(id).copy(title = title)

    private fun onMac(machineId: String, session: AgentSession): MachineSession =
        MachineSession(machineId, machineId, true, session)

    @Test fun cleanedKeepsAPlainTitle() {
        assertEquals("Sửa nút ＋ trên iOS 🚀", SessionName.cleaned("Sửa nút ＋ trên iOS 🚀"))
    }

    @Test fun cleanedTakesTheFirstNonBlankLineAndCollapsesSpaces() {
        assertEquals("Viết test SessionSet", SessionName.cleaned("\n  \n  Viết test   SessionSet \nmore"))
    }

    @Test fun cleanedDropsTagsAndALeadingSlashCommand() {
        assertEquals("brainstorm", SessionName.cleaned("<command-message>brainstorm</command-message>"))
        assertEquals("fix the login bug", SessionName.cleaned("/review fix the login bug"))
        assertNull(SessionName.cleaned("<command-name>/clear</command-name>"))
    }

    @Test fun cleanedKeepsAPathThatStartsWithASlash() {
        assertEquals("/Users/x/app crashes", SessionName.cleaned("/Users/x/app crashes"))
    }

    @Test fun cleanedDropsATagTheMacCutInTheMiddle() {
        assertEquals("fix the login", SessionName.cleaned("fix the login <command-mess"))
        assertNull(SessionName.cleaned("<command-mess"))
    }

    @Test fun cleanedTriesTheNextLineWhenTheFirstIsOnlyTags() {
        assertEquals("fix the login", SessionName.cleaned("<command-name>/clear</command-name>\n  \nfix the login"))
    }

    @Test fun cleanedIsNilForNothing() {
        assertNull(SessionName.cleaned(null))
        assertNull(SessionName.cleaned("   \n "))
    }

    @Test fun baseFallsBackToAgentAndTime() {
        var s = agentSession("s1", lastActivityMs = 1_793_284_320_000) // 2026-10-29 14:32:00 UTC
        s = s.copy(title = null)
        assertEquals("Claude Code · 14:32", SessionName.base(s, ZoneId.of("UTC")))
        s = s.copy(lastActivityMs = null, stateSinceMs = null)
        assertEquals("Claude Code", SessionName.base(s))
    }

    @Test fun distinctNumbersEqualNamesInSessionOrder() {
        val sessions = listOf(
            onMac("m1", titled("s3", "Fix bug")), onMac("m1", titled("s1", "Fix bug")),
            onMac("m1", titled("s2", "Fix bug")), onMac("m1", titled("s4", "Docs")),
        )
        val names = SessionName.distinct(sessions)
        fun name(id: String): String? = names[sessions.first { it.session.sessionId == id }.ref]
        assertEquals("Fix bug", name("s1"))
        assertEquals("Fix bug · #2", name("s2"))
        assertEquals("Fix bug · #3", name("s3"))
        assertEquals("Docs", name("s4"))
    }

    @Test fun distinctKeepsTheSameSessionIdOnTwoMacsApart() {
        val a = onMac("m1", titled("s1", "Fix bug"))
        val b = onMac("m2", titled("s1", "Fix bug"))
        val names = SessionName.distinct(listOf(b, a))
        assertEquals(2, names.size)
        assertEquals("Fix bug", names[a.ref])
        assertEquals("Fix bug · #2", names[b.ref])
    }
}
