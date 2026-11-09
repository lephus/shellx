package com.shellx.core.demo

import com.shellx.core.account.AccountVault
import com.shellx.core.account.AppCoordinator
import com.shellx.core.account.StoredSession
import com.shellx.core.account.UnavailableIdentityProvider
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.link.MachineHub
import com.shellx.core.platform.Clock
import com.shellx.core.platform.KeyValueStore
import com.shellx.core.platform.MemoryKeyValueStore
import com.shellx.core.storage.ConversationStore
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import java.io.File
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay

/**
 * Everything the demo route shows ("Try without an account", in every build; the iPhone's DemoComposition): the app
 * runs without a relay or the Keystore, signed in to a fake account and paired with "Mac giả", an in-process
 * [FakeMac] running [DemoScript]. A second fake Mac, "Mac giả 2", is not paired: 3D puts [secondPairingCode] on the
 * clipboard, so "Paste pairing code" pairs it; the demo relay approves after `approvalDelay`.
 *
 * The parts: a vault over [DemoSecretStore], the demo's own [MemoryKeyValueStore] (the real app's default Mac and
 * "local wipe pending" marker are not the demo's), [DemoRelay], a [ConversationStore] over `historyDirectory` (3D
 * passes `File(context.noBackupFilesDir, "ShellXDemo")`, apart from a real run's history), and an [AppCoordinator]
 * with [UnavailableIdentityProvider], device name "Android" and wipers [history], whose hubs connect through
 * `FakeMacFleet([first, second])` with `onUnauthorized = {}`. Nothing here has a network path, and nothing touches
 * the real account's stores.
 *
 * The fake Macs keep fixed ids, so the demo's chat copies survive a relaunch. Main-confined: everything runs in
 * `scope`, its stores on `io`. `sleep` paces the script, the hubs' waits and the relay's approval.
 */
class DemoEnvironment(
    private val scope: CoroutineScope,
    clock: Clock,
    historyDirectory: File,
    io: CoroutineDispatcher,
    approvalDelay: Duration = 2.seconds,
    private val runsScript: Boolean = true,
    private val sleep: suspend (Duration) -> Unit = { delay(it) },
) {
    val vault: AccountVault = AccountVault(DemoSecretStore(), io)
    val settings: KeyValueStore = MemoryKeyValueStore()
    val first: FakeMac = FakeMac(FIRST_NAME, scope, id = "demo-1", nowMs = clock::nowMs)
    val second: FakeMac = FakeMac(SECOND_NAME, scope, id = "demo-2", nowMs = clock::nowMs)
    val relay: DemoRelay = DemoRelay(listOf(first.machine), setOf(second.machine.machineId), approvalDelay, sleep)
    val history: ConversationStore = ConversationStore(historyDirectory, io, clock)
    val latency: LatencyLog = LatencyLog()
    private val connector = FakeMacFleet(listOf(first, second)) { vault.phoneKey() }
    val coordinator: AppCoordinator = AppCoordinator(
        vault, relay, UnavailableIdentityProvider(), DEVICE_NAME, listOf(history), settings, scope,
    ) {
        MachineHub(vault, relay, connector, latency, settings, scope, clock, sleep) {}
    }
    val script: DemoScript = DemoScript(first, clock::nowMs)

    private var prepared = false
    private var playing: Job? = null

    /**
     * Once it succeeded (seeding again would drop a Mac paired since): stores `StoredSession("demo", "demo-phone", "demo-token",
     * EMAIL)` and `[first.machine]` owned by "demo", then, with `runsScript`, starts the script and gives the first Mac
     * [WORKSPACES]. The caller then calls `coordinator.launch()`.
     */
    suspend fun prepare() {
        if (prepared) return
        vault.setSession(StoredSession("demo", "demo-phone", "demo-token", EMAIL))
        vault.setMachines(listOf(first.machine), "demo")
        // Only once the writes are done: a first call cancelled meanwhile (3D's effect, a configuration change) is
        // done again by the next one (review 4 M-3). Nothing below suspends.
        prepared = true
        if (runsScript) {
            playing = script.start(scope, sleep)
            // The Mac's sidebar as the design shows it, over the script's two sessions.
            first.setWorkspaces(WORKSPACES)
        }
    }

    /** The second Mac's code: 3D puts it on the clipboard so "Paste pairing code" pairs it. */
    fun secondPairingCode(): String = second.pairingCode()

    /** "Demo · Exit": stops the script and the hub. The demo history stays in its own directory (the iPhone keeps it
     *  too). */
    suspend fun exit() {
        playing?.cancel()
        playing = null
        coordinator.hub.value?.stopAll()
    }

    companion object {
        const val FIRST_NAME = "Mac giả"
        const val SECOND_NAME = "Mac giả 2"
        const val EMAIL = "demo@shellx.pro"

        /** The demo account's device name. */
        private const val DEVICE_NAME = "Android"

        /** "Mac giả" has four workspaces: `shellx-ios` and `web` hold the script's two Claude Code sessions (their ids
         *  are the ones the sessions and requests carry), `relay` a dev server and `notes` a shell. */
        val WORKSPACES: List<LinkWorkspace> = listOf(
            LinkWorkspace(
                workspaceId = "ws-shellx", title = "shellx-ios", order = 0, directory = "~/shellx/shellx-ios",
                branch = "feat/workspaces",
                terminals = listOf(
                    LinkTerminal(terminalId = "demo-shellx-t1", title = "claude", order = 0, selected = true, sessionId = "demo-shellx"),
                    LinkTerminal(terminalId = "demo-shellx-t2", title = "zsh", order = 1, selected = false),
                ),
            ),
            LinkWorkspace(
                workspaceId = "ws-relay", title = "relay", order = 1, directory = "~/shellx/relay", branch = "main",
                ports = listOf(8787),
                terminals = listOf(LinkTerminal(terminalId = "demo-relay-t1", title = "npm", order = 0, selected = true)),
            ),
            LinkWorkspace(
                workspaceId = "ws-web", title = "web", order = 2, directory = "~/shellx/web", branch = "develop",
                ports = listOf(3000),
                terminals = listOf(
                    LinkTerminal(terminalId = "demo-web-t1", title = "claude", order = 0, selected = true, sessionId = "demo-web"),
                ),
            ),
            LinkWorkspace(
                workspaceId = "ws-notes", title = "notes", order = 3, directory = "~",
                terminals = listOf(LinkTerminal(terminalId = "demo-notes-t1", title = "zsh", order = 0, selected = true)),
            ),
        )
    }
}
