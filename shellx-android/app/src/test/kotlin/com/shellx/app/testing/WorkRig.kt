package com.shellx.app.testing

import com.shellx.app.AppComposition
import com.shellx.app.LaunchMark
import com.shellx.app.SignedInScope
import com.shellx.core.account.AccountVault
import com.shellx.core.account.StoredSession
import com.shellx.core.demo.DemoRelay
import com.shellx.core.demo.DemoSecretStore
import com.shellx.core.demo.FakeMac
import com.shellx.core.demo.FakeMacFleet
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.link.MachineHub
import com.shellx.core.platform.MemoryKeyValueStore
import com.shellx.core.storage.ConversationStore
import com.shellx.core.voice.VoiceService
import com.shellx.core.workspaces.WorkspaceRef
import com.shellx.core.workspaces.WorkspaceScreenModel
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.ChatEntry
import com.shellx.link.core.ChatEntryKind
import com.shellx.link.core.ChatEntryRole
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import java.io.File
import java.nio.file.Files
import kotlin.time.Duration
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

/**
 * Port of `ShellXTests/Support/WorkspaceRig.swift`: a signed-in scope, made as [AppComposition.makeScope] makes it,
 * over a hub connected to a fake Mac with two workspaces and one Claude Code session. Everything runs on
 * `Dispatchers.Main.immediate` (the Robolectric main looper) on real time: wait with [eventually].
 *
 * `ws-shellx` has the agent `claude` (session `s1`, working) and a shell `zsh` (the Mac's selection); `ws-web` has one
 * shell.
 */
class WorkRig(
    val scope: SignedInScope,
    val mac: FakeMac,
    val settings: MemoryKeyValueStore,
    private val main: CoroutineScope,
    private val historyDirectory: File,
) {
    val hub: MachineHub get() = scope.hub

    val machineId: String get() = mac.machine.machineId

    /** The model of the workspace `ws-<name>` (`new` is one the Mac does not list). */
    fun workspaceModel(name: String = "shellx"): WorkspaceScreenModel = WorkspaceScreenModel(WorkspaceRef(machineId, "ws-$name"), hub)

    /** Stops the hub, cancels the rig's scope and deletes the history folder. */
    fun close() {
        val stopped = main.launch { hub.stopAll() }
        eventually { stopped.isCompleted }
        main.cancel()
        historyDirectory.deleteRecursively()
    }

    companion object {
        fun make(
            acceptsAgentClose: Boolean = true,
            acceptsTerminalClose: Boolean = true,
            acceptsAttachments: Boolean = true,
            voice: VoiceService? = null,
        ): WorkRig {
            val main = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
            val mac = FakeMac(
                "MacBook Pro", main, acceptsAttachments = acceptsAttachments, acceptsAgentClose = acceptsAgentClose,
                acceptsTerminalClose = acceptsTerminalClose,
            )
            mac.setWorkspaces(
                listOf(
                    LinkWorkspace(
                        "ws-shellx", "shellx-ios", 0, directory = "~/shellx/shellx-ios", branch = "feat/workspaces",
                        terminals = listOf(
                            LinkTerminal("t-claude", "claude", 0, selected = false, sessionId = "s1"),
                            LinkTerminal("t-zsh", "zsh", 1, selected = true),
                        ),
                    ),
                    LinkWorkspace("ws-web", "web", 1, terminals = listOf(LinkTerminal("t-web", "zsh", 0, selected = true))),
                ),
            )
            val now = TestClock.nowMs()
            mac.upsertSession(
                AgentSession(
                    "s1", "claude", "ws-shellx", "shellx-ios", state = AgentState.WORKING, stateSinceMs = now - 240_000,
                    lastActivityMs = now,
                ),
            )
            mac.setHistory(
                "s1",
                listOf(
                    ChatEntry(
                        "e1", 1, 1, ChatEntryRole.USER, ChatEntryKind.PROSE, "thêm danh sách workspace vào màn chính",
                        tsMs = 1_700_000_000_000,
                    ),
                    ChatEntry(
                        "e2", 1, 2, ChatEntryRole.AGENT, ChatEntryKind.PROSE,
                        "Mình sẽ thêm **WorkspaceList** và sửa màn chính.", tsMs = 1_700_000_001_000,
                    ),
                ),
            )
            val vault = AccountVault(DemoSecretStore(), Dispatchers.IO)
            runBlocking {
                vault.setSession(StoredSession("u1", "d1", "tok-1", "a@b.c"))
                vault.setMachines(listOf(mac.machine), "u1")
            }
            val settings = MemoryKeyValueStore()
            val relay = DemoRelay(listOf(mac.machine), emptySet(), Duration.ZERO)
            val latency = LatencyLog()
            val hub = MachineHub(vault, relay, FakeMacFleet(listOf(mac)) { vault.phoneKey() }, latency, settings, main, TestClock) {}
            val directory = Files.createTempDirectory("work-rig").toFile()
            val history = ConversationStore(directory, Dispatchers.IO, TestClock)
            val scope = AppComposition.makeScope(
                hub, relay, vault, history, latency, LaunchMark(latency, TestClock), settings, TestClock, voice,
            )
            scope.start()
            main.launch { hub.start() }
            val id = mac.machine.machineId
            check(eventually { hub.workspaceRows(id).size == 2 && hub.liveSessions.size == 1 }) { "the rig's Mac did not come online" }
            return WorkRig(scope, mac, settings, main, directory)
        }
    }
}
