package com.shellx.core.testing

import com.shellx.core.account.AccountVault
import com.shellx.core.account.AppCoordinator
import com.shellx.core.account.LocalDataWiping
import com.shellx.core.demo.FakeMac
import com.shellx.core.demo.FakeMacFleet
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.link.MachineHub
import com.shellx.core.platform.MemoryKeyValueStore
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope

/** An AppCoordinator over fakes (AppCoordinatorTests.swift's Rig, 1C Task 6's CoordinatorRig). */
class CoordinatorRig(
    val store: InMemorySecretStore,
    val vault: AccountVault,
    val relay: FakeRelayAccount,
    val identity: FakeIdentityProvider,
    val wiper: CountingWiper,
    val pendingSettings: MemoryKeyValueStore,
    val coordinator: AppCoordinator,
)

/**
 * The device name is "Phu's Pixel" and the wipers are `extraWipers + wiper`. The coordinator and its hubs run in
 * backgroundScope. Each hub connects through FakeMacFleet([macs]) with instantSleep, and its onUnauthorized calls the
 * coordinator's handleUnauthorized (MachineHubTests.swift's CoordinatorBox).
 */
@Suppress("RedundantSuspendModifier")
suspend fun TestScope.coordinatorRig(
    macs: List<FakeMac> = emptyList(),
    extraWipers: List<LocalDataWiping> = emptyList(),
    store: InMemorySecretStore = InMemorySecretStore(),
    pendingSettings: MemoryKeyValueStore = MemoryKeyValueStore(),
): CoordinatorRig {
    val vault = AccountVault(store, StandardTestDispatcher(testScheduler))
    val relay = FakeRelayAccount()
    val identity = FakeIdentityProvider()
    val wiper = CountingWiper()
    lateinit var coordinator: AppCoordinator
    coordinator = AppCoordinator(vault, relay, identity, "Phu's Pixel", extraWipers + wiper, pendingSettings, backgroundScope) {
        MachineHub(
            vault, relay, FakeMacFleet(macs) { vault.phoneKey() }, LatencyLog(), MemoryKeyValueStore(), backgroundScope,
            ManualClock(), instantSleep,
        ) { coordinator.handleUnauthorized() }
    }
    return CoordinatorRig(store, vault, relay, identity, wiper, pendingSettings, coordinator)
}
