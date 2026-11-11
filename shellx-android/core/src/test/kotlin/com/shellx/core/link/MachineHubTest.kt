package com.shellx.core.link

import com.shellx.core.account.RelayAccountCalling
import com.shellx.core.demo.FakeMac
import com.shellx.core.diagnostics.LatencyMetric
import com.shellx.core.platform.MemoryKeyValueStore
import com.shellx.core.testing.FakeRelayAccount
import com.shellx.core.testing.Gate
import com.shellx.core.testing.agentSession
import com.shellx.core.testing.allOnline
import com.shellx.core.testing.assertSameCase
import com.shellx.core.testing.chatEntry
import com.shellx.core.testing.eventually
import com.shellx.core.testing.hubRig
import com.shellx.core.testing.listing
import com.shellx.core.testing.pendingItem
import com.shellx.link.account.AccountSignIn
import com.shellx.link.account.EmailChallenge
import com.shellx.link.account.PairedMachine
import com.shellx.link.account.PairedMachineListing
import com.shellx.link.account.RelayApiException
import com.shellx.link.core.ChatInterruptOutcome
import com.shellx.link.core.ChatSendOutcome
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.LinkSession
import com.shellx.link.core.PermissionMode
import com.shellx.link.core.ReplyOutcome
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest

class MachineHubTest {
    private fun model(hub: MachineHub, mac: FakeMac): MachineModel? = hub.machines.firstOrNull { it.id == mac.machine.machineId }

    // Brief tests

    @Test fun startsOneConnectionPerPairedMachine() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val b = FakeMac("Mac mini", backgroundScope)
        val rig = hubRig(listOf(a, b))

        rig.hub.start()
        rig.hub.start()

        assertEquals(listOf("MacBook Pro", "Mac mini"), rig.hub.machines.map { it.name })
        assertTrue(eventually { allOnline(rig.hub) }, "${rig.hub.machines.map { it.state }}")
        assertEquals(listOf(1, 1), listOf(a.connectCount, b.connectCount))
    } }

    @Test fun pendingMergedAcrossMachinesSortedByCreation() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val b = FakeMac("Mac mini", backgroundScope)
        a.addPending(pendingItem("a1", createdAtMs = 30))
        a.addPending(pendingItem("a2", createdAtMs = 10))
        b.addPending(pendingItem("b1", createdAtMs = 20))
        val rig = hubRig(listOf(a, b))

        rig.hub.start()

        assertTrue(eventually { rig.hub.pendingItems.size == 3 }, "${rig.hub.pendingItems.map { it.item.requestId }}")
        val items = rig.hub.pendingItems
        assertEquals(listOf("a2", "b1", "a1"), items.map { it.item.requestId })
        assertEquals(listOf("MacBook Pro", "Mac mini", "MacBook Pro"), items.map { it.machineName })
        assertEquals(listOf(true, true, true), items.map { it.actionable })
        assertEquals(PendingKey(b.machine.machineId, "b1"), items[1].id)
    } }

    @Test fun refreshMarksMissingGrantRevokedAndRenames() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val b = FakeMac("Mac mini", backgroundScope)
        b.addPending(pendingItem("b1"))
        val rig = hubRig(listOf(a, b))
        rig.hub.start()
        eventually { allOnline(rig.hub) && rig.hub.pendingItems.size == 1 }

        rig.relay.setGrants(listOf(listing(a.machine, name = "Studio")))
        rig.hub.refreshGrants()

        assertEquals("Studio", model(rig.hub, a)?.name)
        assertEquals(MachineLinkState.Online, model(rig.hub, a)?.state)
        assertEquals(MachineLinkState.Revoked, model(rig.hub, b)?.state)
        assertEquals(emptyList(), rig.hub.pendingItems.map { it.item.requestId })
        assertTrue(eventually { b.liveSessionCount == 0 }, "the revoked Mac's session was closed")
        assertEquals(
            listOf(a.machine.machineId, b.machine.machineId), rig.vault.machines().map { it.machineId },
            "refresh does not write the vault",
        )
        assertEquals(2, rig.hub.machines.size, "a revoked Mac stays listed until the user removes it")
    } }

    @Test fun chatResetArrivesAsItsOwnUpdateInOrder() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        a.upsertSession(agentSession("s1"))
        a.setHistory("s1", emptyList())
        val rig = hubRig(listOf(a))
        rig.hub.start()
        assertTrue(eventually { allOnline(rig.hub) && rig.hub.liveSessions.size == 1 })
        val updates = mutableListOf<ChatUpdate>()
        val stream = rig.hub.chatUpdates()
        backgroundScope.launch { stream.collect { updates += it } }

        // Entries of the old transcript, the reset, then entries of the new one.
        a.pushChat("s1", listOf(chatEntry(7)))
        a.resetChat("s1", listOf(chatEntry(1)))
        a.pushChat("s1", listOf(chatEntry(2)))

        assertTrue(eventually { updates.size == 3 }, "$updates")
        val ref = SessionRef(a.machine.machineId, "s1", "claude", "shellx")
        assertEquals(
            listOf(ChatUpdate.Upsert(ref, listOf(chatEntry(7))), ChatUpdate.Reset(ref), ChatUpdate.Upsert(ref, listOf(chatEntry(2)))),
            updates,
        )
        assertEquals(emptyList(), updates[1].entries, "a reset carries no entries")
        assertEquals(1, rig.hub.transcriptResets(ref))
        // The Mac answers from the new transcript.
        val page = rig.hub.chatHistory(ref, null, 50)
        assertEquals(listOf(1L, 2L), page.entries.map { it.seq })
    } }

    @Test fun chatAndSessionUpdatesMulticast() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        a.upsertSession(agentSession("s1"))
        a.setHistory("s1", emptyList())
        val rig = hubRig(listOf(a))
        rig.hub.start()
        eventually { allOnline(rig.hub) && rig.hub.liveSessions.size == 1 }

        val chatA = mutableListOf<ChatUpdate>()
        val chatB = mutableListOf<ChatUpdate>()
        val listsA = mutableListOf<MachineSessions>()
        val listsB = mutableListOf<MachineSessions>()
        val streamChatA = rig.hub.chatUpdates()
        val streamChatB = rig.hub.chatUpdates()
        val streamListsA = rig.hub.sessionUpdates()
        val streamListsB = rig.hub.sessionUpdates()
        backgroundScope.launch { streamChatA.collect { chatA += it } }
        backgroundScope.launch { streamListsA.collect { listsA += it } }
        val readerChatB = backgroundScope.launch { streamChatB.collect { chatB += it } }
        val readerListsB = backgroundScope.launch { streamListsB.collect { listsB += it } }

        a.pushChat("s1", listOf(chatEntry(1)))
        a.upsertSession(agentSession("s2"))

        val both = eventually { chatA.size == 1 && chatB.size == 1 && listsA.size == 1 && listsB.size == 1 }
        assertTrue(both, "${chatA.size} ${chatB.size} ${listsA.size} ${listsB.size}")
        val ref = SessionRef(a.machine.machineId, "s1", "claude", "shellx")
        assertEquals(ref, chatA.first().ref)
        assertEquals("shellx", chatA.first().ref.workspaceTitle)
        assertEquals(listOf(chatEntry(1)), chatA.first().entries)
        assertEquals(listOf(chatEntry(1)), chatB.first().entries)
        assertEquals(a.machine.machineId, listsA.first().machineId)
        assertEquals(setOf("s1", "s2"), listsB.first().sessions.map { it.sessionId }.toSet())

        // A reader that stops is dropped; the other keeps receiving.
        readerChatB.cancel()
        readerListsB.cancel()
        assertTrue(eventually { rig.hub.chatSubscriberCount == 1 && rig.hub.sessionSubscriberCount == 1 })
        a.pushChat("s1", listOf(chatEntry(2)))
        assertTrue(eventually { chatA.size == 2 })
        assertEquals(1, chatB.size)

        // No replay: a new reader only sees what comes after it.
        val late = mutableListOf<ChatUpdate>()
        val streamLate = rig.hub.chatUpdates()
        backgroundScope.launch { streamLate.collect { late += it } }
        a.pushChat("s1", listOf(chatEntry(3)))
        assertTrue(eventually { chatA.size == 3 && late.size == 1 })
        assertEquals(listOf(chatEntry(3)), late.first().entries)
    } }

    // Calls, pairing, default Mac

    @Test fun callsRouteToTheirMac() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val b = FakeMac("Mac mini", backgroundScope)
        a.addPending(pendingItem("a1"))
        b.addPending(pendingItem("b1"))
        a.upsertSession(agentSession("s1"))
        a.setHistory("s1", listOf(chatEntry(1), chatEntry(2)))
        a.setInterruptOutcome(ChatInterruptOutcome.SENT)
        val rig = hubRig(listOf(a, b))
        rig.hub.start()
        eventually { allOnline(rig.hub) && rig.hub.pendingItems.size == 2 }

        val always = LinkDecision.Permission(PermissionMode.ALWAYS)
        assertEquals(ReplyOutcome.DELIVERED, rig.hub.reply(PendingKey(b.machine.machineId, "b1"), always))
        assertEquals(emptyList(), a.decisions)
        assertEquals(listOf(FakeMac.Decision("b1", always)), b.decisions)
        assertNull(rig.latency.summary(LatencyMetric.REPLY_ROUND_TRIP), "DecisionCenter measures from the tap, not the hub")

        val ref = assertNotNull(rig.hub.liveSessions.firstOrNull()?.ref)
        assertEquals(a.machine.machineId, ref.machineId)
        val page = rig.hub.chatHistory(ref, null, 10)
        assertEquals(listOf(chatEntry(1), chatEntry(2)), page.entries)
        assertFalse(page.hasMore)
        assertEquals(ChatSendOutcome.SUBMITTED, rig.hub.chatSend(ref, "run the tests"))
        assertEquals(listOf(FakeMac.SentText("s1", "run the tests")), a.sentTexts)
        assertEquals(ChatInterruptOutcome.SENT, rig.hub.chatInterrupt(ref, true))
        assertEquals(listOf(FakeMac.Interrupt("s1", true)), a.interrupts)

        assertSameCase(
            LinkCallException.UnknownMachine(),
            assertFails { rig.hub.reply(PendingKey("nope", "x"), LinkDecision.Permission(PermissionMode.ONCE)) },
        )
    } }

    @Test fun addSavesMachineAndReplacesSameID() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val rig = hubRig(listOf(a), saved = emptyList())
        rig.hub.start()
        assertEquals(0, rig.hub.machines.size)

        rig.hub.add(a.machine)
        assertTrue(eventually { allOnline(rig.hub) })
        assertEquals(listOf(a.machine), rig.vault.machines())
        assertEquals("u1", rig.vault.machinesOwner())
        assertEquals(a.machine.machineId, rig.hub.defaultMachineId)

        val renamed = a.machine.copy(name = "Studio")
        rig.hub.add(renamed)
        assertEquals(listOf("Studio"), rig.hub.machines.map { it.name })
        assertEquals(listOf(renamed), rig.vault.machines())
        assertTrue(eventually { allOnline(rig.hub) })
        assertTrue(eventually { a.liveSessionCount == 1 }, "the replaced connection was stopped")
    } }

    @Test fun defaultMachineFallsBackToFirst() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val b = FakeMac("Mac mini", backgroundScope)
        val settings = MemoryKeyValueStore()
        val rig = hubRig(listOf(a, b), settings = settings)
        assertNull(rig.hub.defaultMachineId, "no Macs, no default")
        rig.hub.start()
        assertEquals(a.machine.machineId, rig.hub.defaultMachineId)

        rig.hub.defaultMachineId = b.machine.machineId
        assertEquals(b.machine.machineId, settings.getString("shellx.defaultMachineID"))
        assertEquals(b.machine.machineId, rig.hub.defaultMachineId)

        // A default whose Mac is gone falls back to the first Mac.
        settings.putString("shellx.defaultMachineID", "removed-mac")
        val other = hubRig(listOf(a, b), settings = settings)
        other.hub.start()
        assertEquals(a.machine.machineId, other.hub.defaultMachineId)
    } }

    @Test fun refreshUnauthorizedReports() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val rig = hubRig(listOf(a))
        rig.relay.setError(RelayApiException.Http(401, "unauthorized"), FakeRelayAccount.Function.MACHINES)

        rig.hub.refreshGrants()
        rig.hub.refreshGrants()

        assertEquals(1, rig.unauthorized.size, "reported once")
    } }

    // Fix round 1 regressions

    /** `add` replacing a Mac waits for the old connection to close; a stop meanwhile wins. */
    @Test fun stopAllWhileAddingStartsNothing() { runTest {
        val b = FakeMac("Mac mini", backgroundScope)
        val gate = Gate()
        val rig = hubRig(listOf(b), connector = { GatedConnector(it, setOf(b.machine.machineId), gate) })
        rig.hub.start()
        eventually { gate.waiting == 1 }

        val renamed = b.machine.copy(name = "Studio")
        val adding = backgroundScope.async { rig.hub.add(renamed) }
        assertTrue(eventually { rig.hub.connectionCount == 0 }, "add is waiting for the old connection to close")

        rig.hub.stopAll()
        gate.open()
        adding.await()

        assertEquals(0, rig.hub.connectionCount, "a stopped hub never reconnects")
    } }

    /** A Mac re-paired while the grant list was in flight is not revoked by that (older) list. */
    @Test fun refreshSkipsMacRepairedMeanwhile() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val gate = Gate()
        var base: FakeRelayAccount? = null
        val rig = hubRig(listOf(a), relay = { relay -> base = relay; GatedGrantsRelay(relay, gate) })
        val relay = assertNotNull(base)
        rig.hub.start()
        eventually { allOnline(rig.hub) }

        val refreshing = backgroundScope.launch { rig.hub.refreshGrants() }
        eventually { gate.waiting == 1 }
        val repaired = a.machine.copy(name = "Studio")
        rig.hub.add(repaired)
        relay.setGrants(emptyList())
        gate.open()
        refreshing.join()

        assertNotEquals(MachineLinkState.Revoked, model(rig.hub, a)?.state)
        assertEquals("Studio", model(rig.hub, a)?.name)
    } }

    /** A 401 that answers a grant request sent before a sign-out does not sign out a second time. */
    @Test fun refreshAfterStopAllDoesNotReport() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val gate = Gate()
        var base: FakeRelayAccount? = null
        val rig = hubRig(listOf(a), relay = { relay -> base = relay; GatedGrantsRelay(relay, gate) })
        val relay = assertNotNull(base)
        relay.setError(RelayApiException.Http(401, "unauthorized"), FakeRelayAccount.Function.MACHINES)
        rig.hub.start()

        val refreshing = backgroundScope.launch { rig.hub.refreshGrants() }
        eventually { gate.waiting == 1 }
        rig.hub.stopAll()
        gate.open()
        refreshing.join()

        assertEquals(0, rig.unauthorized.size)
    } }

    // Task 4

    /** The UI tells "no Mac yet" from "not read yet": a hub is loaded once `start()` read the vault. */
    @Test fun loadedOnceTheVaultWasRead() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val rig = hubRig(listOf(a))
        assertFalse(rig.hub.isLoaded)

        rig.hub.start()

        assertTrue(rig.hub.isLoaded)
        assertEquals(1, rig.hub.machines.size)
    } }
}

/**
 * Holds connects to the [gated] Macs until the gate opens, then fails them; others go to [base]. The hold ignores
 * cancellation, so stopping such a connection waits for the gate.
 */
internal class GatedConnector(
    private val base: MachineLinkConnecting,
    private val gated: Set<String>,
    private val gate: Gate,
) : MachineLinkConnecting {
    override suspend fun connect(machine: PairedMachine): LinkSession {
        if (machine.machineId !in gated) return base.connect(machine)
        gate.wait()
        throw IOException("offline")
    }
}

/** A FakeRelayAccount whose grant list waits for the gate before answering. */
private class GatedGrantsRelay(private val base: FakeRelayAccount, private val gate: Gate) : RelayAccountCalling {
    override suspend fun nonce(): String = base.nonce()

    override suspend fun signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: ByteArray): AccountSignIn =
        base.signInWithGoogle(idToken, nonce, deviceName, clientKey)

    override suspend fun deleteAccount(idToken: String, nonce: String, token: String) = base.deleteAccount(idToken, nonce, token)

    override suspend fun requestEmailCode(email: String, locale: String): EmailChallenge = base.requestEmailCode(email, locale)

    override suspend fun signInWithEmailCode(challengeId: String, code: String, deviceName: String, clientKey: ByteArray): AccountSignIn =
        base.signInWithEmailCode(challengeId, code, deviceName, clientKey)

    override suspend fun deleteAccountWithEmailCode(challengeId: String, code: String, token: String) =
        base.deleteAccountWithEmailCode(challengeId, code, token)

    override suspend fun logout(token: String) = base.logout(token)

    override suspend fun machines(token: String): List<PairedMachineListing> {
        gate.wait()
        return base.machines(token)
    }

    override suspend fun unpair(grantId: String, token: String) = base.unpair(grantId, token)

    override suspend fun pair(offerUri: String, clientKey: ByteArray, token: String): PairedMachine =
        base.pair(offerUri, clientKey, token)

    override suspend fun setPushToken(fcmToken: String, token: String) = base.setPushToken(fcmToken, token)

    override suspend fun unsetPushToken(token: String) = base.unsetPushToken(token)
}
