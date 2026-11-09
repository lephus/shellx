package com.shellx.core.home

import com.shellx.core.link.MachineSession
import com.shellx.core.link.SessionRef
import com.shellx.core.platform.Clock
import com.shellx.core.platform.KeyValueStore
import com.shellx.core.storage.JsonCodec
import com.shellx.core.storage.field
import com.shellx.core.storage.long
import com.shellx.core.storage.obj
import com.shellx.core.storage.optLong
import com.shellx.core.storage.string
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import kotlin.time.Duration
import kotlin.time.Duration.Companion.days
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

/**
 * The sessions the user removed from this phone after their Mac answered `not_found` for them ("This session is gone
 * from the Mac", spec 6.8), each with what the Mac reported for it then (GoneRemovals.swift). It only hides a session
 * on this phone, as the Ended page's trash does (EndedDismissals); nothing is sent to the Mac.
 *
 * A removal is per Mac and session id, stamped with the session's state, when it entered it and its last activity.
 * The session stays hidden while its Mac reports exactly that stamp; any change shows it again. [shown] is the one
 * filter every list and count of the phone's sessions goes through. [pruned] drops removals made [KEPT_FOR] or more
 * ago, by the phone's clock. Immutable.
 */
class GoneRemovals private constructor(
    /** By Mac, then by session id. */
    private val removals: Map<String, Map<String, Removal>>,
) {
    /** What the Mac reported for a session: a removal holds while it reports the same. */
    data class Stamp(val state: AgentState, val stateSinceMs: Long?, val lastActivityMs: Long?) {
        companion object {
            fun of(session: AgentSession): Stamp = Stamp(session.state, session.stateSinceMs, session.lastActivityMs)
        }
    }

    /** [removedAtMs] is when the user removed it, by the phone's clock. */
    private data class Removal(val stamp: Stamp, val removedAtMs: Long)

    /** True when the user removed this session and its Mac reports it exactly as it did then. */
    fun hides(session: MachineSession): Boolean =
        removals[session.machineId]?.get(session.session.sessionId)?.stamp == Stamp.of(session.session)

    /** [sessions] without the ones this hides, in their order. */
    fun shown(sessions: List<MachineSession>): List<MachineSession> =
        if (removals.isEmpty()) sessions else sessions.filter { !hides(it) }

    /** Hides the session as its Mac reports it now; [atMs] is when, by the phone's clock. A removal of the same session
     *  made before is replaced. */
    fun remove(session: MachineSession, atMs: Long): GoneRemovals {
        val sessions = removals[session.machineId].orEmpty()
        val removal = Removal(Stamp.of(session.session), atMs)
        return GoneRemovals(removals + (session.machineId to sessions + (session.session.sessionId to removal)))
    }

    /** Without the removals made KEPT_FOR or more before [nowMs]. One made after [nowMs] (the phone's clock went back)
     *  is kept. */
    fun pruned(nowMs: Long): GoneRemovals {
        val kept = LinkedHashMap<String, Map<String, Removal>>()
        for ((machineId, sessions) in removals) {
            val fresh = sessions.filterValues { maxOf(0, nowMs - it.removedAtMs) < KEPT_FOR.inWholeMilliseconds }
            if (fresh.isNotEmpty()) kept[machineId] = fresh
        }
        return GoneRemovals(kept)
    }

    override fun equals(other: Any?): Boolean = other is GoneRemovals && removals == other.removals

    override fun hashCode(): Int = removals.hashCode()

    override fun toString(): String = "GoneRemovals(${removals.values.sumOf { it.size }} sessions)"

    companion object {
        /** How long a removal is kept, counted from when it was made: 30 days. */
        val KEPT_FOR: Duration = 30.days

        val NONE: GoneRemovals = GoneRemovals(emptyMap())

        /**
         * `{"removals":{"<machineId>":{"<sessionId>":{"stamp":{"state","state_since_ms"?,"last_activity_ms"?},
         * "removed_at_ms"}}}}`, the state as its wire string.
         */
        val CODEC: JsonCodec<GoneRemovals> = object : JsonCodec<GoneRemovals> {
            override fun encode(value: GoneRemovals): JsonElement = buildJsonObject {
                putJsonObject("removals") {
                    for ((machineId, sessions) in value.removals) {
                        putJsonObject(machineId) {
                            for ((sessionId, removal) in sessions) {
                                putJsonObject(sessionId) {
                                    putJsonObject("stamp") {
                                        put("state", removal.stamp.state.wire)
                                        removal.stamp.stateSinceMs?.let { put("state_since_ms", it) }
                                        removal.stamp.lastActivityMs?.let { put("last_activity_ms", it) }
                                    }
                                    put("removed_at_ms", removal.removedAtMs)
                                }
                            }
                        }
                    }
                }
            }

            override fun decode(json: JsonElement): GoneRemovals {
                val removals = json.obj("removals").field("removals").obj("removals").mapValues { (_, sessions) ->
                    sessions.obj("sessions").mapValues { (_, element) ->
                        val removal = element.obj("removal")
                        val stamp = removal.field("stamp").obj("stamp")
                        Removal(
                            Stamp(AgentState(stamp.string("state")), stamp.optLong("state_since_ms"), stamp.optLong("last_activity_ms")),
                            removal.long("removed_at_ms"),
                        )
                    }
                }
                return GoneRemovals(removals)
            }
        }
    }
}

/** What [GoneRemovalStore] holds: the saved removals, and the sessions seen gone this run (never saved). */
data class GoneRemovalState(
    val removals: GoneRemovals = GoneRemovals.NONE,
    val knownGone: Map<SessionRef, GoneRemovals.Stamp> = emptyMap(),
)

/**
 * Keeps [GoneRemovals] in the settings under [KEY], so a removal outlives a relaunch for 30 days. Old entries go at each
 * launch and each removal. Saved text it cannot read counts as no removals.
 *
 * It also knows, for this run only, which sessions an agent screen heard answered `not_found` for ([noteGone]): only
 * those swipe to "Remove from This Phone", while their Mac reports them as it did then. The phone cannot tell a ghost
 * from a live session before it asks, and a live session never gets the action. Main-confined.
 */
class GoneRemovalStore(private val settings: KeyValueStore, private val clock: Clock) {
    companion object {
        const val KEY = "shellx.removedGone"
    }

    private val _state: MutableStateFlow<GoneRemovalState>
    val state: StateFlow<GoneRemovalState>

    val removals: GoneRemovals get() = state.value.removals

    init {
        val saved = settings.getString(KEY)?.let { text ->
            try {
                GoneRemovals.CODEC.decode(Json.parseToJsonElement(text))
            } catch (_: IllegalArgumentException) {
                null
            }
        }
        _state = MutableStateFlow(GoneRemovalState(removals = (saved ?: GoneRemovals.NONE).pruned(clock.nowMs())))
        state = _state.asStateFlow()
        if (removals != saved) save()
    }

    /** An agent screen heard its Mac answer `not_found` for this session, which the Mac still lists
     *  (AgentThreadModel.ghost). */
    fun noteGone(session: MachineSession) {
        val stamp = GoneRemovals.Stamp.of(session.session)
        if (state.value.knownGone[session.ref] != stamp) {
            _state.update { it.copy(knownGone = it.knownGone + (session.ref to stamp)) }
        }
    }

    /** The session's card swipes to "Remove from This Phone": it was seen gone this run and its Mac reports it as it
     *  did then. */
    fun canRemove(session: MachineSession): Boolean = state.value.knownGone[session.ref] == GoneRemovals.Stamp.of(session.session)

    /** The ones of [sessions] that [canRemove]. */
    fun removable(sessions: List<MachineSession>): Set<SessionRef> {
        if (state.value.knownGone.isEmpty()) return emptySet()
        return sessions.filter { canRemove(it) }.map { it.ref }.toSet()
    }

    /** The user removed the session from this phone (the agent screen, or a card's swipe). */
    fun remove(session: MachineSession) {
        val now = clock.nowMs()
        _state.update { it.copy(removals = it.removals.remove(session, now).pruned(now)) }
        save()
    }

    private fun save() {
        val value = removals
        if (value == GoneRemovals.NONE) {
            settings.remove(KEY)
        } else {
            settings.putString(KEY, GoneRemovals.CODEC.encode(value).toString())
        }
    }
}
