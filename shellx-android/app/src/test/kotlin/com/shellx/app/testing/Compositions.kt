package com.shellx.app.testing

import com.shellx.app.AppComposition
import com.shellx.app.RelayBundle
import com.shellx.core.account.AccountVault
import com.shellx.core.account.SecretStore
import com.shellx.core.account.StoredSession
import com.shellx.core.demo.DemoEnvironment
import com.shellx.core.demo.DemoSecretStore
import com.shellx.core.demo.FakeMac
import com.shellx.core.demo.FakeMacFleet
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.link.MachineHub
import com.shellx.core.platform.Clock
import com.shellx.core.platform.KeyValueStore
import com.shellx.core.platform.MemoryKeyValueStore
import com.shellx.core.update.UpdateChecker
import com.shellx.core.voice.VoiceService
import java.io.File
import kotlin.time.Duration
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope

/** An [AppComposition] over fakes, with the fakes the test drives. [demoEnvironments] are the demo runs, in order. */
class TestComposition(
    val composition: AppComposition,
    val relay: ScriptedRelay,
    val identity: TestIdentity,
    val network: TestNetworkMonitor,
    val clock: ManualClock,
    val settings: KeyValueStore,
    val secrets: SecretStore,
    val demoEnvironments: List<DemoEnvironment>,
)

private const val EMAIL = "phu@example.com"

private suspend fun seed(secrets: SecretStore, io: CoroutineDispatcher, macs: List<FakeMac>) {
    val vault = AccountVault(secrets, io)
    vault.setSession(StoredSession("u1", "d1", "tok-1", EMAIL))
    vault.setMachines(macs.map { it.machine }, "u1")
}

private fun build(
    root: File,
    appScope: CoroutineScope,
    io: CoroutineDispatcher,
    macs: List<FakeMac>,
    pairable: List<FakeMac>,
    secrets: SecretStore,
    settings: KeyValueStore,
    clock: ManualClock,
    debugBuild: Boolean,
    updateChecker: UpdateChecker?,
    makeVoice: ((MachineHub, LatencyLog, KeyValueStore, Clock) -> VoiceService)?,
): TestComposition {
    val identity = TestIdentity()
    val network = TestNetworkMonitor()
    val relay = ScriptedRelay(macs.map { it.machine }, pairable.map { it.machine.machineId }.toSet())
    val environment = testEnvironment(root, io, secrets, settings, network, clock, identity, debugBuild)
    val demoEnvironments = mutableListOf<DemoEnvironment>()
    val composition = AppComposition(
        environment = environment,
        appScope = appScope,
        updateChecker = updateChecker,
        makeVoice = makeVoice,
        relays = { vault -> RelayBundle(relay, FakeMacFleet(macs + pairable) { vault.phoneKey() }) },
        demoEnvironment = { scope ->
            DemoEnvironment(
                scope, clock, environment.demoHistoryDirectory, io, approvalDelay = Duration.ZERO, runsScript = false,
            ).also { synchronized(demoEnvironments) { demoEnvironments += it } }
        },
    )
    return TestComposition(composition, relay, identity, network, clock, settings, secrets, demoEnvironments)
}

/**
 * An [AppComposition] over fakes in `backgroundScope` (io = StandardTestDispatcher(testScheduler)). [signedIn]: the
 * vault holds `StoredSession("u1", "d1", "tok-1", "phu@example.com")` and [macs] owned by "u1". The connector is
 * `FakeMacFleet(macs + pairable)`. The demo's environment uses `approvalDelay = Duration.ZERO` and `runsScript = false`.
 * Nothing is launched.
 */
suspend fun TestScope.testComposition(
    root: File,
    macs: List<FakeMac> = emptyList(),
    signedIn: Boolean = true,
    pairable: List<FakeMac> = emptyList(),
    secrets: SecretStore = DemoSecretStore(),
    debugBuild: Boolean = true,
    makeVoice: ((MachineHub, LatencyLog, KeyValueStore, Clock) -> VoiceService)? = null,
    settings: KeyValueStore = MemoryKeyValueStore(),
    updateChecker: UpdateChecker? = null,
): TestComposition {
    val io = StandardTestDispatcher(testScheduler)
    if (signedIn) seed(secrets, io, macs)
    return build(root, backgroundScope, io, macs, pairable, secrets, settings, ManualClock(), debugBuild, updateChecker, makeVoice)
}

/**
 * The same over the real main thread (Robolectric): [appScope] is the caller's
 * `CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)`, io is Dispatchers.IO, and the FakeMacs are built by
 * the caller on that scope. For Compose tests that wait with `composeRule.waitUntil`.
 */
fun mainComposition(
    root: File,
    macs: List<FakeMac>,
    appScope: CoroutineScope,
    signedIn: Boolean = true,
    pairable: List<FakeMac> = emptyList(),
    clock: ManualClock = ManualClock(),
): TestComposition {
    val secrets = DemoSecretStore()
    if (signedIn) runBlocking { seed(secrets, Dispatchers.IO, macs) }
    return build(root, appScope, Dispatchers.IO, macs, pairable, secrets, MemoryKeyValueStore(), clock, true, null, null)
}
