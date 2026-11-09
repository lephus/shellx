package com.shellx.core.link

import com.shellx.core.demo.FakeMac
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.diagnostics.LatencyMetric
import com.shellx.core.testing.EventLog
import com.shellx.core.testing.ManualClock
import com.shellx.core.testing.ManualSleeper
import com.shellx.core.testing.agentSession
import com.shellx.core.testing.assertSameCase
import com.shellx.core.testing.chatEntry
import com.shellx.core.testing.eventually
import com.shellx.core.testing.instantSleep
import com.shellx.core.testing.linkTerminal
import com.shellx.core.testing.linkWorkspace
import com.shellx.core.testing.pendingItem
import com.shellx.link.account.RelayApiException
import com.shellx.link.core.LinkClientException
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.NoiseStaticKey
import com.shellx.link.core.PermissionMode
import com.shellx.link.core.ReplyOutcome
import com.shellx.link.core.TerminalViewPush
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertIs
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlin.time.DurationUnit
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout

class MachineConnectionTest {
    private val phone = NoiseStaticKey.generate()

    private fun TestScope.connect(
        mac: FakeMac,
        sleep: suspend (Duration) -> Unit = instantSleep,
        latency: LatencyLog = LatencyLog(),
    ): Pair<MachineConnection, EventLog> {
        val connection = MachineConnection(mac.machine, mac.connector { phone }, latency, backgroundScope, ManualClock(), sleep = sleep)
        val log = EventLog(connection.events, backgroundScope)
        connection.start()
        return connection to log
    }

    private fun seconds(duration: Duration?): Double = assertNotNull(duration).toDouble(DurationUnit.SECONDS)

    // Session

    @Test fun connectsAndPublishesPendingAndSessions() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(pendingItem("r1"))
        mac.upsertSession(agentSession("s1"))

        val (_, log) = connect(mac)

        assertTrue(eventually { log.isOnline }, "${log.states}")
        assertEquals(listOf(MachineLinkState.Connecting, MachineLinkState.Online), log.states)
        assertEquals(listOf("r1"), log.pendingIds)
        assertEquals(true, log.pending?.actionable)
        assertEquals(listOf("s1"), log.sessionIds)
        assertEquals(true, log.sessions?.supported)
        assertEquals(1, mac.connectCount)
    } }

    @Test fun changesAppliedInOrder() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(pendingItem("r1", createdAtMs = 10))
        val latency = LatencyLog()
        val (_, log) = connect(mac, latency = latency)
        eventually { log.isOnline }
        val base = assertNotNull(log.pending?.set?.revision)

        mac.addPending(pendingItem("r3", createdAtMs = 30))
        mac.addPending(pendingItem("r2", createdAtMs = 20))
        mac.resolvePending("r1")
        mac.upsertSession(agentSession("s1", lastActivityMs = 1))
        mac.upsertSession(agentSession("s2", lastActivityMs = 2))
        mac.removeSession("s1")

        val applied = eventually { log.pending?.set?.revision == base + 3 && log.sessionIds == listOf("s2") }
        assertTrue(applied, "${log.pendingIds} ${log.sessionIds}")
        assertEquals(listOf("r2", "r3"), log.pendingIds)
        // Every change was applied on its own, one revision after the other.
        val revisions = log.pendingEvents.map { it.set.revision }
        assertEquals(listOf(base, base + 1, base + 2, base + 3), revisions.takeLast(4))
        assertEquals(2, latency.summary(LatencyMetric.PENDING_ARRIVAL)?.count)
        assertEquals(2, latency.summary(LatencyMetric.SESSION_CHANGE_ARRIVAL)?.count)
        assertEquals(1, mac.snapshotCount)
    } }

    @Test fun revisionGapTriggersResync() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(pendingItem("r1", createdAtMs = 10))
        val (_, log) = connect(mac)
        eventually { log.isOnline }

        mac.skipNextPendingRevision()
        mac.addPending(pendingItem("r2", createdAtMs = 20))
        mac.skipNextSessionRevision()
        mac.upsertSession(agentSession("s9"))

        val resynced = eventually { log.pendingIds == listOf("r1", "r2") && log.sessionIds == listOf("s9") }
        assertTrue(resynced, "${log.pendingIds} ${log.sessionIds}")
        assertEquals(2, mac.snapshotCount, "a gap asks for a new snapshot")
        assertEquals(2, mac.sessionListCount, "a session gap asks for the list again")
        assertEquals(1, mac.connectCount, "the resync happens inside the live session")
        assertEquals(MachineLinkState.Online, log.state)
    } }

    @Test fun hostWithoutSessionsStillServesPending() { runTest {
        val mac = FakeMac("Old Mac", backgroundScope, servesSessionsAndChat = false)
        mac.addPending(pendingItem("r1", createdAtMs = 10))
        val (_, log) = connect(mac)

        assertTrue(eventually { log.isOnline }, "${log.states}")
        assertEquals(false, log.sessions?.supported)
        assertEquals(emptyList(), log.sessionIds)

        mac.addPending(pendingItem("r2", createdAtMs = 20))
        assertTrue(eventually { log.pendingIds == listOf("r1", "r2") }, "${log.pendingIds}")
        assertEquals(true, log.pending?.actionable)
    } }

    @Test fun workspacesArriveBeforeOnlineAndChangesFollow() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("shellx"), linkWorkspace("web", order = 1)))
        val (_, log) = connect(mac)

        assertTrue(eventually { log.isOnline }, "${log.states}")
        // The first workspace event is the whole list, sent before Online.
        assertEquals(listOf("ws-shellx", "ws-web"), log.workspaceEvents.first().set.workspaces.map { it.workspaceId })
        assertEquals(true, log.workspaces?.supported)

        mac.removeWorkspace("ws-shellx")
        mac.upsertWorkspace(linkWorkspace("docs", order = 2))
        assertTrue(eventually { log.workspaceIds == listOf("ws-web", "ws-docs") }, "${log.workspaceIds}")
        // Every change was applied on its own, one revision after the other.
        val tail = log.workspaceEvents.map { it.set.revision }.takeLast(3)
        assertEquals(listOf(0L, 1L, 2L), tail.map { it - tail[0] })
        assertEquals(1, mac.workspaceListCount)
    } }

    @Test fun hostWithoutWorkspacesStillServesPendingAndSessions() { runTest {
        val mac = FakeMac("Old Mac", backgroundScope, servesWorkspaces = false)
        mac.addPending(pendingItem("r1", createdAtMs = 10))
        mac.upsertSession(agentSession("s1"))
        val (_, log) = connect(mac)

        assertTrue(eventually { log.isOnline }, "${log.states}")
        assertEquals(false, log.workspaces?.supported)
        assertEquals(emptyList(), log.workspaceIds)
        assertEquals(listOf("r1"), log.pendingIds)
        assertEquals(listOf("s1"), log.sessionIds)
        assertEquals(1, mac.connectCount, "no failed round on the way")
    } }

    @Test fun chatEntriesConsumedWithoutSubscribers() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.upsertSession(agentSession("s1"))
        mac.setHistory("s1", emptyList())
        val (_, log) = connect(mac)
        eventually { log.isOnline }

        // Nobody looks at chat: the connection still drains every push off the client's unbounded buffer (it hands
        // them on as events and keeps none), and pending items keep flowing.
        for (batch in 0 until 100) {
            mac.pushChat("s1", (0 until 100).map { chatEntry((batch * 100 + it).toLong()) })
        }
        mac.addPending(pendingItem("r1"))

        val drained = eventually(timeout = 30.seconds) { log.chatEntries == 10_000 && log.pendingIds == listOf("r1") }
        assertTrue(drained, "chat ${log.chatEntries}, pending ${log.pendingIds}")
    } }

    /**
     * Plan 3G Decision 1: the connection hands on the live session's terminal pushes, once per session and before its
     * Online, and reads none of them itself. They stay in the session's bounded queue, in order, until a terminal page
     * collects them.
     */
    @Test fun terminalPushesStayInTheSessionsQueueInOrder() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setWorkspaces(listOf(linkWorkspace("a", terminals = listOf(linkTerminal("t1")))))
        val (connection, log) = connect(mac)
        assertTrue(eventually { log.isOnline })
        val pushes = assertNotNull(log.terminalSessions.singleOrNull())

        connection.call { it.openTerminalView("t1", 30, 6) }
        runCurrent()

        val first = withTimeout(5.seconds) { pushes.take(2).toList() }
        assertEquals(TerminalViewPush.Opened("t1"), first[0])
        assertIs<TerminalViewPush.Frame>(first[1])
    } }

    // Reconnect

    @Test fun sessionEndReconnects() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(pendingItem("r1"))
        val (_, log) = connect(mac)
        eventually { log.isOnline }

        mac.dropLiveSessions()

        assertTrue(eventually { log.states.size >= 4 && log.isOnline }, "${log.states}")
        assertEquals(
            listOf(MachineLinkState.Connecting, MachineLinkState.Online, MachineLinkState.Reconnecting, MachineLinkState.Online),
            log.states,
        )
        assertEquals(listOf("r1"), log.pendingIds)
        assertEquals(true, log.pending?.actionable)
        assertEquals(2, mac.connectCount)
    } }

    @Test fun pendingDisabledWhileReconnectingClearedWhenOffline() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(pendingItem("r1"))
        val sleeper = ManualSleeper()
        val (connection, log) = connect(mac, sleep = sleeper.sleep)
        eventually { log.isOnline }
        assertEquals(true, log.pending?.actionable)

        mac.failNextConnects(IOException("offline"), 1)
        mac.dropLiveSessions()

        // The session is gone: the items stay, but nothing may act on them.
        assertTrue(eventually { log.state == MachineLinkState.Reconnecting && sleeper.waiting.size == 1 }, "${log.states}")
        assertEquals(listOf("r1"), log.pendingIds)
        assertEquals(false, log.pending?.actionable)
        assertSameCase(LinkCallException.Offline("MacBook Pro"), assertFails { connection.call { it.snapshot() } })
        assertEquals(0.5, seconds(sleeper.waiting.firstOrNull()), 0.11)

        // The first reconnect fails: the Mac is offline and its items are gone.
        sleeper.release()
        assertTrue(eventually { log.isOffline && sleeper.waiting.size == 1 }, "${log.states}")
        assertEquals(emptyList(), log.pendingIds)
        assertEquals(false, log.pending?.actionable)
        assertEquals(1.0, seconds(sleeper.waiting.firstOrNull()), 0.21)

        // The next attempt succeeds and resyncs.
        sleeper.release()
        assertTrue(eventually { log.isOnline }, "${log.states}")
        assertEquals(listOf("r1"), log.pendingIds)
        assertEquals(true, log.pending?.actionable)
        assertIs<MachineLinkState.Offline>(log.states.dropLast(1).last(), "${log.states}")
    } }

    @Test fun notGrantedStopsLoopAndMarksRevoked() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(pendingItem("r1"))
        val (connection, log) = connect(mac)
        eventually { log.isOnline }

        mac.failNextConnects(RelayApiException.Http(403, "not_granted"), 5)
        mac.dropLiveSessions()

        assertTrue(eventually { log.finished }, "${log.states}")
        assertEquals(MachineLinkState.Revoked, log.state)
        assertEquals(emptyList(), log.pendingIds)
        assertEquals(false, log.pending?.actionable)
        connection.reconnectNow()
        connection.forceReconnect()
        runCurrent()
        assertEquals(2, mac.connectCount, "the loop stopped after the refusal")
    } }

    @Test fun unauthorizedStopsAndReports() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.failNextConnects(RelayApiException.Http(401, "unauthorized"), 5)
        val (_, log) = connect(mac)

        assertTrue(eventually { log.finished }, "${log.states}")
        assertEquals(1, log.signedOut)
        assertNotEquals(MachineLinkState.Online, log.state)
        assertEquals(false, log.pending?.actionable ?: false)
        assertEquals(1, mac.connectCount)
    } }

    @Test fun untrustedHostStops() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.rotateHostKey()
        val (_, log) = connect(mac)

        assertTrue(eventually { log.finished }, "${log.states}")
        assertEquals(MachineLinkState.HostKeyChanged, log.state)
        assertEquals(1, mac.connectCount)
    } }

    @Test fun protocolMismatchStops() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.failNextConnects(LinkClientException.ProtocolMismatch("the host speaks protocol 2"), 5)
        val (_, log) = connect(mac)

        assertTrue(eventually { log.finished }, "${log.states}")
        assertEquals(MachineLinkState.NeedsUpdate, log.state)
        assertEquals(1, mac.connectCount)
    } }

    @Test fun reconnectNowSkipsBackoff() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.failNextConnects(IOException("offline"), 1)
        val sleeper = ManualSleeper()
        val (connection, log) = connect(mac, sleep = sleeper.sleep)

        assertTrue(eventually { log.isOffline && sleeper.waiting.size == 1 }, "${log.states}")

        connection.reconnectNow()

        assertTrue(eventually { log.isOnline }, "${log.states}")
        assertEquals(1, sleeper.cancelled, "the backoff wait was cut short")
        assertEquals(2, mac.connectCount)
    } }

    @Test fun callWhenOfflineThrowsOffline() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(pendingItem("r1"))
        mac.failNextConnects(IOException("offline"), 1)
        val sleeper = ManualSleeper()
        val (connection, log) = connect(mac, sleep = sleeper.sleep)
        eventually { log.isOffline }

        val once = LinkDecision.Permission(PermissionMode.ONCE)
        assertSameCase(LinkCallException.Offline("MacBook Pro"), assertFails { connection.call { it.reply("r1", once) } })
        assertEquals(emptyList(), mac.decisions, "nothing reached the Mac")

        sleeper.release()
        eventually { log.isOnline }
        assertEquals(ReplyOutcome.DELIVERED, connection.call { it.reply("r1", once) })
    } }

    @Test fun forceReconnectAbortsAnAttemptStillSyncing() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.addPending(pendingItem("r1"))
        mac.holdSnapshots()
        val sleeper = ManualSleeper()
        val (connection, log) = connect(mac, sleep = sleeper.sleep)
        assertTrue(eventually { mac.heldSnapshotCount == 1 })

        connection.forceReconnect()

        assertTrue(eventually(timeout = 3.seconds) { mac.connectCount == 2 }, "the attempt was dropped and started again")
        mac.releaseSnapshots()
        assertTrue(eventually { log.isOnline }, "${log.states}")
        // Dropping our own attempt is not a failure: no offline, no cleared items, no backoff.
        assertEquals(listOf(MachineLinkState.Connecting, MachineLinkState.Online), log.states)
        assertEquals(listOf("r1"), log.pendingIds)
        assertEquals(emptyList(), sleeper.requested)
    } }

    @Test fun slotMismatchStops() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.failNextConnects(RelayApiException.SlotMismatch(), 5)
        val (_, log) = connect(mac)

        assertTrue(eventually { log.finished }, "${log.states}")
        assertEquals(MachineLinkState.HostKeyChanged, log.state)
        assertEquals(1, mac.connectCount)
    } }

    @Test fun forceReconnectReplacesLiveSession() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val sleeper = ManualSleeper()
        val (connection, log) = connect(mac, sleep = sleeper.sleep)
        eventually { log.isOnline }

        connection.forceReconnect()

        val back = eventually {
            log.states == listOf(
                MachineLinkState.Connecting, MachineLinkState.Online, MachineLinkState.Reconnecting, MachineLinkState.Online,
            )
        }
        assertTrue(back, "${log.states}")
        assertEquals(emptyList(), sleeper.requested, "a forced reconnect does not wait")
        assertEquals(2, mac.connectCount)
        assertTrue(eventually { mac.liveSessionCount == 1 }, "the old session was closed")
    } }
}
