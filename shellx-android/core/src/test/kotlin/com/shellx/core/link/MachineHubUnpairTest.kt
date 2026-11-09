package com.shellx.core.link

import com.shellx.core.account.AccountVault
import com.shellx.core.account.SecretStoreException
import com.shellx.core.account.StoredSession
import com.shellx.core.demo.FakeMac
import com.shellx.core.demo.FakeMacFleet
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.platform.MemoryKeyValueStore
import com.shellx.core.testing.FakeRelayAccount
import com.shellx.core.testing.HubRig
import com.shellx.core.testing.InMemorySecretStore
import com.shellx.core.testing.ManualClock
import com.shellx.core.testing.eventually
import com.shellx.core.testing.hubRig
import com.shellx.core.testing.instantSleep
import com.shellx.core.testing.listing
import com.shellx.link.account.RelayApiException
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest

class MachineHubUnpairTest {
    private suspend fun TestScope.rig(macs: List<FakeMac>): HubRig {
        val rig = hubRig(macs, sleep = instantSleep, start = true)
        assertTrue(eventually { rig.hub.machines.all { it.state == MachineLinkState.Online } }, "${rig.hub.machines.map { it.state }}")
        rig.relay.resetCalls()
        return rig
    }

    private fun ids(hub: MachineHub): List<String> = hub.machines.map { it.id }

    // Brief tests

    @Test fun unpairCallsRelayThenForgets() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val b = FakeMac("Mac mini", backgroundScope)
        val rig = rig(listOf(a, b))

        rig.hub.unpair(a.machine.machineId)

        assertEquals(
            listOf(FakeRelayAccount.Call.Machines("tok-1"), FakeRelayAccount.Call.Unpair("g-${a.machine.machineId}", "tok-1")),
            rig.relay.calls,
        )
        assertEquals(listOf(b.machine.machineId), ids(rig.hub))
        assertEquals(listOf(b.machine), rig.vault.machines())
        assertEquals("u1", rig.vault.machinesOwner())
        assertEquals(1, rig.hub.connectionCount)
        assertTrue(eventually { a.liveSessionCount == 0 }, "the session to the unpaired Mac was closed")
        assertEquals(1, b.liveSessionCount, "the other Mac is untouched")
    } }

    @Test fun unpairMissingGrantStillForgets() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val b = FakeMac("Mac mini", backgroundScope)
        val rig = rig(listOf(a, b))

        // The relay no longer lists the Mac (removed on the Mac meanwhile).
        rig.relay.setGrants(listOf(listing(b.machine)))
        rig.hub.unpair(a.machine.machineId)
        assertEquals(listOf(FakeRelayAccount.Call.Machines("tok-1")), rig.relay.calls, "nothing to unpair")
        assertEquals(listOf(b.machine.machineId), ids(rig.hub))

        // Listed, but gone by the time the delete arrives.
        rig.relay.resetCalls()
        rig.relay.setError(RelayApiException.Http(404, "not_found"), FakeRelayAccount.Function.UNPAIR)
        rig.hub.unpair(b.machine.machineId)
        assertEquals(
            listOf(FakeRelayAccount.Call.Machines("tok-1"), FakeRelayAccount.Call.Unpair("g-${b.machine.machineId}", "tok-1")),
            rig.relay.calls,
        )
        assertEquals(emptyList(), ids(rig.hub))
        assertEquals(emptyList(), rig.vault.machines())
    } }

    @Test fun unpairNetworkErrorKeepsMachine() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val rig = rig(listOf(a))

        rig.relay.setError(IOException("offline"), FakeRelayAccount.Function.MACHINES)
        assertEquals("offline", assertFailsWith<IOException> { rig.hub.unpair(a.machine.machineId) }.message)
        assertEquals(listOf(a.machine.machineId), ids(rig.hub))
        assertEquals(listOf(a.machine), rig.vault.machines())

        rig.relay.setError(null, FakeRelayAccount.Function.MACHINES)
        rig.relay.setError(IOException("timed out"), FakeRelayAccount.Function.UNPAIR)
        assertEquals("timed out", assertFailsWith<IOException> { rig.hub.unpair(a.machine.machineId) }.message)
        assertEquals(listOf(a.machine.machineId), ids(rig.hub))
        assertEquals(listOf(a.machine), rig.vault.machines())
        assertEquals(MachineLinkState.Online, rig.hub.machines.first().state, "the Mac stays connected")
    } }

    @Test fun defaultMachineFallsBackWhenRemoved() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val b = FakeMac("Mac mini", backgroundScope)
        val rig = rig(listOf(a, b))
        rig.hub.defaultMachineId = b.machine.machineId

        rig.hub.unpair(b.machine.machineId)

        assertEquals(a.machine.machineId, rig.hub.defaultMachineId)
        assertNull(rig.settings.getString("shellx.defaultMachineID"), "the removed Mac is not remembered")

        rig.hub.unpair(a.machine.machineId)
        assertNull(rig.hub.defaultMachineId)
    } }

    // More

    /** A Mac that already removed this phone has no grant left: removing it needs no network. */
    @Test fun removeRevokedMacWorksOffline() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val b = FakeMac("Mac mini", backgroundScope)
        val rig = rig(listOf(a, b))
        rig.relay.setGrants(listOf(listing(b.machine)))
        rig.hub.refreshGrants()
        assertEquals(MachineLinkState.Revoked, rig.hub.machines.first().state)

        rig.relay.setError(IOException("offline"), FakeRelayAccount.Function.MACHINES)
        rig.hub.unpair(a.machine.machineId)

        assertEquals(listOf(b.machine.machineId), ids(rig.hub))
        assertEquals(listOf(b.machine), rig.vault.machines())
    } }

    @Test fun unpairUnauthorizedReportsAndKeepsMachine() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val rig = rig(listOf(a))
        rig.relay.setError(RelayApiException.Http(401, "unauthorized"), FakeRelayAccount.Function.MACHINES)

        assertFailsWith<RelayApiException.Http> { rig.hub.unpair(a.machine.machineId) }

        assertEquals(1, rig.unauthorized.size)
        assertEquals(listOf(a.machine.machineId), ids(rig.hub))
    } }

    @Test fun unpairUnknownMachineDoesNothing() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val rig = rig(listOf(a))

        rig.hub.unpair("never-paired")

        assertEquals(emptyList(), rig.relay.calls)
        assertEquals(listOf(a.machine.machineId), ids(rig.hub))
    } }

    @Test fun vaultWriteFailureKeepsMachine() { runTest {
        val store = InMemorySecretStore()
        val a = FakeMac("MacBook Pro", backgroundScope)
        val vault = AccountVault(store, StandardTestDispatcher(testScheduler))
        vault.setSession(StoredSession("u1", "d1", "tok-1", "a@b.c"))
        vault.setMachines(listOf(a.machine), "u1")
        val relay = FakeRelayAccount()
        val hub = MachineHub(
            vault, relay, FakeMacFleet(listOf(a)) { vault.phoneKey() }, LatencyLog(), MemoryKeyValueStore(), backgroundScope,
            ManualClock(), instantSleep,
        ) {}
        hub.start()
        store.failWrites = SecretStoreException.Failed()

        assertFailsWith<SecretStoreException.Failed> { hub.unpair(a.machine.machineId) }

        assertEquals(listOf(a.machine.machineId), ids(hub), "still listed: the vault still has it")
    } }
}
