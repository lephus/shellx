package com.shellx.app.testing

import com.shellx.app.AppEnvironment
import com.shellx.core.account.IdentityProviding
import com.shellx.core.account.SecretStore
import com.shellx.core.demo.DemoSecretStore
import com.shellx.core.platform.KeyValueStore
import com.shellx.core.platform.MemoryKeyValueStore
import java.io.File
import kotlinx.coroutines.CoroutineDispatcher

/** An environment over fakes: history in `root/ShellX`, the demo's in `root/ShellXDemo`, device "Test Phone",
 *  version "1.0.0" (100), relay "https://relay.example.test". */
fun testEnvironment(
    root: File,
    io: CoroutineDispatcher,
    secrets: SecretStore = DemoSecretStore(),
    settings: KeyValueStore = MemoryKeyValueStore(),
    network: TestNetworkMonitor = TestNetworkMonitor(),
    clock: ManualClock = ManualClock(),
    identity: IdentityProviding = TestIdentity(),
    debugBuild: Boolean = true,
): AppEnvironment = AppEnvironment(
    secrets = secrets,
    settings = settings,
    network = network,
    clock = clock,
    identity = identity,
    io = io,
    historyDirectory = File(root, "ShellX"),
    demoHistoryDirectory = File(root, "ShellXDemo"),
    deviceName = "Test Phone",
    appVersion = "1.0.0",
    versionCode = 100,
    debugBuild = debugBuild,
    apiBase = "https://relay.example.test",
)
