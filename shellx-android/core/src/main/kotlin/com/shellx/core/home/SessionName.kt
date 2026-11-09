package com.shellx.core.home

import com.shellx.core.link.MachineSession
import com.shellx.core.link.SessionRef
import com.shellx.core.pending.AgentLabel
import com.shellx.core.text.nonEmptyLines
import com.shellx.core.text.words
import com.shellx.link.core.AgentSession
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** The name a session row shows: the session's own title, so rows of one workspace tell apart. */
object SessionName {
    private val TAG = Regex("<[^>]*>")
    private val CUT_TAG = Regex("<[^>]*$")
    private val TIME: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm", Locale.ROOT)

    /**
     * The first non-blank line of [title] that has text left, with every `<…>` tag removed (and a tag the Mac cut in
     * the middle), a leading `/command` word dropped (not a path such as `/Users/x`), and runs of whitespace collapsed
     * to one space; null when nothing is left.
     */
    fun cleaned(title: String?): String? {
        title ?: return null
        for (line in title.nonEmptyLines()) {
            val untagged = line.replace(TAG, " ").replace(CUT_TAG, " ")
            val words = untagged.words().toMutableList()
            val first = words.firstOrNull()
            if (first != null && first.startsWith("/") && !first.drop(1).contains("/")) words.removeAt(0)
            val text = words.joinToString(" ")
            if (text.isNotEmpty()) return text
        }
        return null
    }

    /** `cleaned(title)`, else "<AgentLabel> · HH:mm" from `lastActivityMs` (then `stateSinceMs`), else the label. */
    fun base(session: AgentSession, zone: ZoneId = ZoneId.systemDefault()): String {
        cleaned(session.title)?.let { return it }
        val label = AgentLabel.of(session.agent).text
        val ms = session.lastActivityMs ?: session.stateSinceMs ?: return label
        return "$label · ${TIME.format(Instant.ofEpochMilli(ms).atZone(zone))}"
    }

    /** The name each session shows in one list: equal bases get " · #2", " · #3"… in (machineId, sessionId) order. */
    fun distinct(sessions: List<MachineSession>, zone: ZoneId = ZoneId.systemDefault()): Map<SessionRef, String> {
        val ordered = sessions.sortedWith(compareBy<MachineSession> { it.machineId }.thenBy { it.session.sessionId })
        val seen = HashMap<String, Int>()
        val names = LinkedHashMap<SessionRef, String>()
        for (machineSession in ordered) {
            val base = base(machineSession.session, zone)
            val count = (seen[base] ?: 0) + 1
            seen[base] = count
            names[machineSession.ref] = if (count == 1) base else "$base · #$count"
        }
        return names
    }
}
