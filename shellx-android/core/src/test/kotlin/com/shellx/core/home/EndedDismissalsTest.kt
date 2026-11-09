package com.shellx.core.home

import com.shellx.core.link.MachineSession
import com.shellx.core.platform.Clock
import com.shellx.core.platform.MemoryKeyValueStore
import com.shellx.core.testing.ManualClock
import com.shellx.core.testing.agentSession
import com.shellx.link.core.AgentState
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** The ended sessions the user took off the phone's Ended list, and how that survives a launch. */
class EndedDismissalsTest {
    private val nowMs = 1_800_000_000_000L

    private fun ms(ago: Double): Long = nowMs - (ago * 1000).toLong()

    private fun ended(id: String, machine: String = "m1", ago: Double = 600.0) =
        MachineSession(machine, machine, true, agentSession(id, state = AgentState.ENDED, stateSinceMs = ms(ago = ago)))

    /** A store over [settings] whose clock stands [offset] seconds after now. */
    private fun makeStore(settings: MemoryKeyValueStore, offset: Double = 0.0): EndedDismissalStore =
        EndedDismissalStore(settings, clockAt(offset))

    private fun clockAt(offset: Double): Clock = ManualClock(nowMs + (offset * 1000).toLong())

    // The value

    @Test fun nothingIsHiddenUntilItIsDismissed() {
        assertFalse(EndedDismissals.NONE.hides(ended("s")))
        val dismissals = EndedDismissals.NONE.dismiss(ended("s"))
        assertTrue(dismissals.hides(ended("s")))
    }

    @Test fun aDismissalIsPerMacAndPerSession() {
        val dismissals = EndedDismissals.NONE.dismiss(ended("s", machine = "m1"))
        assertFalse(dismissals.hides(ended("s", machine = "m2")), "the same id on another Mac is another session")
        assertFalse(dismissals.hides(ended("other", machine = "m1")))
    }

    @Test fun aSessionThatEndsAgainLaterShowsAgain() {
        val dismissals = EndedDismissals.NONE.dismiss(ended("s", ago = 3600.0))
        assertTrue(dismissals.hides(ended("s", ago = 3600.0)))
        assertFalse(dismissals.hides(ended("s", ago = 60.0)), "a newer end is a new ending")
    }

    @Test fun anEarlierEndStaysHidden() {
        val dismissals = EndedDismissals.NONE.dismiss(ended("s", ago = 60.0))
        assertTrue(dismissals.hides(ended("s", ago = 3600.0)))
    }

    @Test fun dismissingTwiceKeepsTheNewerEnd() {
        val dismissals = EndedDismissals.NONE.dismiss(ended("s", ago = 60.0)).dismiss(ended("s", ago = 3600.0))
        assertTrue(dismissals.hides(ended("s", ago = 60.0)))
    }

    @Test fun aSessionWithoutAnEndTimeIsNotRemembered() {
        val session = MachineSession(
            "m1", "m1", true, agentSession("s", state = AgentState.ENDED, lastActivityMs = null, stateSinceMs = null),
        )
        assertEquals(EndedDismissals.NONE, EndedDismissals.NONE.dismiss(session))
    }

    @Test fun pruningDropsWhatTheTwelveHoursWouldHaveDropped() {
        val dismissals = EndedDismissals.NONE
            .dismiss(ended("old", ago = 43_201.0))
            .dismiss(ended("edge", ago = 43_200.0))
            .dismiss(ended("fresh", ago = 43_199.0))
        val pruned = dismissals.pruned(nowMs)
        assertFalse(pruned.hides(ended("old", ago = 43_201.0)))
        assertFalse(pruned.hides(ended("edge", ago = 43_200.0)))
        assertTrue(pruned.hides(ended("fresh", ago = 43_199.0)))
        val onlyFresh = EndedDismissals.NONE.dismiss(ended("fresh", ago = 43_199.0))
        assertEquals(onlyFresh, pruned, "a Mac with nothing left is not kept either")
    }

    @Test fun anEndAheadOfTheClockIsKept() {
        val dismissals = EndedDismissals.NONE.dismiss(ended("s", ago = -300.0))
        assertTrue(dismissals.pruned(nowMs).hides(ended("s", ago = -300.0)))
    }

    @Test fun itSurvivesEncoding() {
        val dismissals = EndedDismissals.NONE.dismiss(ended("s", machine = "m1")).dismiss(ended("t", machine = "m2", ago = 90.0))
        val back = EndedDismissals.CODEC.decode(EndedDismissals.CODEC.encode(dismissals))
        assertEquals(dismissals, back)
        assertTrue(back.hides(ended("s", machine = "m1")))
        assertTrue(back.hides(ended("t", machine = "m2", ago = 90.0)))
    }

    // The Ended list and the home's fold

    private fun focus(sessions: List<MachineSession>, dismissed: EndedDismissals): HomeFocus =
        HomeFocus.make(sessions, emptyList(), emptyMap(), dismissed = dismissed, nowMs = nowMs, zone = ZoneId.of("UTC"))

    @Test fun aDismissedSessionLeavesTheEndedList() {
        val sessions = listOf(ended("a", ago = 60.0), ended("b", ago = 120.0), ended("c", ago = 180.0))
        val dismissals = EndedDismissals.NONE.dismiss(sessions[1])
        assertEquals(listOf("a", "b", "c"), focus(sessions, EndedDismissals.NONE).ended.map { it.session.session.sessionId })
        val shown = focus(sessions, dismissals).ended
        assertEquals(listOf("a", "c"), shown.map { it.session.session.sessionId })
        assertEquals(2, shown.size, "the home's Ended fold counts the same list")
    }

    @Test fun dismissingEveryEndedSessionEmptiesTheFold() {
        val sessions = listOf(ended("a"), ended("b", machine = "m2"))
        var dismissals = EndedDismissals.NONE
        sessions.forEach { dismissals = dismissals.dismiss(it) }
        assertTrue(focus(sessions, dismissals).ended.isEmpty())
    }

    @Test fun aDismissedSessionThatResumedShowsInItsGroup() {
        val dismissals = EndedDismissals.NONE.dismiss(ended("s", ago = 3600.0))
        val resumed = MachineSession("m1", "m1", true, agentSession("s", state = AgentState.WORKING, stateSinceMs = ms(ago = 30.0)))
        val result = focus(listOf(resumed), dismissals)
        assertEquals(listOf("s"), result.running.map { it.session.session.sessionId })
        assertTrue(result.ended.isEmpty())
    }

    @Test fun aDismissedSessionThatEndedAgainShowsAgain() {
        val dismissals = EndedDismissals.NONE.dismiss(ended("s", ago = 7200.0))
        assertEquals(0, focus(listOf(ended("s", ago = 7200.0)), dismissals).ended.size)
        assertEquals(listOf("s"), focus(listOf(ended("s", ago = 120.0)), dismissals).ended.map { it.session.session.sessionId })
    }

    @Test fun namesAreWorkedOutOverWhatIsShown() {
        val a = agentSession("a", state = AgentState.ENDED, stateSinceMs = ms(ago = 60.0)).copy(title = "Fix bug")
        val b = agentSession("b", state = AgentState.ENDED, stateSinceMs = ms(ago = 120.0)).copy(title = "Fix bug")
        val sessions = listOf(MachineSession("m1", "m1", true, a), MachineSession("m1", "m1", true, b))
        val dismissals = EndedDismissals.NONE.dismiss(sessions[0])
        assertEquals(listOf("Fix bug", "Fix bug · #2"), focus(sessions, EndedDismissals.NONE).ended.map { it.name })
        assertEquals(listOf("Fix bug"), focus(sessions, dismissals).ended.map { it.name })
    }

    // The store

    @Test fun theStoreStartsEmpty() {
        assertEquals(EndedDismissals.NONE, makeStore(MemoryKeyValueStore()).dismissals.value)
    }

    @Test fun aDismissalSurvivesALaunch() {
        val settings = MemoryKeyValueStore()
        val first = makeStore(settings)
        first.dismiss(ended("s"))
        assertTrue(first.dismissals.value.hides(ended("s")))

        val relaunched = makeStore(settings, offset = 3600.0)
        assertTrue(relaunched.dismissals.value.hides(ended("s")))
        assertFalse(relaunched.dismissals.value.hides(ended("t")))
    }

    @Test fun aLaunchAfterTheTwelveHoursForgetsIt() {
        val settings = MemoryKeyValueStore()
        makeStore(settings).dismiss(ended("s", ago = 600.0))
        assertTrue(makeStore(settings, offset = 43_199.0 - 600).dismissals.value.hides(ended("s", ago = 600.0)))

        val later = makeStore(settings, offset = 43_200.0)
        assertEquals(EndedDismissals.NONE, later.dismissals.value)
        // Saved pruned: the entry is gone for good, not only hidden by the clock.
        val earlier = makeStore(settings)
        assertFalse(earlier.dismissals.value.hides(ended("s", ago = 600.0)))
    }

    @Test fun dismissingForgetsTheOldOnes() {
        val settings = MemoryKeyValueStore()
        val store = makeStore(settings)
        store.dismiss(ended("old", ago = 43_000.0))
        val hour = makeStore(settings, offset = 1800.0)
        hour.dismiss(ended("new", ago = 60.0))
        assertFalse(hour.dismissals.value.hides(ended("old", ago = 43_000.0)))
        assertTrue(hour.dismissals.value.hides(ended("new", ago = 60.0)))
    }

    @Test fun unreadableSavedDataStartsEmpty() {
        val settings = MemoryKeyValueStore()
        settings.putString(EndedDismissalStore.KEY, "not json")
        val store = makeStore(settings)
        assertEquals(EndedDismissals.NONE, store.dismissals.value)
        store.dismiss(ended("s"))
        assertTrue(makeStore(settings).dismissals.value.hides(ended("s")))
    }
}
