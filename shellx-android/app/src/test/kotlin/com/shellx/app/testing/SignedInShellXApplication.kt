package com.shellx.app.testing

import com.shellx.app.AppEnvironment
import com.shellx.app.BuildConfig
import com.shellx.app.RelayBundle
import com.shellx.core.account.AccountVault
import com.shellx.core.account.StoredSession
import com.shellx.core.demo.DemoSecretStore
import com.shellx.core.demo.FakeMac
import com.shellx.core.demo.FakeMacFleet
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/**
 * [TestShellXApplication] signed in over fakes: the vault holds `StoredSession("u1", "d1", "tok-1", "phu@example.com")`
 * and one Mac, [mac] ("MacBook Pro", workspace `ws-1` "shellx-ios"); the relay is [relay] and the Mac connector a
 * FakeMacFleet. ShellXApplication's own wiring (the platform's pieces, the push hooks, the lifecycle) is unchanged, and
 * nothing reaches a network.
 */
class SignedInShellXApplication : TestShellXApplication() {
    private val macScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    val mac: FakeMac by lazy {
        FakeMac("MacBook Pro", macScope).apply {
            setWorkspaces(listOf(LinkWorkspace("ws-1", "shellx-ios", 0, terminals = listOf(LinkTerminal("t1", "zsh", 0, selected = true)))))
        }
    }

    val relay: ScriptedRelay by lazy { ScriptedRelay(listOf(mac.machine)) }

    override suspend fun environment(): AppEnvironment {
        val secrets = DemoSecretStore()
        val vault = AccountVault(secrets, Dispatchers.IO)
        vault.setSession(StoredSession("u1", "d1", "tok-1", "phu@example.com"))
        vault.setMachines(listOf(mac.machine), "u1")
        return testEnvironment(File(noBackupFilesDir, "signed-in"), Dispatchers.IO, secrets, debugBuild = BuildConfig.DEBUG)
    }

    override fun relays(environment: AppEnvironment): (AccountVault) -> RelayBundle =
        { vault -> RelayBundle(relay, FakeMacFleet(listOf(mac)) { vault.phoneKey() }) }
}
