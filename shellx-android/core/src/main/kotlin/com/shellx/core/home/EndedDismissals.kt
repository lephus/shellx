package com.shellx.core.home

import com.shellx.core.link.MachineSession
import com.shellx.core.platform.Clock
import com.shellx.core.platform.KeyValueStore
import com.shellx.core.storage.JsonCodec
import com.shellx.core.storage.field
import com.shellx.core.storage.longValue
import com.shellx.core.storage.obj
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

/**
 * The ended sessions the user took off the phone's Ended list, each with the end time it had then
 * (EndedDismissals.swift). It only hides a session on this phone, exactly as the 12 hours do (HomeFocus.ENDED_FOR);
 * nothing is sent to the Mac.
 *
 * A dismissal is per Mac, session id and end time: a session that ended again later has a newer end time and shows
 * again, and one that is no longer ENDED is not on the list whatever this holds. [pruned] drops what the 12 hours
 * would have dropped anyway. Immutable.
 */
class EndedDismissals private constructor(
    /** The end time (HomeFocus.endedMs) each dismissed session had, by Mac and session id. */
    private val ends: Map<String, Map<String, Long>>,
) {
    /** True when the user dismissed this session and it has not ended again since. */
    fun hides(session: MachineSession): Boolean {
        val endedMs = HomeFocus.endedMs(session.session) ?: return false
        val dismissed = ends[session.machineId]?.get(session.session.sessionId) ?: return false
        return endedMs <= dismissed
    }

    /** Takes the session off the list. A session with no end time was never on it, so nothing is kept. */
    fun dismiss(session: MachineSession): EndedDismissals {
        val endedMs = HomeFocus.endedMs(session.session) ?: return this
        val id = session.session.sessionId
        val sessions = ends[session.machineId].orEmpty()
        val newest = maxOf(endedMs, sessions[id] ?: Long.MIN_VALUE)
        return EndedDismissals(ends + (session.machineId to sessions + (id to newest)))
    }

    /** Without the sessions whose end is HomeFocus.ENDED_FOR or more before [nowMs]: they are off the list anyway. */
    fun pruned(nowMs: Long): EndedDismissals {
        val kept = LinkedHashMap<String, Map<String, Long>>()
        for ((machineId, sessions) in ends) {
            val fresh = sessions.filterValues { HomeFocus.endedAge(it, nowMs) < HomeFocus.ENDED_FOR }
            if (fresh.isNotEmpty()) kept[machineId] = fresh
        }
        return EndedDismissals(kept)
    }

    override fun equals(other: Any?): Boolean = other is EndedDismissals && ends == other.ends

    override fun hashCode(): Int = ends.hashCode()

    override fun toString(): String = "EndedDismissals(${ends.values.sumOf { it.size }} sessions)"

    companion object {
        val NONE: EndedDismissals = EndedDismissals(emptyMap())

        /** `{"ends":{"<machineId>":{"<sessionId>":<endMs>}}}`. */
        val CODEC: JsonCodec<EndedDismissals> = object : JsonCodec<EndedDismissals> {
            override fun encode(value: EndedDismissals): JsonElement = buildJsonObject {
                putJsonObject("ends") {
                    for ((machineId, sessions) in value.ends) {
                        putJsonObject(machineId) { for ((sessionId, endMs) in sessions) put(sessionId, endMs) }
                    }
                }
            }

            override fun decode(json: JsonElement): EndedDismissals {
                val ends = json.obj("dismissals").field("ends").obj("ends").mapValues { (_, sessions) ->
                    sessions.obj("sessions").mapValues { (sessionId, endMs) -> endMs.longValue(sessionId) }
                }
                return EndedDismissals(ends)
            }
        }
    }
}

/**
 * Keeps [EndedDismissals] in the settings under [KEY], so a dismissal outlives a relaunch for as long as the 12 hours
 * would have kept the session. Old entries go at each launch and each dismissal. Saved text it cannot read counts as no
 * dismissals. Main-confined.
 */
class EndedDismissalStore(private val settings: KeyValueStore, private val clock: Clock) {
    companion object {
        const val KEY = "shellx.dismissedEnded"
    }

    private val _dismissals: MutableStateFlow<EndedDismissals>
    val dismissals: StateFlow<EndedDismissals>

    init {
        val saved = settings.getString(KEY)?.let { text ->
            try {
                EndedDismissals.CODEC.decode(Json.parseToJsonElement(text))
            } catch (_: IllegalArgumentException) {
                null
            }
        }
        _dismissals = MutableStateFlow((saved ?: EndedDismissals.NONE).pruned(clock.nowMs()))
        dismissals = _dismissals.asStateFlow()
        if (_dismissals.value != saved) save()
    }

    /** The user took the session off the Ended list. */
    fun dismiss(session: MachineSession) {
        _dismissals.value = _dismissals.value.dismiss(session).pruned(clock.nowMs())
        save()
    }

    private fun save() {
        val value = _dismissals.value
        if (value == EndedDismissals.NONE) {
            settings.remove(KEY)
        } else {
            settings.putString(KEY, EndedDismissals.CODEC.encode(value).toString())
        }
    }
}
