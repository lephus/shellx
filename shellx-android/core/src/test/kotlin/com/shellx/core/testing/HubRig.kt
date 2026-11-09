package com.shellx.core.testing

import com.shellx.core.account.AccountVault
import com.shellx.core.account.RelayAccountCalling
import com.shellx.core.account.StoredSession
import com.shellx.core.demo.FakeMac
import com.shellx.core.demo.FakeMacFleet
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachineLinkConnecting
import com.shellx.core.link.MachineLinkState
import com.shellx.core.platform.MemoryKeyValueStore
import com.shellx.link.account.PairedMachine
import com.shellx.link.account.PairedMachineListing
import kotlin.time.Duration
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope

/**
 * A signed-in hub over fake Macs (MachineHubTests' rig and HubRig.swift): the vault holds the session u1/d1/tok-1/a@b.c
 * and the Macs saved for u1, the relay lists a grant for each Mac, and the hub runs in the test's backgroundScope.
 */
class HubRig(
    val hub: MachineHub,
    val vault: AccountVault,
    val relay: FakeRelayAccount,
    val settings: MemoryKeyValueStore,
    val latency: LatencyLog,
    val clock: ManualClock,
    /** The hub's reconnect and grace waits, unless the rig was given its own `sleep`. */
    val backoff: ManualSleeper,
    /** One entry per call of the hub's onUnauthorized. */
    val unauthorized: MutableList<Unit>,
    private val test: TestScope,
) {
    /** HubRig.swift's online(sessions:): eventually every Mac is online and liveSessions.size == sessions. */
    suspend fun online(sessions: Int): Boolean = test.eventually {
        hub.machines.all { it.state == MachineLinkState.Online } && hub.liveSessions.size == sessions
    }
}

/** The relay's grant for [machine], as MachineHubTests' `listing`: grant "g-<machineId>", "macos", online, fingerprint "f". */
fun listing(machine: PairedMachine, name: String? = null): PairedMachineListing = PairedMachineListing(
    grantId = "g-${machine.machineId}", machineId = machine.machineId, name = name ?: machine.name, platform = "macos",
    online = true, linkSlot = machine.linkSlot, fingerprint = "f",
)

/**
 * The hub's sleep is [sleep] when given (MachineHubWorkspaceTests and FakeMacDemoScriptTests pass instantSleep), else
 * [sleeper]'s (the Swift rigs' ManualSleeper). onUnauthorized appends to [HubRig.unauthorized]. [saved] are the Macs in
 * the vault ([macs] by default); [connector] and [relay] wrap the fakes. [start] starts the hub before returning.
 */
suspend fun TestScope.hubRig(
    macs: List<FakeMac>,
    saved: List<FakeMac>? = null,
    sleeper: ManualSleeper = ManualSleeper(),
    sleep: (suspend (Duration) -> Unit)? = null,
    settings: MemoryKeyValueStore = MemoryKeyValueStore(),
    clock: ManualClock = ManualClock(),
    connector: (MachineLinkConnecting) -> MachineLinkConnecting = { it },
    relay: (FakeRelayAccount) -> RelayAccountCalling = { it },
    start: Boolean = false,
): HubRig {
    val vault = AccountVault(InMemorySecretStore(), StandardTestDispatcher(testScheduler))
    vault.setSession(StoredSession("u1", "d1", "tok-1", "a@b.c"))
    vault.setMachines((saved ?: macs).map { it.machine }, "u1")
    val fake = FakeRelayAccount()
    fake.setGrants(macs.map { listing(it.machine) })
    val latency = LatencyLog()
    val unauthorized = mutableListOf<Unit>()
    val hub = MachineHub(
        vault, relay(fake), connector(FakeMacFleet(macs) { vault.phoneKey() }), latency, settings, backgroundScope, clock,
        sleep ?: sleeper.sleep,
    ) { unauthorized += Unit }
    if (start) hub.start()
    return HubRig(hub, vault, fake, settings, latency, clock, sleeper, unauthorized, this)
}

/** Every Mac of the hub is online (and there is at least one). */
fun allOnline(hub: MachineHub): Boolean =
    hub.machines.isNotEmpty() && hub.machines.all { it.state == MachineLinkState.Online }
