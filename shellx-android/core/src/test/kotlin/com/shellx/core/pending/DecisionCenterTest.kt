package com.shellx.core.pending

import com.shellx.core.demo.FakeMac
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.diagnostics.LatencyMetric
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.PendingKey
import com.shellx.core.testing.Gate
import com.shellx.core.testing.ManualClock
import com.shellx.core.testing.ManualSleeper
import com.shellx.core.testing.ScriptedSender
import com.shellx.core.testing.ScriptedSender.Answer
import com.shellx.core.testing.eventually
import com.shellx.core.testing.pendingRig
import com.shellx.core.testing.permissionItem
import com.shellx.core.testing.planItem
import com.shellx.core.text.utf8Size
import com.shellx.link.core.ExitPlanMode
import com.shellx.link.core.LinkClientException
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.PermissionMode
import com.shellx.link.core.ReplyOutcome
import java.io.IOException
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

/**
 * Sending a decision from a card: what the card shows meanwhile and after, against a real hub and FakeMac (A1: a
 * handled item disappears; a tap that cannot be sent says so).
 */
class DecisionCenterTest {
    private val once = LinkDecision.Permission(PermissionMode.ONCE)

    @Test fun deliveredHidesCardBeforeResolvedArrives() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(permissionItem("r1"))
        mac.addPending(permissionItem("r2"))
        // The Mac answers `delivered` but its `agent.changed` comes later.
        mac.setReplyOutcome(ReplyOutcome.DELIVERED, resolves = false)
        val rig = pendingRig(listOf(mac))
        assertTrue(rig.synced(2))
        val key = rig.key(mac, "r1")

        rig.center.send(once, key)

        assertEquals(DecisionStatus.Done, rig.center.status[key])
        assertEquals(listOf("r1", "r2"), rig.hub.pendingItems.map { it.item.requestId }, "the Mac has not resolved it yet")
        assertEquals(listOf("r2"), rig.visibleIds, "the card goes at once")
        assertEquals(listOf(FakeMac.Decision("r1", once)), mac.decisions)
        assertEquals(1, rig.latency.summary(LatencyMetric.REPLY_ROUND_TRIP)?.count, "tap to delivered is measured once")

        mac.resolvePending("r1")
        assertTrue(eventually { rig.hub.pendingItems.size == 1 })
        assertEquals(listOf("r2"), rig.visibleIds)
        assertNull(rig.center.status[key])
    } }

    @Test fun alreadyHandledShowsThenHides() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(permissionItem("r1"))
        mac.setReplyOutcome(ReplyOutcome.ALREADY_HANDLED)
        val rig = pendingRig(listOf(mac))
        assertTrue(rig.synced(1))
        val key = rig.key(mac, "r1")

        rig.center.send(once, key)

        assertEquals(DecisionStatus.HandledElsewhere, rig.center.status[key])
        assertEquals(listOf("r1"), rig.visibleIds, "the card stays to say so")
        assertTrue(eventually { rig.linger.waiting == listOf(DecisionCenter.HANDLED_ELSEWHERE_LINGER) }, "${rig.linger.waiting}")
        assertEquals(2.seconds, DecisionCenter.HANDLED_ELSEWHERE_LINGER)
        assertEquals(listOf("r1"), rig.visibleIds, "still there while the linger runs")
        assertNull(rig.latency.summary(LatencyMetric.REPLY_ROUND_TRIP), "nothing reached the agent")

        rig.center.send(LinkDecision.Permission(PermissionMode.DENY), key)
        assertEquals(1, mac.decisions.size, "a handled item takes no other decision")

        rig.linger.release()
        assertTrue(eventually { rig.visibleIds.isEmpty() })
    } }

    @Test fun handledElsewhereLingersAfterItemLeaves() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(permissionItem("r1"))
        val rig = pendingRig(listOf(mac))
        assertTrue(rig.synced(1))
        assertEquals(listOf("r1"), rig.visibleIds, "the card is on screen")
        val key = rig.key(mac, "r1")
        // Decided on the Mac before the tap arrives: the item leaves while the reply is on its way.
        mac.resolvePending("r1")
        assertTrue(eventually { rig.hub.pendingItems.isEmpty() })

        rig.center.send(once, key)

        assertEquals(DecisionStatus.HandledElsewhere, rig.center.status[key])
        val shown = rig.shown
        assertEquals(listOf("r1"), shown.map { it.item.requestId }, "the card says it was handled elsewhere")
        assertEquals(listOf(false), shown.map { it.actionable })
        assertTrue(eventually { rig.linger.waiting.size == 1 })
        rig.linger.release()
        assertTrue(eventually { rig.visibleIds.isEmpty() })
        assertNull(rig.center.status[key])
    } }

    @Test fun unknownKeepsCardWithRejected() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(permissionItem("r1"))
        mac.setReplyOutcome(ReplyOutcome.UNKNOWN)
        val rig = pendingRig(listOf(mac))
        assertTrue(rig.synced(1))
        val key = rig.key(mac, "r1")

        rig.center.send(LinkDecision.Permission(PermissionMode.ALWAYS), key)

        assertEquals(DecisionStatus.Failed(DecisionFailure.REJECTED), rig.center.status[key])
        assertEquals(listOf("r1"), rig.visibleIds)

        // A host error answering the call reads the same.
        val sender = ScriptedSender(listOf(Answer.Failure(LinkClientException.Remote("bad_request", "no"))))
        val center = DecisionCenter(sender, LatencyLog(), backgroundScope, ManualClock(), rig.linger.sleep)
        center.send(once, key)
        assertEquals(DecisionStatus.Failed(DecisionFailure.REJECTED), center.status[key])
        val other = ScriptedSender(listOf(Answer.Outcome(ReplyOutcome("later"))))
        val center2 = DecisionCenter(other, LatencyLog(), backgroundScope, ManualClock(), rig.linger.sleep)
        center2.send(once, key)
        assertEquals(DecisionStatus.Failed(DecisionFailure.REJECTED), center2.status[key])
    } }

    @Test fun timeoutResendsOnceThenFails() { runTest {
        val key = PendingKey("m1", "r1")
        val sender = ScriptedSender(listOf(Answer.Failure(LinkClientException.TimedOut())))
        val latency = LatencyLog()
        val center = DecisionCenter(sender, latency, backgroundScope, ManualClock(), ManualSleeper().sleep)

        center.send(once, key)

        assertEquals(2, sender.calls.size, "one resend, which is safe: replies are idempotent")
        assertEquals(listOf<LinkDecision>(once, once), sender.calls.map { it.second })
        assertEquals(DecisionStatus.Failed(DecisionFailure.NO_ANSWER), center.status[key])

        // "Try again" sends the same decision again.
        center.retry(key)
        assertEquals(4, sender.calls.size)

        val second = PendingKey("m1", "r2")
        val flaky = ScriptedSender(listOf(Answer.Failure(LinkClientException.TimedOut()), Answer.Outcome(ReplyOutcome.DELIVERED)))
        val center2 = DecisionCenter(flaky, latency, backgroundScope, ManualClock(), ManualSleeper().sleep)
        center2.send(LinkDecision.Permission(PermissionMode.DENY), second)
        assertEquals(2, flaky.calls.size)
        assertEquals(DecisionStatus.Done, center2.status[second])
        assertEquals(1, latency.summary(LatencyMetric.REPLY_ROUND_TRIP)?.count, "the round trip spans both tries")
    } }

    @Test fun secondTapWhileSendingIgnored() { runTest {
        val key = PendingKey("m1", "r1")
        val gate = Gate()
        val sender = ScriptedSender(listOf(Answer.Outcome(ReplyOutcome.DELIVERED)))
        sender.gate = gate
        val center = DecisionCenter(sender, LatencyLog(), backgroundScope, ManualClock(), ManualSleeper().sleep)

        val first = launch { center.send(once, key) }
        assertTrue(eventually { gate.waiting == 1 })
        assertEquals(DecisionStatus.Sending, center.status[key])

        center.send(LinkDecision.Permission(PermissionMode.DENY), key)
        center.retry(key)
        assertEquals(1, sender.calls.size, "taps while sending do nothing")
        assertEquals(DecisionStatus.Sending, center.status[key])

        gate.open()
        first.join()
        assertEquals(DecisionStatus.Done, center.status[key])
        center.send(LinkDecision.Permission(PermissionMode.DENY), key)
        assertEquals(1, sender.calls.size, "nor taps after it was delivered")
    } }

    @Test fun offlineFailsWithoutResend() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(permissionItem("r1"))
        val rig = pendingRig(listOf(mac))
        assertTrue(rig.synced(1))
        val key = rig.key(mac, "r1")
        // The network goes: the session drops and the next attempt fails, so the Mac is offline.
        mac.failNextConnects(IOException("offline"), 1)
        mac.dropLiveSessions()
        assertTrue(eventually { rig.backoff.waiting.size == 1 }, "${rig.hub.machines.map { it.state }}")
        rig.backoff.release()
        assertTrue(
            eventually { rig.hub.machines.firstOrNull()?.state is MachineLinkState.Offline && rig.backoff.waiting.size == 1 },
            "${rig.hub.machines.map { it.state }}",
        )

        rig.center.send(once, key)

        assertEquals(DecisionStatus.Failed(DecisionFailure.OFFLINE), rig.center.status[key])
        // Back online: nothing was queued, so nothing goes out by itself (spec section 7.5).
        rig.backoff.release()
        assertTrue(rig.synced(1))
        assertEquals(emptyList(), mac.decisions)
        assertEquals(DecisionStatus.Failed(DecisionFailure.OFFLINE), rig.center.status[key])
        // The card is back with live buttons: "offline, not sent" no longer holds.
        rig.center.sync(rig.hub.pendingItems)
        assertNull(rig.center.status[key])
        assertEquals(emptyList(), mac.decisions, "clearing the message sends nothing")

        // A session that ends while the reply is out reads the same, and is not resent.
        val sender = ScriptedSender(listOf(Answer.Failure(LinkClientException.SessionClosed())))
        val center = DecisionCenter(sender, LatencyLog(), backgroundScope, ManualClock(), rig.linger.sleep)
        center.send(once, key)
        assertEquals(DecisionStatus.Failed(DecisionFailure.OFFLINE), center.status[key])
        assertEquals(1, sender.calls.size)
    } }

    @Test fun tapWhileReconnectingFailsVisibly() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(permissionItem("r1"))
        val rig = pendingRig(listOf(mac))
        assertTrue(rig.synced(1))
        assertEquals(listOf(true), rig.shown.map { it.actionable })
        val key = rig.key(mac, "r1")
        // The session drops; the next one connects but has not synced yet.
        mac.holdSnapshots()
        mac.dropLiveSessions()
        assertTrue(eventually { rig.backoff.waiting.size == 1 }, "${rig.hub.machines.map { it.state }}")
        // The hub applies the not-actionable event on its own reader, which may run after the connection registered
        // its backoff wait.
        assertTrue(eventually { rig.shown.map { it.actionable } == listOf(false) }, "${rig.shown.map { it.actionable }}")
        rig.backoff.release()
        assertTrue(
            eventually { mac.heldSnapshotCount == 1 && rig.hub.pendingItems.map { it.actionable } == listOf(false) },
            "${rig.hub.machines.map { it.state }}",
        )
        assertEquals(listOf(false), rig.shown.map { it.actionable }, "buttons off")

        // A tap that got through anyway (it raced the redraw) fails where the user can see it.
        rig.center.send(once, key)

        assertEquals(DecisionStatus.Failed(DecisionFailure.OFFLINE), rig.center.status[key])
        assertEquals(emptyList(), mac.decisions, "nothing was sent for unsynced data")

        rig.center.sync(rig.hub.pendingItems)
        assertEquals(
            DecisionStatus.Failed(DecisionFailure.OFFLINE), rig.center.status[key],
            "still not live: the card keeps saying so",
        )

        mac.releaseSnapshots()
        assertTrue(rig.synced(1))
        assertEquals(listOf(true), rig.shown.map { it.actionable })
        assertNull(rig.center.status[key], "live again: the offline note goes, the buttons are back")
        assertEquals(emptyList(), mac.decisions, "and nothing goes out once it syncs")
    } }

    @Test fun visibleItemsOnlyReads() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(permissionItem("r1"))
        mac.setReplyOutcome(ReplyOutcome.UNKNOWN)
        val rig = pendingRig(listOf(mac))
        assertTrue(rig.synced(1))
        val key = rig.key(mac, "r1")
        rig.center.send(once, key)
        mac.resolvePending("r1")
        assertTrue(eventually { rig.hub.pendingItems.isEmpty() })

        // A screen may call it any number of times, with any subset: nothing changes.
        assertEquals(emptyList(), rig.center.visibleItems(emptyList()))
        assertEquals(DecisionStatus.Failed(DecisionFailure.REJECTED), rig.center.status[key])

        rig.center.sync(rig.hub.pendingItems)
        assertNull(rig.center.status[key], "sync forgets what left the set")
    } }

    @Test fun resolvedItemClearsStatus() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(permissionItem("r1"))
        mac.addPending(permissionItem("r2"))
        mac.setReplyOutcome(ReplyOutcome.UNKNOWN)
        val rig = pendingRig(listOf(mac))
        assertTrue(rig.synced(2))
        val key = rig.key(mac, "r1")
        rig.center.send(once, key)
        assertEquals(DecisionStatus.Failed(DecisionFailure.REJECTED), rig.center.status[key])

        mac.resolvePending("r1")
        assertTrue(eventually { rig.hub.pendingItems.size == 1 })

        assertEquals(listOf("r2"), rig.visibleIds)
        assertNull(rig.center.status[key], "a resolved item's status is forgotten")
        assertTrue(rig.center.status.isEmpty())
    } }

    @Test fun feedbackOver4096BytesRefused() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(planItem("p1"))
        mac.addPending(planItem("p2"))
        val rig = pendingRig(listOf(mac))
        assertTrue(rig.synced(2))
        assertEquals(4096, DecisionCenter.MAX_FEEDBACK_BYTES)
        // "ệ" is 3 bytes: 1366 of them are 4098 bytes.
        val tooLong = "ệ".repeat(1366)

        rig.center.send(LinkDecision.ExitPlan(ExitPlanMode.DENY, tooLong), rig.key(mac, "p1"))

        assertNull(rig.center.status[rig.key(mac, "p1")], "refused before anything is sent")
        assertEquals(emptyList(), mac.decisions)

        val fits = "ệ".repeat(1365) + "a"
        assertEquals(4096, fits.utf8Size)
        rig.center.send(LinkDecision.ExitPlan(ExitPlanMode.DENY, fits), rig.key(mac, "p2"))
        assertEquals(DecisionStatus.Done, rig.center.status[rig.key(mac, "p2")])
        assertEquals(listOf("p2"), mac.decisions.map { it.requestId })
    } }

    // Android (Review Focus 1, review 1 M-3)

    /** The card's screen went away while the reply was out: the decision still gets its final status. */
    @Test fun aCancelledCallerStillGetsItsStatus() { runTest {
        val sender = ScriptedSender(listOf(Answer.Outcome(ReplyOutcome.DELIVERED))).also { it.gate = Gate() }
        val center = DecisionCenter(sender, LatencyLog(), backgroundScope, ManualClock(), ManualSleeper().sleep)
        val key = PendingKey("m1", "r1")
        center.sync(listOf(MachinePendingItem("m1", "Mac", permissionItem("r1"), true)))
        val caller = launch { center.send(LinkDecision.Permission(PermissionMode.ONCE), key) }
        runCurrent()
        assertEquals(DecisionStatus.Sending, center.status[key])
        // The gate holds the reply whatever happens, so a caller stuck behind it would hang a cancelAndJoin: look
        // whether the wait ended, then open the gate.
        caller.cancel()
        runCurrent()
        val released = caller.isCompleted
        sender.gate!!.open()
        caller.join()
        runCurrent()
        assertTrue(released, "the caller's wait ends at once")
        assertEquals(DecisionStatus.Done, center.status[key])
    } }

    /** A reply that throws a CancellationException of its own (nobody cancelled) is a failure, not a card that says
     *  "sending" forever. */
    @Test fun aReplyThatCancelsItselfFails() { runTest {
        val sender = ScriptedSender(listOf(Answer.Failure(CancellationException("own"))))
        val center = DecisionCenter(sender, LatencyLog(), backgroundScope, ManualClock(), ManualSleeper().sleep)
        val key = PendingKey("m1", "r1")

        center.send(once, key)

        assertEquals(DecisionStatus.Failed(DecisionFailure.NO_ANSWER), center.status[key])
    } }
}
