package com.shellx.core.demo

import com.shellx.core.testing.agentSession
import com.shellx.core.testing.assertSameCase
import com.shellx.core.testing.eventually
import com.shellx.core.testing.pendingItem
import com.shellx.link.account.RelayApiException
import com.shellx.link.core.LinkClientException
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.LinkSession
import com.shellx.link.core.LinkWorkspace
import com.shellx.link.core.NoiseException
import com.shellx.link.core.NoiseStaticKey
import com.shellx.link.core.PendingChange
import com.shellx.link.core.PendingSnapshot
import com.shellx.link.core.PermissionMode
import com.shellx.link.core.ReplyOutcome
import com.shellx.link.core.SessionChange
import com.shellx.link.core.SessionList
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

class FakeMacTest {
    private val phone = NoiseStaticKey.generate()

    private suspend fun connect(mac: FakeMac): LinkSession = mac.connector { phone }.connect(mac.machine)

    private suspend fun TestScope.features(
        servesSessionsAndChat: Boolean = true,
        acceptsAttachments: Boolean = true,
        servesWorkspaces: Boolean = true,
        acceptsWorkspaceControl: Boolean = true,
    ): Set<String> = connect(
        FakeMac(
            "MacBook Pro", backgroundScope, servesSessionsAndChat = servesSessionsAndChat,
            acceptsAttachments = acceptsAttachments, servesWorkspaces = servesWorkspaces,
            acceptsWorkspaceControl = acceptsWorkspaceControl,
        ),
    ).hostFeatures

    @Test fun featuresFollowWhatTheMacServes() { runTest {
        assertEquals(setOf("attachments", "workspaces", "workspace_control", "agent_close", "terminal_close"), features())
        assertEquals(setOf("workspaces", "workspace_control", "terminal_close"), features(servesSessionsAndChat = false))
        assertEquals(setOf("attachments", "agent_close"), features(servesWorkspaces = false))
        assertFalse("attachments" in features(acceptsAttachments = false))
        assertFalse("workspace_control" in features(acceptsWorkspaceControl = false))
    } }

    @Test fun connectCountsEveryAttemptAndFailsAsTold() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.failNextConnects(IOException("down"), 2)
        repeat(2) { assertEquals("down", assertFailsWith<IOException> { connect(mac) }.message) }
        connect(mac)
        assertEquals(3, mac.connectCount)
        assertEquals(1, mac.liveSessionCount)
    } }

    @Test fun aRotatedKeyIsAnUntrustedPeer() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.rotateHostKey()
        assertSameCase(NoiseException.UntrustedPeer(), assertFails { connect(mac) })
        assertEquals(1, mac.connectCount)
        assertEquals(0, mac.liveSessionCount)
        mac.connector { phone }.connect(mac.machine.copy(hostKey = mac.pairingOffer().hostKey))
        assertEquals(1, mac.liveSessionCount)
    } }

    @Test fun pendingRevisionsCountEveryChangeAndSkipLeavesAGap() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(pendingItem("r1"))
        val session = connect(mac)
        assertEquals(PendingSnapshot(1, listOf(pendingItem("r1"))), session.snapshot())
        mac.addPending(pendingItem("r2"))
        assertEquals(PendingChange(2, listOf(pendingItem("r2")), emptyList()), session.changes.first())
        mac.skipNextPendingRevision()
        mac.resolvePending("r1")
        assertEquals(PendingChange(4, emptyList(), listOf("r1")), session.changes.first())
        assertEquals(1, mac.snapshotCount)
    } }

    @Test fun replyResolvesAKnownItemAndAnswersAlreadyHandledAfter() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(pendingItem("r1"))
        mac.addPending(pendingItem("r2"))
        val session = connect(mac)
        val once = LinkDecision.Permission(PermissionMode.ONCE)
        assertEquals(ReplyOutcome.DELIVERED, session.reply("r1", once))
        assertEquals(PendingChange(3, emptyList(), listOf("r1")), session.changes.first())
        assertEquals(ReplyOutcome.ALREADY_HANDLED, session.reply("r1", once))
        assertEquals(ReplyOutcome.UNKNOWN, session.reply("nope", once))
        assertEquals(
            listOf(FakeMac.Decision("r1", once), FakeMac.Decision("r1", once), FakeMac.Decision("nope", once)),
            mac.decisions,
        )
        mac.setReplyOutcome(ReplyOutcome.ALREADY_HANDLED)
        assertEquals(ReplyOutcome.ALREADY_HANDLED, session.reply("r2", once))
    } }

    @Test fun heldSnapshotsWaitAndAClosedSessionStopsWaiting() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val session = connect(mac)
        mac.holdSnapshots()
        val call = backgroundScope.async { runCatching { session.snapshot() }.exceptionOrNull() }
        assertTrue(eventually { mac.heldSnapshotCount == 1 })
        session.close()
        assertSameCase(LinkClientException.SessionClosed(), call.await())
        assertEquals(0, mac.snapshotCount)
        mac.releaseSnapshots()
        assertTrue(eventually { mac.snapshotCount == 1 })
        assertEquals(0, mac.heldSnapshotCount)
        assertEquals(0, mac.liveSessionCount)
    } }

    @Test fun sessionsFollowTheMacAndAreUnsupportedWithoutChat() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.upsertSession(agentSession("s1"))
        val session = connect(mac)
        assertEquals(SessionList(1, listOf(agentSession("s1"))), session.sessions())
        assertEquals(1, mac.sessionListCount)
        mac.upsertSession(agentSession("s2"))
        assertEquals(SessionChange(2, listOf(agentSession("s2")), emptyList()), session.sessionChanges.first())
        mac.removeSession("s1")
        assertEquals(SessionChange(3, emptyList(), listOf("s1")), session.sessionChanges.first())
        val bare = FakeMac("Mac mini", backgroundScope, servesSessionsAndChat = false)
        assertSameCase(
            LinkClientException.Remote("unsupported", "this host has no agent sessions"),
            assertFails { connect(bare).sessions() },
        )
        assertEquals(0, bare.sessionListCount)
    } }

    @Test fun aWorkspaceListThatDoesNotFitIsTooLarge() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(LinkWorkspace("ws-huge", "w".repeat(70_000), 0, terminals = emptyList())))
        val session = connect(mac)
        assertSameCase(
            LinkClientException.Remote("too_large", "the answer does not fit in one frame"),
            assertFails { session.workspaces() },
        )
        assertEquals(1, mac.workspaceListCount)
    } }

    @Test fun dropLiveSessionsEndsEveryFlowAndCall() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val first = connect(mac)
        val second = connect(mac)
        assertEquals(2, mac.liveSessionCount)
        mac.holdSnapshots()
        val call = backgroundScope.async { runCatching { first.snapshot() }.exceptionOrNull() }
        assertTrue(eventually { mac.heldSnapshotCount == 1 })
        mac.dropLiveSessions()
        assertSameCase(LinkClientException.SessionClosed(), call.await())
        for (session in listOf(first, second)) {
            assertEquals(emptyList(), session.changes.toList())
            assertEquals(emptyList(), session.sessionChanges.toList())
            assertEquals(emptyList(), session.workspaceChanges.toList())
            assertEquals(emptyList(), session.chatEntries.toList())
        }
        assertSameCase(LinkClientException.SessionClosed(), assertFails { second.sessions() })
        assertEquals(0, mac.liveSessionCount)
    } }

    @Test fun phoneCallsAreCounted() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val session = connect(mac)
        session.snapshot()
        session.sessions()
        session.workspaces()
        assertEquals(3, mac.phoneCallCount)
        val reader = backgroundScope.launch { session.changes.collect {} }
        runCurrent()
        reader.cancel()
        assertEquals(3, mac.phoneCallCount)
    } }

    @Test fun fleetConnectsByMachineIdAndRefusesStrangers() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val b = FakeMac("Mac mini", backgroundScope)
        val fleet = FakeMacFleet(listOf(a)) { phone }
        fleet.connect(a.machine)
        assertEquals(1, a.connectCount)
        assertSameCase(RelayApiException.Http(404, "machine_not_found"), assertFails { fleet.connect(b.machine) })
        assertEquals(0, b.connectCount)
    } }
}
