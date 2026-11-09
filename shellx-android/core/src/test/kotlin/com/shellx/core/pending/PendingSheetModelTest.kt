package com.shellx.core.pending

import com.shellx.core.demo.FakeMac
import com.shellx.core.link.MachineLinkState
import com.shellx.core.testing.PendingRig
import com.shellx.core.testing.eventually
import com.shellx.core.testing.pendingRig
import com.shellx.core.testing.planItem
import com.shellx.core.testing.questionItem
import com.shellx.link.account.RelayApiException
import com.shellx.link.core.LinkDecision
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest

/** The question and plan sheets stay open while the user reads: the item may be decided elsewhere meanwhile. */
class PendingSheetModelTest {
    @Test fun sheetReportsHandledElsewhereWhenItemResolved() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(questionItem("q1"))
        val rig = pendingRig(listOf(mac))
        assertTrue(rig.synced(1))
        val sheet = PendingSheetModel(rig.key(mac, "q1"), rig.hub, rig.center)
        assertEquals("q1", sheet.opened?.item?.requestId)
        assertTrue(sheet.canSend)
        assertFalse(sheet.handledElsewhere)

        // Answered on the Mac while the sheet is open.
        mac.resolvePending("q1")
        val flagged = eventually { sheet.handledElsewhere }

        assertTrue(flagged)
        assertFalse(sheet.canSend)
        assertEquals("q1", sheet.opened?.item?.requestId, "the sheet keeps showing what was asked")
        sheet.send(LinkDecision.Question(listOf("Postgres")))
        assertEquals(emptyList(), mac.decisions, "the sheet sends nothing")
    } }

    @Test fun sheetNotFlaggedAfterOwnSend() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(questionItem("q1"))
        val rig = pendingRig(listOf(mac))
        assertTrue(rig.synced(1))
        val key = rig.key(mac, "q1")
        val sheet = PendingSheetModel(key, rig.hub, rig.center)

        sheet.send(LinkDecision.Question(listOf("Free text answer")))

        assertEquals(DecisionStatus.Done, sheet.status)
        assertEquals(listOf(FakeMac.Decision("q1", LinkDecision.Question(listOf("Free text answer")))), mac.decisions)
        assertTrue(eventually { rig.hub.pendingItems.isEmpty() }, "the Mac resolved it")
        rig.center.sync(rig.hub.pendingItems)
        assertNull(rig.center.status[key], "the center forgot it")
        assertFalse(sheet.handledElsewhere, "our own answer is not someone else's")
        assertEquals(DecisionStatus.Done, sheet.status)
        assertFalse(sheet.canSend)
    } }

    @Test fun sheetWaitsWhileReconnecting() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(planItem("p1"))
        val rig = pendingRig(listOf(mac))
        assertTrue(rig.synced(1))
        val sheet = PendingSheetModel(rig.key(mac, "p1"), rig.hub, rig.center)
        assertTrue(sheet.actionable)

        mac.dropLiveSessions()
        val waiting = eventually { !sheet.actionable }

        assertTrue(waiting)
        assertFalse(sheet.canSend)
        assertFalse(sheet.handledElsewhere, "still pending, just not synced")
    } }

    // The Mac goes away while the sheet is open

    /** Ends the Mac's session and lets the first reconnect fail: the Mac is offline, its items gone. */
    private suspend fun TestScope.dropAndFailReconnect(mac: FakeMac, rig: PendingRig): Boolean {
        mac.failNextConnects(IOException("offline"), 1)
        mac.dropLiveSessions()
        if (!eventually { rig.backoff.waiting.size == 1 }) return false
        rig.backoff.release()
        return eventually {
            rig.hub.machines.firstOrNull()?.state is MachineLinkState.Offline && rig.hub.pendingItems.isEmpty() &&
                rig.backoff.waiting.size == 1
        }
    }

    @Test fun sheetWaitsWhileTheMacIsOfflineThenSendsWhenItIsBack() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(questionItem("q1"))
        val rig = pendingRig(listOf(mac))
        assertTrue(rig.synced(1))
        val sheet = PendingSheetModel(rig.key(mac, "q1"), rig.hub, rig.center)

        assertTrue(dropAndFailReconnect(mac, rig), "the failed reconnect dropped the item")

        assertFalse(sheet.handledElsewhere, "the Mac went offline; nobody handled the question")
        assertFalse(sheet.canSend)
        assertEquals(PendingSheetModel.LinkNote.OFFLINE, sheet.linkNote)
        assertEquals("q1", sheet.opened?.item?.requestId, "the sheet keeps what was asked")
        sheet.send(LinkDecision.Question(listOf("Postgres")))
        assertEquals(emptyList(), mac.decisions, "nothing is sent while the Mac is offline")

        // The Mac is back and the question still waits: the answer typed meanwhile can go.
        rig.backoff.release()
        assertTrue(eventually { sheet.canSend })
        assertFalse(sheet.handledElsewhere)
        assertNull(sheet.linkNote)
        sheet.send(LinkDecision.Question(listOf("Postgres")))
        assertEquals(DecisionStatus.Done, sheet.status)
        assertEquals(listOf(FakeMac.Decision("q1", LinkDecision.Question(listOf("Postgres")))), mac.decisions)
    } }

    @Test fun itemResolvedWhileTheMacWasOfflineIsHandledOnceSyncedAgain() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(questionItem("q1"))
        val rig = pendingRig(listOf(mac))
        assertTrue(rig.synced(1))
        val sheet = PendingSheetModel(rig.key(mac, "q1"), rig.hub, rig.center)
        assertTrue(dropAndFailReconnect(mac, rig))
        assertFalse(sheet.handledElsewhere)

        // Answered on the Mac while this phone could not see it; the next sync no longer lists it.
        mac.resolvePending("q1")
        rig.backoff.release()
        assertTrue(eventually { rig.hub.machines.firstOrNull()?.state == MachineLinkState.Online })
        assertTrue(eventually { sheet.handledElsewhere })
        assertFalse(sheet.canSend)
        assertNull(sheet.linkNote)
    } }

    @Test fun handledWhileOnlineStaysHandledWhenTheMacThenGoesOffline() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(questionItem("q1"))
        val rig = pendingRig(listOf(mac))
        assertTrue(rig.synced(1))
        val sheet = PendingSheetModel(rig.key(mac, "q1"), rig.hub, rig.center)
        mac.resolvePending("q1")
        assertTrue(eventually { sheet.handledElsewhere })

        assertTrue(dropAndFailReconnect(mac, rig))

        assertTrue(sheet.handledElsewhere, "it left the list while the Mac was online and synced")
        assertFalse(sheet.canSend)
        assertNull(sheet.linkNote)
    } }

    @Test fun sheetWaitsWhenTheMacRemovesThisIPhone() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(planItem("p1"))
        val rig = pendingRig(listOf(mac))
        assertTrue(rig.synced(1))
        val sheet = PendingSheetModel(rig.key(mac, "p1"), rig.hub, rig.center)

        // The Mac refuses this phone from now on: the next connect is not granted.
        mac.failNextConnects(RelayApiException.Http(403, "not_granted"), 5)
        mac.dropLiveSessions()
        assertTrue(eventually { rig.backoff.waiting.size == 1 })
        rig.backoff.release()
        assertTrue(eventually { rig.hub.machines.firstOrNull()?.state == MachineLinkState.Revoked })
        assertEquals(emptyList(), rig.hub.pendingItems)

        assertFalse(sheet.handledElsewhere, "the Mac removed this phone; nobody handled the plan")
        assertFalse(sheet.canSend)
        assertEquals(PendingSheetModel.LinkNote.NEEDS_PAIRING, sheet.linkNote)
    } }

    @Test fun sheetWaitsWhenTheRelayNoLongerGrantsTheMac() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(questionItem("q1"))
        val rig = pendingRig(listOf(mac))
        assertTrue(rig.synced(1))
        val sheet = PendingSheetModel(rig.key(mac, "q1"), rig.hub, rig.center)

        // The relay lists no grant for the Mac any more (the rig's relay has none).
        rig.hub.refreshGrants()
        assertEquals(MachineLinkState.Revoked, rig.hub.machines.firstOrNull()?.state)
        assertEquals(emptyList(), rig.hub.pendingItems)

        assertFalse(sheet.handledElsewhere)
        assertFalse(sheet.canSend)
        assertEquals(PendingSheetModel.LinkNote.NEEDS_PAIRING, sheet.linkNote)
    } }
}
