package com.shellx.core.home

import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.MachineSession
import com.shellx.core.platform.MemoryKeyValueStore
import com.shellx.core.testing.ManualClock
import com.shellx.core.testing.agentSession
import com.shellx.core.testing.pendingItem
import com.shellx.link.core.AgentState
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * The sessions gone from their Mac that the user removed from this phone: a removal hides a session only while its
 * Mac reports exactly what it reported then, every home group and count leaves it out, the removals survive a launch
 * for 30 days, and only a session the phone saw answered `not_found` this run swipes to be removed.
 */
class GoneRemovalsTest {
    private val nowMs = 1_800_000_000_000L
    private val dayMs = 86_400_000L

    private fun ms(ago: Double): Long = nowMs - (ago * 1000).toLong()

    /** A session as its Mac reports it: by default one that has said "working" for 52 hours. */
    private fun ghost(
        id: String = "s",
        machine: String = "m1",
        state: AgentState = AgentState.WORKING,
        since: Double = 52 * 3600.0,
        activity: Double = 52 * 3600.0,
        workspace: String = "shellx",
    ) = MachineSession(
        machine, machine, true,
        agentSession(id, state = state, lastActivityMs = ms(ago = activity), stateSinceMs = ms(ago = since), workspace = workspace),
    )

    private fun removing(vararg sessions: MachineSession, atMs: Long = nowMs): GoneRemovals =
        sessions.fold(GoneRemovals.NONE) { removals, session -> removals.remove(session, atMs) }

    /** A store over [settings] whose clock stands [offsetMs] after now. */
    private fun makeStore(settings: MemoryKeyValueStore, offsetMs: Long = 0): GoneRemovalStore =
        GoneRemovalStore(settings, ManualClock(nowMs + offsetMs))

    // The value

    @Test fun nothingIsHiddenUntilItIsRemoved() {
        assertFalse(GoneRemovals.NONE.hides(ghost()))
        assertTrue(removing(ghost()).hides(ghost()))
    }

    @Test fun aRemovalHidesOnlyWhatTheMacReportedThen() {
        val removals = removing(ghost())
        assertTrue(removals.hides(ghost()), "the same state, since and last activity")
        assertFalse(removals.hides(ghost(activity = 60.0)), "a newer last activity shows it again")
        assertFalse(removals.hides(ghost(since = 3600.0)), "another time it entered its state shows it again")
        assertFalse(removals.hides(ghost(state = AgentState.IDLE)), "another state shows it again")
        assertFalse(removals.hides(ghost(state = AgentState.ENDED)), "an end shows it again")
    }

    @Test fun aStampWithoutTimesMatchesOnlyWithoutTimes() {
        val bare = MachineSession("m1", "m1", true, agentSession("s", state = AgentState.WORKING, lastActivityMs = null, stateSinceMs = null))
        val removals = removing(bare)
        assertTrue(removals.hides(bare))
        assertFalse(removals.hides(ghost()), "times the Mac gives later are a change")
    }

    @Test fun aRemovalIsPerMacAndPerSession() {
        val removals = removing(ghost("s", machine = "m1"))
        assertFalse(removals.hides(ghost("s", machine = "m2")), "the same id on another Mac is another session")
        assertFalse(removals.hides(ghost("other", machine = "m1")))
    }

    @Test fun removingAgainKeepsTheNewStamp() {
        val removals = removing(ghost(activity = 3600.0), ghost(activity = 60.0))
        assertTrue(removals.hides(ghost(activity = 60.0)))
        assertFalse(removals.hides(ghost(activity = 3600.0)))
    }

    @Test fun theSharedFilterKeepsTheOrderAndDropsOnlyWhatIsHidden() {
        val sessions = listOf(ghost("a"), ghost("b"), ghost("c"), ghost("b", machine = "m2"))
        val removals = removing(sessions[1])
        assertEquals(listOf(sessions[0], sessions[2], sessions[3]), removals.shown(sessions))
        assertEquals(sessions, GoneRemovals.NONE.shown(sessions))
    }

    @Test fun pruningDropsRemovalsThirtyDaysOld() {
        val removals = GoneRemovals.NONE
            .remove(ghost("old"), nowMs - 30 * dayMs - 1_000)
            .remove(ghost("edge"), nowMs - 30 * dayMs)
            .remove(ghost("fresh"), nowMs - 30 * dayMs + 1_000)
        val pruned = removals.pruned(nowMs)
        assertFalse(pruned.hides(ghost("old")))
        assertFalse(pruned.hides(ghost("edge")))
        assertTrue(pruned.hides(ghost("fresh")))
        val onlyFresh = GoneRemovals.NONE.remove(ghost("fresh"), nowMs - 30 * dayMs + 1_000)
        assertEquals(onlyFresh, pruned, "a Mac with nothing left is not kept either")
    }

    @Test fun aRemovalAheadOfTheClockIsKept() {
        // The phone's clock was set back after the removal.
        val removals = removing(ghost(), atMs = nowMs + 3_600_000)
        assertTrue(removals.pruned(nowMs).hides(ghost()))
    }

    @Test fun itSurvivesEncoding() {
        val removals = GoneRemovals.NONE
            .remove(ghost("s", machine = "m1"), nowMs)
            .remove(ghost("t", machine = "m2", state = AgentState.NEEDS_INPUT, since = 90.0), nowMs - 60_000)
            .remove(ghost("u", state = AgentState("compacting")), nowMs)
        val back = GoneRemovals.CODEC.decode(GoneRemovals.CODEC.encode(removals))
        assertEquals(removals, back)
        assertTrue(back.hides(ghost("s", machine = "m1")))
        assertTrue(back.hides(ghost("t", machine = "m2", state = AgentState.NEEDS_INPUT, since = 90.0)))
        assertTrue(back.hides(ghost("u", state = AgentState("compacting"))))
    }

    // Every home group and its count

    private fun focus(
        sessions: List<MachineSession>,
        removed: GoneRemovals,
        pending: List<MachinePendingItem> = emptyList(),
        finished: Map<String, Map<String, Long>> = emptyMap(),
    ): HomeFocus = HomeFocus.make(sessions, pending, finished, removed = removed, nowMs = nowMs, zone = ZoneId.of("UTC"))

    private fun ids(items: List<FocusItem>): List<String> = items.map { it.session.session.sessionId }

    @Test fun aRemovedSessionLeavesEveryHomeGroupAndItsCount() {
        val waiting = ghost("n", state = AgentState.NEEDS_INPUT, since = 600.0, activity = 600.0)
        val running = ghost("r")
        val live = ghost("live", since = 60.0, activity = 5.0)
        val done = ghost("d", state = AgentState.IDLE, since = 300.0, activity = 300.0)
        val ended = ghost("e", state = AgentState.ENDED, since = 3600.0, activity = 3600.0)
        val sessions = listOf(waiting, running, live, done, ended)
        val finished = mapOf("m1" to mapOf("d" to nowMs - 300_000))

        val before = focus(sessions, GoneRemovals.NONE, finished = finished)
        assertEquals(listOf("n"), ids(before.needsYou))
        assertEquals(listOf("live", "r"), ids(before.running))
        assertEquals(listOf("d"), ids(before.justDone))
        assertEquals(listOf("e"), ids(before.ended))

        val after = focus(sessions, removing(waiting, running, done, ended), finished = finished)
        assertEquals(emptyList(), ids(after.needsYou))
        assertEquals(listOf("live"), ids(after.running))
        assertEquals(1, after.running.size, "\"Running · N\" counts the same list")
        assertEquals(emptyList(), ids(after.justDone))
        assertEquals(emptyList(), ids(after.ended), "the Ended fold and its page leave it out too")
    }

    @Test fun aRequestDoesNotBringARemovedSessionBackAsNeedsYou() {
        // The Mac lists a request of the removed session's workspace and agent: it goes to another session of that
        // workspace, or to none.
        val removedOne = ghost("r", workspace = "web")
        val request = MachinePendingItem("m1", "m1", pendingItem("p1", workspace = "web"), true)
        assertEquals(listOf("r"), ids(focus(listOf(removedOne), GoneRemovals.NONE, pending = listOf(request)).needsYou))
        assertTrue(focus(listOf(removedOne), removing(removedOne), pending = listOf(request)).isQuiet)

        val other = ghost("w", since = 600.0, activity = 600.0, workspace = "web")
        val shown = focus(listOf(removedOne, other), removing(removedOne), pending = listOf(request))
        assertEquals(listOf("w"), ids(shown.needsYou))
        assertEquals(emptyList(), ids(shown.running))
    }

    @Test fun aRemovedSessionShowsAgainWhenItsMacReportsAChange() {
        val removals = removing(ghost("r"))
        assertEquals(emptyList(), ids(focus(listOf(ghost("r")), removals).running))
        assertEquals(listOf("r"), ids(focus(listOf(ghost("r", activity = 30.0)), removals).running))
        assertEquals(listOf("r"), ids(focus(listOf(ghost("r", state = AgentState.NEEDS_INPUT, since = 30.0)), removals).needsYou))
    }

    @Test fun namesAreWorkedOutOverWhatIsShown() {
        val a = agentSession("a", lastActivityMs = ms(ago = 60.0), stateSinceMs = ms(ago = 60.0)).copy(title = "Fix bug")
        val b = agentSession("b", lastActivityMs = ms(ago = 120.0), stateSinceMs = ms(ago = 120.0)).copy(title = "Fix bug")
        val sessions = listOf(MachineSession("m1", "m1", true, a), MachineSession("m1", "m1", true, b))
        assertEquals(listOf("Fix bug", "Fix bug · #2"), focus(sessions, GoneRemovals.NONE).running.map { it.name })
        assertEquals(listOf("Fix bug"), focus(sessions, removing(sessions[0])).running.map { it.name })
    }

    // The store

    @Test fun theStoreStartsEmpty() {
        assertEquals(GoneRemovals.NONE, makeStore(MemoryKeyValueStore()).removals)
    }

    @Test fun aRemovalSurvivesALaunch() {
        val settings = MemoryKeyValueStore()
        val first = makeStore(settings)
        first.remove(ghost())
        assertTrue(first.removals.hides(ghost()))

        val relaunched = makeStore(settings, offsetMs = 7 * dayMs)
        assertTrue(relaunched.removals.hides(ghost()))
        assertFalse(relaunched.removals.hides(ghost("t")))
    }

    @Test fun aLaunchThirtyDaysLaterForgetsIt() {
        val settings = MemoryKeyValueStore()
        makeStore(settings).remove(ghost())
        assertTrue(makeStore(settings, offsetMs = 30 * dayMs - 1_000).removals.hides(ghost()))

        assertEquals(GoneRemovals.NONE, makeStore(settings, offsetMs = 30 * dayMs).removals)
        // Saved pruned: the removal is gone for good, not only hidden by the clock.
        assertFalse(makeStore(settings).removals.hides(ghost()))
    }

    @Test fun removingForgetsTheOldOnes() {
        val settings = MemoryKeyValueStore()
        makeStore(settings).remove(ghost("old"))
        val later = makeStore(settings, offsetMs = 30 * dayMs - 60_000)
        assertTrue(later.removals.hides(ghost("old")))
        val laterStill = makeStore(settings, offsetMs = 30 * dayMs + 60_000)
        laterStill.remove(ghost("new"))
        assertFalse(laterStill.removals.hides(ghost("old")))
        assertTrue(laterStill.removals.hides(ghost("new")))
    }

    @Test fun unreadableSavedDataStartsEmpty() {
        val settings = MemoryKeyValueStore()
        settings.putString(GoneRemovalStore.KEY, "not json")
        val store = makeStore(settings)
        assertEquals(GoneRemovals.NONE, store.removals)
        store.remove(ghost())
        assertTrue(makeStore(settings).removals.hides(ghost()))
    }

    @Test fun itKeepsItsOwnKey() {
        assertEquals("shellx.removedGone", GoneRemovalStore.KEY)
        assertNotEquals(GoneRemovalStore.KEY, EndedDismissalStore.KEY)
    }

    // Known gone this run

    @Test fun onlyASessionSeenGoneThisRunSwipesToBeRemoved() {
        val settings = MemoryKeyValueStore()
        val store = makeStore(settings)
        val gone = ghost("gone")
        val live = ghost("live", since = 60.0, activity = 5.0)
        assertFalse(store.canRemove(gone), "nothing is known gone before an agent screen hears not_found")
        assertEquals(emptySet(), store.removable(listOf(gone, live)))

        store.noteGone(gone)
        assertTrue(store.canRemove(gone))
        assertFalse(store.canRemove(live), "a live session never gets it")
        assertEquals(setOf(gone.ref), store.removable(listOf(gone, live)))
        assertFalse(store.canRemove(ghost("gone", machine = "m2")), "the same id on another Mac")
        assertFalse(store.canRemove(ghost("gone", activity = 30.0)), "the Mac reported a change since it was seen gone")

        assertFalse(makeStore(settings).canRemove(gone), "known gone is this run's only")
    }

    @Test fun removingHidesItAndKeepsWhatIsKnown() {
        val store = makeStore(MemoryKeyValueStore())
        val gone = ghost("gone")
        store.noteGone(gone)
        store.remove(gone)
        assertTrue(store.removals.hides(gone))
        assertEquals(listOf("other"), store.removals.shown(listOf(gone, ghost("other"))).map { it.session.sessionId })
    }
}
