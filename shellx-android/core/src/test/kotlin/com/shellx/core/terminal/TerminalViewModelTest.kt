package com.shellx.core.terminal

import com.shellx.core.diagnostics.LatencyMetric
import com.shellx.core.link.MachineLinkState
import com.shellx.core.testing.Gate
import com.shellx.core.testing.ManualClock
import com.shellx.core.testing.ManualSleeper
import com.shellx.core.testing.ScriptedTerminalLink
import com.shellx.core.testing.ScriptedTerminalLink.Call
import com.shellx.core.testing.deltaPart
import com.shellx.core.testing.eventually
import com.shellx.core.testing.historyPart
import com.shellx.core.testing.snapshotPart
import com.shellx.link.core.TerminalInputUnit.Text
import com.shellx.link.core.TerminalScreen
import com.shellx.link.core.TerminalViewEndReason
import com.shellx.link.core.TerminalViewOpenOutcome
import com.shellx.link.core.TerminalViewPush
import com.shellx.link.core.TerminalViewPush.Ended
import com.shellx.link.core.TerminalViewPush.Frame
import com.shellx.link.core.TerminalViewPush.Opened
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

/**
 * The terminal view model's lifecycle and frames (rules R1–R9 and the first grid of R11, plan 3G's A1–A5), against a
 * [ScriptedTerminalLink] (TerminalViewModelTests.swift).
 */
class TerminalViewModelTest {
    /** A model of Mac `m1` whose run() runs in the test's backgroundScope until the test ends, and that run's job. */
    private fun TestScope.makeModel(
        link: ScriptedTerminalLink,
        sleeper: ManualSleeper = ManualSleeper(),
        maxHistoryRows: Int = TerminalScreen.DEFAULT_MAX_HISTORY_ROWS,
        clock: ManualClock = ManualClock(),
    ): Pair<TerminalViewModel, Job> {
        val model = TerminalViewModel("m1", link, backgroundScope, maxHistoryRows, sleeper.sleep, clock.monotonic)
        val run = backgroundScope.launch { model.run() }
        return model to run
    }

    /** Shows [id] at 50 × 20 and brings it live with a first snapshot of [text]. */
    private suspend fun TestScope.live(
        model: TerminalViewModel,
        link: ScriptedTerminalLink,
        id: String = "t1",
        text: List<String> = listOf("$"),
        alt: Boolean = false,
    ) {
        model.setPhoneGrid(50, 20)
        model.show(id)
        eventually { link.opens.lastOrNull() == id }
        emit(link, Opened(id))
        emit(link, Frame(id, snapshotPart(1, cols = 50, rows = 20, text = text, alt = alt)))
        assertTrue(eventually { model.phase == TerminalViewPhase.Live }, "${model.phase} ${link.calls}")
    }

    private fun emit(link: ScriptedTerminalLink, push: TerminalViewPush) = link.emit(TerminalHubEvent.Push("m1", push))

    private fun ScriptedTerminalLink.firstScreens() = samples.filter { it.first == LatencyMetric.TERMINAL_FIRST_SCREEN }

    private val open50x20 = Call.Open("t1", 50, 20)

    @Test fun opensTheTerminalShownAtThePhoneSize() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link)
        model.show("t1")
        delay(50.milliseconds)
        assertEquals(emptyList(), link.calls, "no open before the phone's size is known")
        model.setPhoneGrid(50, 20)
        assertTrue(eventually { link.calls == listOf(open50x20) })
        assertEquals(TerminalViewPhase.Connecting, model.phase)
    } }

    @Test fun theFirstSnapshotGoesLiveAndIsMeasured() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link)
        live(model, link, text = listOf("$ ls"))
        assertEquals("$ ls", model.screen.screenText().first()); assertEquals(1, model.snapshots); assertEquals(0, model.topShift)
        assertEquals(1, link.firstScreens().size)
        assertTrue(LatencyMetric.TERMINAL_FRAME_APPLY in link.latencies)
    } }

    @Test fun framesBeforeOpenedAndOfOtherTerminalsOrMacsAreIgnored() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link)
        model.setPhoneGrid(50, 20); model.show("t1")
        eventually { link.opens == listOf("t1") }
        emit(link, Frame("t1", snapshotPart(1, text = listOf("early"))))
        emit(link, Opened("t1"))
        link.emit(TerminalHubEvent.Push("m2", Frame("t1", snapshotPart(1, text = listOf("other mac")))))
        emit(link, Frame("t2", snapshotPart(1, text = listOf("other terminal"))))
        emit(link, Frame("t1", snapshotPart(1, text = listOf("mine"))))
        assertTrue(eventually { model.phase == TerminalViewPhase.Live })
        assertEquals("mine", model.screen.screenText().first())
    } }

    @Test fun fastSwitchesNeverShowAnotherTerminalsFrames() { runTest {   // Review Focus 1
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link)
        eventually { link.subscriberCount == 1 }   // run() has started: both shows reach the Mac
        model.setPhoneGrid(50, 20); model.show("t1"); model.show("t2")
        assertTrue(eventually { link.calls == listOf(open50x20, Call.Close("t1"), Call.Open("t2", 50, 20)) }, "${link.calls}")
        emit(link, Opened("t1")); emit(link, Frame("t1", snapshotPart(1, text = listOf("one"))))
        emit(link, Opened("t2")); emit(link, Frame("t2", snapshotPart(1, text = listOf("two"))))
        emit(link, Frame("t1", deltaPart(2, replacing = mapOf(0 to "late one"))))
        eventually { model.phase == TerminalViewPhase.Live }
        delay(50.milliseconds)
        assertEquals("two", model.screen.screenText().first())
    } }

    @Test fun theLoadingStateLastsUntilTheFirstSnapshot() { runTest {   // contracts §17: the Mac may wait 500 ms for the size
        val link = ScriptedTerminalLink(); val clock = ManualClock()
        val (model, _) = makeModel(link, clock = clock)
        model.setPhoneGrid(50, 20); model.show("t1")
        eventually { link.opens == listOf("t1") }
        emit(link, Opened("t1"))
        delay(50.milliseconds)
        assertEquals(TerminalViewPhase.Connecting, model.phase, "answered and opened, but no screen yet: still loading")
        clock.advance(600.milliseconds)
        emit(link, Frame("t1", snapshotPart(1, cols = 50, rows = 20, text = listOf("$"))))
        eventually { model.phase == TerminalViewPhase.Live }
        assertEquals(600.milliseconds, link.firstScreens().first().second, "measured from the swipe, the Mac's wait included")
    } }

    @Test fun aGridWiderThanThePhoneCanAskForIsShown() { runTest {   // Review Focus 5, contracts §17
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link)
        model.setPhoneGrid(50, 20); model.show("t1")
        eventually { link.opens == listOf("t1") }
        emit(link, Opened("t1"))
        emit(link, Frame("t1", snapshotPart(1, cols = 320, rows = 130, text = listOf("x".repeat(320)))))
        assertTrue(eventually { model.phase == TerminalViewPhase.Live })
        assertEquals(320, model.screen.cols); assertEquals(130, model.screen.rows)
        assertFalse(Call.Resync("t1") in link.calls)
    } }

    @Test fun showingNothingClosesTheView() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link)
        live(model, link)
        model.show(null)
        assertTrue(eventually { link.calls.last() == Call.Close("t1") })
    } }

    @Test fun leavingTheScreenClosesTheView() { runTest {
        val link = ScriptedTerminalLink(); val (model, run) = makeModel(link)
        live(model, link)
        run.cancel()
        assertTrue(eventually { link.calls.last() == Call.Close("t1") }, "the close still goes out after run() ends")
    } }

    /** A2: a run started in the same turn as the old one is cancelled (a restarted effect) takes over. */
    @Test fun aRestartedRunKeepsTheViewOpen() { runTest {
        val link = ScriptedTerminalLink(); val (model, first) = makeModel(link)
        live(model, link)
        first.cancel()
        backgroundScope.launch { model.run() }
        advanceTimeBy(100.milliseconds)
        assertEquals(listOf<Call>(open50x20), link.calls, "a restarted run neither closes nor reopens")
    } }

    /** A1: the iPhone's background and foreground are a run that stops and a later one. */
    @Test fun stoppingTheRunClosesAndALaterRunReopens() { runTest {
        val link = ScriptedTerminalLink(); val (model, run) = makeModel(link)
        live(model, link)
        run.cancel()
        assertTrue(eventually { link.calls.last() == Call.Close("t1") })
        assertEquals("$", model.screen.screenText().first(), "the screen stays")
        backgroundScope.launch { model.run() }
        assertTrue(eventually { link.opens == listOf("t1", "t1") })
    } }

    @Test fun stoppingDuringTheOpenClosesAfterIt() { runTest {   // Review Focus 4
        val link = ScriptedTerminalLink(); val gate = Gate(); link.openGate = gate
        val (model, run) = makeModel(link)
        model.setPhoneGrid(50, 20); model.show("t1")
        eventually { link.opens == listOf("t1") }
        run.cancel(); gate.open()
        assertTrue(eventually { link.calls == listOf(open50x20, Call.Close("t1")) }, "${link.calls}")
        emit(link, Opened("t1")); emit(link, Frame("t1", snapshotPart(1, text = listOf("$"))))
        delay(50.milliseconds)
        assertNotEquals(TerminalViewPhase.Live, model.phase)
    } }

    @Test fun aGapAsksForOneResyncThenTakesTheSnapshot() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link)
        live(model, link)
        emit(link, Frame("t1", deltaPart(3, cols = 50, rows = 20, replacing = mapOf(0 to "three"))))
        emit(link, Frame("t1", deltaPart(4, cols = 50, rows = 20, replacing = mapOf(0 to "four"))))
        val asked = eventually { link.calls.count { it == Call.Resync("t1") } == 1 }
        delay(50.milliseconds)
        assertTrue(asked); assertEquals(1, link.calls.count { it == Call.Resync("t1") })
        emit(link, Frame("t1", snapshotPart(5, cols = 50, rows = 20, text = listOf("fresh"))))
        assertTrue(eventually { model.screen.screenText().first() == "fresh" })
    } }

    @Test fun macOfflineKeepsTheScreenAndReopensOnceOnline() { runTest {   // Review Focus 4
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link)
        live(model, link, text = listOf("$ ls"))
        link.online = false; link.emit(TerminalHubEvent.State("m1", MachineLinkState.Reconnecting))
        assertTrue(eventually { model.phase == TerminalViewPhase.Offline })
        assertEquals("$ ls", model.screen.screenText().first())
        assertFalse(Call.Close("t1") in link.calls, "the session is gone: nothing to close")
        link.online = true; link.emit(TerminalHubEvent.State("m1", MachineLinkState.Online))
        assertTrue(eventually { link.opens == listOf("t1", "t1") })
        emit(link, Opened("t1"))
        emit(link, Frame("t1", snapshotPart(1, cols = 50, rows = 20, text = listOf("back"))))
        assertTrue(
            eventually { model.phase == TerminalViewPhase.Live && model.screen.screenText().first() == "back" },
            "revision 1 again: a fresh assembler takes it",
        )
        assertFalse(Call.Resync("t1") in link.calls)
    } }

    @Test fun openOutcomesThatStop() { runTest {
        val link = ScriptedTerminalLink()
        link.openAnswers += listOf(outcome(TerminalViewOpenOutcome.NOT_FOUND), outcome(TerminalViewOpenOutcome.REFUSED))
        val (model, _) = makeModel(link)
        model.setPhoneGrid(50, 20); model.show("t1")
        val gone = eventually { model.phase == TerminalViewPhase.Unavailable(TerminalUnavailableReason.GONE) }
        delay(50.milliseconds)
        assertTrue(gone); assertEquals(listOf("t1"), link.opens, "a terminal that is gone is not asked for again")
        model.show("t2")
        assertTrue(eventually { model.phase == TerminalViewPhase.Unavailable(TerminalUnavailableReason.REFUSED) })
    } }

    @Test fun aFailedOpenIsRetriedOnceThenOffersTryAgain() { runTest {
        val link = ScriptedTerminalLink()
        link.openAnswers += listOf(outcome(TerminalViewOpenOutcome.FAILED), TerminalOpenResult.NoAnswer)
        val sleeper = ManualSleeper(); val (model, _) = makeModel(link, sleeper)
        model.setPhoneGrid(50, 20); model.show("t1")
        eventually { TerminalViewModel.FAILED_RETRY_DELAY in sleeper.waiting }
        sleeper.release { it == TerminalViewModel.FAILED_RETRY_DELAY }
        assertTrue(eventually {
            link.opens.size == 2 && model.phase == TerminalViewPhase.Unavailable(TerminalUnavailableReason.FAILED)
        })
        model.retry()
        assertTrue(eventually { link.opens.size == 3 })
    } }

    @Test fun busyIsRetriedFiveTimes() { runTest {
        val link = ScriptedTerminalLink(); link.openAnswers += List(6) { outcome(TerminalViewOpenOutcome.BUSY) }
        val sleeper = ManualSleeper(); val (model, _) = makeModel(link, sleeper)
        model.setPhoneGrid(50, 20); model.show("t1")
        repeat(5) {
            eventually { TerminalViewModel.BUSY_RETRY_DELAY in sleeper.waiting }
            sleeper.release { it == TerminalViewModel.BUSY_RETRY_DELAY }
        }
        assertTrue(eventually {
            link.opens.size == 6 && model.phase == TerminalViewPhase.Unavailable(TerminalUnavailableReason.FAILED)
        }, "${link.opens.size} ${model.phase}")
    } }

    @Test fun endedViews() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link)
        live(model, link)
        emit(link, Ended("t1", TerminalViewEndReason.NOT_OPEN))
        assertTrue(eventually { link.opens == listOf("t1", "t1") })
        emit(link, Opened("t1")); emit(link, Frame("t1", snapshotPart(1, text = listOf("$"))))
        eventually { model.phase == TerminalViewPhase.Live }
        emit(link, Ended("t1", TerminalViewEndReason.GONE))
        assertTrue(eventually { model.phase == TerminalViewPhase.Unavailable(TerminalUnavailableReason.GONE) })
        live(model, link, "t2")
        emit(link, Ended("t2", TerminalViewEndReason.REFUSED))
        assertTrue(eventually { model.phase == TerminalViewPhase.Unavailable(TerminalUnavailableReason.REFUSED) })
    } }

    @Test fun notOpenBeforeOpenedIsIgnored() { runTest {
        val link = ScriptedTerminalLink(); val gate = Gate(); link.openGate = gate
        val (model, _) = makeModel(link)
        model.setPhoneGrid(50, 20); model.show("t1")
        eventually { link.opens == listOf("t1") }
        emit(link, Ended("t1", TerminalViewEndReason.NOT_OPEN))
        gate.open()
        delay(100.milliseconds)
        assertEquals(listOf("t1"), link.opens)
    } }

    @Test fun aMacWithoutTerminalViewsOrOfflineOpensNothing() { runTest {
        val old = ScriptedTerminalLink(); old.supportsViews = false
        val (model, _) = makeModel(old)
        model.setPhoneGrid(50, 20); model.show("t1")
        assertTrue(eventually { model.phase == TerminalViewPhase.Unsupported })
        assertEquals(emptyList(), old.calls)
        val away = ScriptedTerminalLink(); away.online = false; away.supportsViews = false
        val (other, _) = makeModel(away)
        other.setPhoneGrid(50, 20); other.show("t1")
        assertTrue(eventually { other.phase == TerminalViewPhase.Offline }, "a Mac never seen online is not called too old")
    } }

    @Test fun topShiftFollowsRowsAddedAboveAndDroppedFromTheTop() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link, maxHistoryRows = 5)
        model.setPhoneGrid(50, 20); model.show("t1")
        eventually { link.opens == listOf("t1") }
        emit(link, Opened("t1"))
        emit(link, Frame("t1", snapshotPart(1, cols = 10, rows = 2, text = listOf("a", "b"), history = listOf("h1", "h2"))))
        eventually { model.snapshots == 1 }
        emit(link, Frame("t1", historyPart(2, cols = 10, rows = 2, lines = listOf("h-2", "h-1", "h0"))))
        assertTrue(eventually { model.topShift == 3 && model.screen.historyRows.size == 5 })
        emit(link, Frame("t1", deltaPart(3, cols = 10, rows = 2, replacing = mapOf(0 to "c", 1 to "d"), scroll = 2)))
        assertTrue(eventually { model.topShift == 1 }, "two rows dropped from the top")
        emit(link, Frame("t1", snapshotPart(4, cols = 10, rows = 2, text = listOf("e"))))
        assertTrue(eventually { model.snapshots == 2 && model.topShift == 0 })
    } }

    /** A4: close() queues the view's close, lets it go out, and the model ignores every later call. */
    @Test fun closeQueuesTheCloseAndStopsForGood() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link); live(model, link)
        model.close().join()
        assertEquals(Call.Close("t1"), link.calls.last())
        model.show("t2"); model.setPhoneGrid(40, 10); runCurrent()
        assertFalse(link.opens.contains("t2"))
    } }

    // After the iPhone's final review (plan 3G Task 10b)

    @Test fun aTimedOutOpenIsClosedOnTheMac() { runTest {   // the Mac may have opened the view although its answer never came
        val link = ScriptedTerminalLink(); link.openAnswers += TerminalOpenResult.NoAnswer
        val sleeper = ManualSleeper(); val (model, _) = makeModel(link, sleeper)
        model.setPhoneGrid(50, 20); model.show("t1")
        assertTrue(eventually { link.calls == listOf(open50x20, Call.Close("t1")) }, "${link.calls}")
        eventually { TerminalViewModel.FAILED_RETRY_DELAY in sleeper.waiting }
        assertEquals(listOf("t1"), link.opens, "the retry waits")
        sleeper.release { it == TerminalViewModel.FAILED_RETRY_DELAY }
        assertTrue(eventually { link.calls == listOf(open50x20, Call.Close("t1"), open50x20) }, "${link.calls}")
        assertEquals(TerminalViewPhase.Connecting, model.phase)
    } }

    @Test fun aNoAnswerWhileOfflineSendsNoClose() { runTest {   // the session is gone, like R8
        val link = ScriptedTerminalLink(); val gate = Gate(); link.openGate = gate; link.openAnswers += TerminalOpenResult.NoAnswer
        val (model, _) = makeModel(link)
        model.setPhoneGrid(50, 20); model.show("t1")
        eventually { link.opens == listOf("t1") }
        link.online = false; gate.open()
        val offline = eventually { model.phase == TerminalViewPhase.Offline }
        delay(50.milliseconds)
        assertTrue(offline)
        assertEquals(listOf<Call>(open50x20), link.calls, "nothing to close")
        link.online = true; link.emit(TerminalHubEvent.State("m1", MachineLinkState.Online))
        assertTrue(eventually { link.calls == listOf(open50x20, open50x20) }, "${link.calls}")
    } }

    /** A view that ends `failed` is reopened after 1 s. Meanwhile the page is reopening, not live, so nothing typed can
     *  go nowhere while it still looks live (the iPhone's final review, core M1). */
    @Test fun aFailedViewWaitsForItsReopenAsConnecting() { runTest {
        val link = ScriptedTerminalLink(); val sleeper = ManualSleeper(); val (model, _) = makeModel(link, sleeper)
        live(model, link, text = listOf("$ ls"))
        emit(link, Ended("t1", TerminalViewEndReason.FAILED))
        assertTrue(eventually { TerminalViewModel.FAILED_RETRY_DELAY in sleeper.waiting })
        assertEquals(TerminalViewPhase.Connecting, model.phase, "the reopen's wait is not live")
        assertEquals("$ ls", model.screen.screenText().first(), "the last screen stays")
        sleeper.release { it == TerminalViewModel.FAILED_RETRY_DELAY }
        assertTrue(eventually { link.opens == listOf("t1", "t1") }, "${link.calls}")
    } }

    /** The first-screen clock does not run while the Mac is offline (core M3): it starts at the open that brings the
     *  first screen. */
    @Test fun firstScreenIsNotMeasuredAcrossAnOfflinePeriod() { runTest {
        val link = ScriptedTerminalLink(); link.online = false
        val clock = ManualClock(); val (model, _) = makeModel(link, clock = clock)
        model.setPhoneGrid(50, 20); model.show("t1")
        eventually { model.phase == TerminalViewPhase.Offline }
        clock.advance(600.seconds)
        link.online = true; link.emit(TerminalHubEvent.State("m1", MachineLinkState.Online))
        eventually { link.opens == listOf("t1") }
        clock.advance(300.milliseconds)
        emit(link, Opened("t1"))
        emit(link, Frame("t1", snapshotPart(1, cols = 50, rows = 20, text = listOf("$"))))
        eventually { model.phase == TerminalViewPhase.Live }
        assertEquals(listOf(300.milliseconds), link.firstScreens().map { it.second })
    } }

    /** Nor while the page is stopped (the iPhone's background, A1) before the first screen came (core M3). */
    @Test fun firstScreenIsNotMeasuredAcrossTheBackground() { runTest {
        val link = ScriptedTerminalLink()
        val clock = ManualClock(); val (model, run) = makeModel(link, clock = clock)
        model.setPhoneGrid(50, 20); model.show("t1")
        eventually { link.opens == listOf("t1") }
        run.cancel()
        eventually { Call.Close("t1") in link.calls }
        clock.advance(600.seconds)
        backgroundScope.launch { model.run() }
        eventually { link.opens == listOf("t1", "t1") }
        clock.advance(200.milliseconds)
        emit(link, Opened("t1"))
        emit(link, Frame("t1", snapshotPart(1, cols = 50, rows = 20, text = listOf("$"))))
        eventually { model.phase == TerminalViewPhase.Live }
        assertEquals(listOf(200.milliseconds), link.firstScreens().map { it.second })
    } }

    /** An open lost with its session (no answer while the hub still says online, then the reconnect) does not use up the
     *  one retry of a failed open: the reconnect gives it back (core M4). */
    @Test fun aReconnectRestoresTheRetryBudget() { runTest {
        val link = ScriptedTerminalLink()
        link.openAnswers += listOf(TerminalOpenResult.NoAnswer, outcome(TerminalViewOpenOutcome.FAILED))
        val sleeper = ManualSleeper(); val (model, _) = makeModel(link, sleeper)
        model.setPhoneGrid(50, 20); model.show("t1")
        eventually { Call.Close("t1") in link.calls }
        link.online = false; link.emit(TerminalHubEvent.State("m1", MachineLinkState.Reconnecting))
        eventually { model.phase == TerminalViewPhase.Offline }
        link.online = true; link.emit(TerminalHubEvent.State("m1", MachineLinkState.Online))
        // A wait left from before the reconnect would hold the reopen back: let it go only if nothing reopened.
        val atOnce = eventually(timeout = 500.milliseconds) { link.opens.size == 2 }
        if (!atOnce) sleeper.release { it == TerminalViewModel.FAILED_RETRY_DELAY }
        assertTrue(eventually { link.opens.size == 2 }, "${link.calls}")
        val retried = eventually(timeout = 2.seconds) { TerminalViewModel.FAILED_RETRY_DELAY in sleeper.waiting }
        assertTrue(retried, "the first failure after the reconnect is retried: ${model.phase}")
        assertEquals(TerminalViewPhase.Connecting, model.phase)
    } }

    /** A Mac that keeps ending its views `not_open` before any screen cannot make the phone open them forever: the second
     *  one without a snapshot between ends in Try Again (core M5). */
    @Test fun repeatedNotOpenEndsInTryAgain() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link)
        live(model, link)
        emit(link, Ended("t1", TerminalViewEndReason.NOT_OPEN))
        assertTrue(eventually { link.opens == listOf("t1", "t1") })
        emit(link, Opened("t1"))
        emit(link, Ended("t1", TerminalViewEndReason.NOT_OPEN))
        val stopped = eventually(timeout = 2.seconds) {
            model.phase == TerminalViewPhase.Unavailable(TerminalUnavailableReason.FAILED)
        }
        delay(50.milliseconds)
        assertTrue(stopped, "${model.phase} ${link.opens.size} opens")
        assertEquals(listOf("t1", "t1"), link.opens)
    } }

    /** Review Focus 1, A → B → A: the late pushes of B and of A's first view never reach the screen, and keys go to the
     *  view of A that is open now (core M8). */
    @Test fun swipingBackAndForthKeepsFramesAndKeysOnTheTerminalShown() { runTest {
        val link = ScriptedTerminalLink(); val (model, _) = makeModel(link)
        eventually { link.subscriberCount == 1 }
        model.setPhoneGrid(50, 20); model.show("t1"); model.show("t2"); model.show("t1")
        assertTrue(eventually {
            link.calls == listOf(open50x20, Call.Close("t1"), Call.Open("t2", 50, 20), Call.Close("t2"), open50x20)
        }, "${link.calls}")
        emit(link, Opened("t2"))
        emit(link, Frame("t2", snapshotPart(1, cols = 50, rows = 20, text = listOf("two"))))
        emit(link, Opened("t1"))
        emit(link, Frame("t1", snapshotPart(1, cols = 50, rows = 20, text = listOf("one"))))
        assertTrue(eventually { model.phase == TerminalViewPhase.Live })
        emit(link, Frame("t2", deltaPart(2, cols = 50, rows = 20, replacing = mapOf(0 to "late two"))))
        model.insertText("x")
        assertTrue(eventually { link.calls.last() == Call.Input("t1", listOf(Text("x"))) }, "${link.calls}")
        assertEquals("one", model.screen.screenText().first())
        assertFalse(link.calls.any { it is Call.Input && it.id == "t2" })
    } }

    /**
     * Input is taken while live, or while a view reopens after a screen came (it queues behind the open, R10); not
     * before the first screen, in the wait before a failed view is reopened, after a NotSent, nor offline (the iPhone's
     * final review follow-up). A stopped page (A1) keeps the keyboard as it was.
     */
    @Test fun acceptsInputWhileLiveOrReopeningAView() { runTest {
        val link = ScriptedTerminalLink(); val sleeper = ManualSleeper(); val (model, run) = makeModel(link, sleeper)
        model.setPhoneGrid(50, 20); model.show("t1")
        eventually { link.opens == listOf("t1") }
        assertFalse(model.acceptsInput, "before the first screen the loading card covers the page")
        emit(link, Opened("t1"))
        emit(link, Frame("t1", snapshotPart(1, cols = 50, rows = 20, text = listOf("$"))))
        eventually { model.phase == TerminalViewPhase.Live }
        assertTrue(model.acceptsInput); assertTrue(model.state.value.acceptsInput)

        run.cancel()
        eventually { link.calls.last() == Call.Close("t1") }
        assertTrue(model.acceptsInput, "a stopped page keeps the keyboard as it was")
        val gate = Gate(); link.openGate = gate
        backgroundScope.launch { model.run() }
        eventually { link.opens.size == 2 }
        assertEquals(TerminalViewPhase.Connecting, model.phase)
        assertTrue(model.acceptsInput, "a view is opening: input queues behind it")
        model.insertText("x")
        gate.open()
        assertTrue(eventually { link.calls.last() == Call.Input("t1", listOf(Text("x"))) }, "${link.calls}")
        emit(link, Opened("t1"))
        emit(link, Frame("t1", snapshotPart(1, cols = 50, rows = 20, text = listOf("$"))))
        eventually { model.phase == TerminalViewPhase.Live }

        emit(link, Ended("t1", TerminalViewEndReason.FAILED))
        eventually { TerminalViewModel.FAILED_RETRY_DELAY in sleeper.waiting }
        assertEquals(TerminalViewPhase.Connecting, model.phase)
        assertFalse(model.acceptsInput, "the retry wait has no view"); assertFalse(model.state.value.acceptsInput)
        link.online = false; link.emit(TerminalHubEvent.State("m1", MachineLinkState.Reconnecting))
        eventually { model.phase == TerminalViewPhase.Offline }
        assertFalse(model.acceptsInput)

        link.openAnswers += TerminalOpenResult.NotSent
        link.online = true; link.emit(TerminalHubEvent.State("m1", MachineLinkState.Online))
        eventually { link.opens.size == 3 }
        delay(50.milliseconds)
        assertEquals(TerminalViewPhase.Connecting, model.phase, "the hub still calls the Mac online")
        assertFalse(model.acceptsInput, "after a NotSent there is no view to type into")
    } }

    // Review C (fix round 1)

    /** A scope whose coroutines run inline, as on the app's `Main.immediate`: the outbox delivers inside send(). */
    private fun TestScope.immediate() = CoroutineScope(backgroundScope.coroutineContext + UnconfinedTestDispatcher(testScheduler))

    /** Review C I-1: an open the link answers inside its own send keeps its outcome; reconcile() writes nothing after. */
    @Test fun anOpenAnsweredInsideItsSendKeepsItsOutcome() { runTest {
        val link = ScriptedTerminalLink(); link.openAnswers += outcome(TerminalViewOpenOutcome.NOT_FOUND)
        val model = TerminalViewModel("m1", link, immediate(), sleep = ManualSleeper().sleep, now = ManualClock().monotonic)
        backgroundScope.launch { model.run() }
        eventually { link.subscriberCount == 1 }
        model.setPhoneGrid(50, 20); model.show("t1")
        assertEquals(TerminalViewPhase.Unavailable(TerminalUnavailableReason.GONE), model.phase)
        delay(50.milliseconds)
        assertEquals(TerminalViewPhase.Unavailable(TerminalUnavailableReason.GONE), model.phase)
        assertEquals(listOf("t1"), link.opens)
    } }

    /** Review C I-1: a first screen that arrives inside the open's send stays live, and is measured once. */
    @Test fun aScreenShownInsideTheOpensSendStaysLive() { runTest {
        val link = ScriptedTerminalLink(); val clock = ManualClock(); val scope = immediate()
        link.onOpen = { id ->
            emit(link, Opened(id))
            emit(link, Frame(id, snapshotPart(1, cols = 50, rows = 20, text = listOf("$"))))
        }
        val model = TerminalViewModel("m1", link, scope, sleep = ManualSleeper().sleep, now = clock.monotonic)
        scope.launch { model.run() }
        eventually { link.subscriberCount == 1 }
        model.setPhoneGrid(50, 20); model.show("t1")
        assertEquals(TerminalViewPhase.Live, model.phase); assertEquals(1, model.snapshots)
        link.onOpen = null
        clock.advance(1.seconds)
        emit(link, Frame("t1", snapshotPart(2, cols = 50, rows = 20, text = listOf("$ ls"))))
        assertTrue(eventually { model.snapshots == 2 })
        assertEquals(TerminalViewPhase.Live, model.phase)
        assertEquals(1, link.firstScreens().size, "measured once, at the first snapshot")
    } }

    /** Review C m2: a run ends quietly only when a newer run or close() stopped its collection. */
    @Test fun onlyANewerRunOrCloseEndsARunQuietly() { runTest {
        val link = ScriptedTerminalLink()
        val model = TerminalViewModel("m1", link, backgroundScope, sleep = ManualSleeper().sleep, now = ManualClock().monotonic)
        val first = async { runCatching { model.run() } }
        eventually { link.subscriberCount == 1 }
        val second = async { runCatching { model.run() } }
        assertTrue(first.await().isSuccess, "a newer run takes over quietly")
        model.close().join()
        assertTrue(second.await().isSuccess, "close() ends the run quietly")

        val failing = ScriptedTerminalLink(); failing.eventsFailure = CancellationException("the events were cancelled")
        val other = TerminalViewModel("m1", failing, backgroundScope, sleep = ManualSleeper().sleep, now = ManualClock().monotonic)
        val ended = runCatching { other.run() }.exceptionOrNull()
        assertIs<CancellationException>(ended, "a cancellation no newer run or close() made is the caller's to see")
    } }

    private fun outcome(outcome: TerminalViewOpenOutcome) = TerminalOpenResult.Outcome(outcome)
}
