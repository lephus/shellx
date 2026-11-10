package com.shellx.core.demo

import com.shellx.core.account.AppPhase
import com.shellx.core.account.SignInException
import com.shellx.core.agent.AgentSendResult
import com.shellx.core.agent.AgentThreadModel
import com.shellx.core.agent.ChatThread
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.SessionRef
import com.shellx.core.pairing.PairingModel
import com.shellx.core.storage.StoreDocument
import com.shellx.core.testing.ManualClock
import com.shellx.core.testing.assertSameCase
import com.shellx.core.testing.chatEntry
import com.shellx.core.terminal.TerminalViewModel
import com.shellx.core.terminal.TerminalViewPhase
import com.shellx.core.testing.eventually
import com.shellx.link.core.ChatEntryRole
import com.shellx.link.core.ChatInterruptOutcome
import com.shellx.link.core.ChatSendOutcome
import com.shellx.link.core.TerminalScreen
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.io.TempDir

/** The demo route's wiring ("Try without an account"): signed in to a fake account, paired with "Mac giả", with "Mac giả
 *  2" pairable from its code, and never touching the network or the real account's data. */
class DemoEnvironmentTest {
    private fun TestScope.environment(directory: File, runsScript: Boolean): DemoEnvironment = DemoEnvironment(
        backgroundScope, ManualClock(), directory, StandardTestDispatcher(testScheduler), approvalDelay = Duration.ZERO,
        runsScript = runsScript,
    )

    @Test fun demoIsSignedInWithFakeMacOnlineAndPairsSecondMacFromPastedCode(@TempDir root: File) { runTest {
        val env = environment(File(root, "ShellXDemo"), runsScript = false)

        env.prepare()
        env.coordinator.launch()

        assertEquals(AppPhase.SignedIn("demo@shellx.pro"), env.coordinator.phase.value)
        val hub = assertNotNull(env.coordinator.hub.value)
        val online = eventually { hub.machines.firstOrNull()?.state == MachineLinkState.Online }
        assertTrue(online, "${hub.machines.map { it.state }}")
        assertEquals(listOf(DemoEnvironment.FIRST_NAME), hub.machines.map { it.name })

        val pairing = PairingModel(hub, env.relay, env.vault, hub.scope)
        pairing.begin(env.secondPairingCode())
        assertEquals(PairingModel.Step.Confirm(DemoEnvironment.SECOND_NAME), pairing.step.value)
        pairing.confirm()

        assertEquals(PairingModel.Step.Paired(DemoEnvironment.SECOND_NAME), pairing.step.value)
        val both = eventually { hub.machines.size == 2 && hub.machines.all { it.state == MachineLinkState.Online } }
        assertTrue(both, "${hub.machines.map { it.state }}")

        // The fake relay lists the new Mac, so a refresh keeps both.
        hub.refreshGrants()
        assertEquals(listOf<MachineLinkState>(MachineLinkState.Online, MachineLinkState.Online), hub.machines.map { it.state })
    } }

    @Test fun demoMacListsTheFourWorkspacesOfTheDesign(@TempDir root: File) { runTest {
        val env = environment(File(root, "ShellXDemo"), runsScript = true)
        env.prepare()
        env.coordinator.launch()
        val hub = assertNotNull(env.coordinator.hub.value)
        val id = assertNotNull(hub.machines.firstOrNull()?.id)

        val listed = eventually { hub.workspaceRows(id).size == 4 }

        assertTrue(listed, "${hub.workspaceRows(id).map { it.title }}")
        assertEquals(listOf("shellx-ios", "relay", "web", "notes"), hub.workspaceRows(id).map { it.title })
        assertTrue(hub.supportsWorkspaceControl(id))
        // The script's two working sessions are in `shellx-ios` and `web`; its idle second "Pairing sheet" is outside
        // every workspace (the ended one is on the Ended page).
        val others = eventually { hub.otherSessions(id).map { it.session.sessionId } == listOf("demo-shellx-2") }
        assertTrue(others, "${hub.otherSessions(id).map { it.session.sessionId }}")
    } }

    @Test fun demoAgentScreenShowsTheScriptedChatAndStops(@TempDir root: File) { runTest {
        val env = environment(File(root, "ShellXDemo"), runsScript = true)
        env.prepare()
        env.coordinator.launch()
        val hub = assertNotNull(env.coordinator.hub.value)
        val listed = eventually { hub.liveSessions.size == 3 }
        assertTrue(listed, "${hub.machines.map { it.state }}")
        val session = assertNotNull(hub.liveSessions.firstOrNull { it.session.workspaceTitle == "shellx" })

        // What tapping its row opens.
        val model = AgentThreadModel(session.ref, hub, env.history, hub.scope)
        model.open()

        val kinds = model.thread.entries.map { it.kind.wire }.toSet()
        assertTrue(kinds.containsAll(setOf("prose", "thought", "tool_use", "status")), "$kinds")
        assertTrue(model.thread.entries.any { it.truncated == true }, "one entry is cut")
        assertEquals(ChatEntryRole.USER, model.thread.entries.firstOrNull()?.role)
        val sent = model.send("Chạy lại test giúp mình", viaVoice = false)
        assertEquals(AgentSendResult.Sent(ChatSendOutcome.SUBMITTED), sent)
        // The script leaves shellx working (its third step switched it back on).
        assertTrue(model.canStop)
        val stopped = model.stop(hard = false)
        assertEquals(ChatInterruptOutcome.SENT, stopped)
        model.close().join()
    } }

    /** The demo Mac's terminals show their fixtures (DemoCompositionTests.swift, `testDemoMacShowsItsTerminals`). */
    @Test fun demoMacShowsItsTerminals(@TempDir root: File) { runTest {
        val env = environment(File(root, "ShellXDemo"), runsScript = true)
        env.prepare()
        env.coordinator.launch()
        val hub = assertNotNull(env.coordinator.hub.value)
        val id = env.first.machine.machineId
        val ready = eventually {
            hub.supportsTerminalView(id) && hub.supportsTerminalCreate(id) && hub.workspaceRows(id).size == 4
        }
        assertTrue(ready)

        val model = TerminalViewModel(id, hub, hub.scope)
        backgroundScope.launch { model.run() }
        model.setPhoneGrid(50, 40)
        model.show("demo-shellx-t2")
        val expected = TerminalScreen().apply { apply(DemoTerminalScreens.SHELL.snapshot) }
        val shell = eventually { model.phase == TerminalViewPhase.Live && model.screen.screenText() == expected.screenText() }
        assertTrue(shell, "${model.phase} ${model.screen.screenText().take(3)}")

        model.show("demo-notes-t1")
        val wide = eventually { model.phase == TerminalViewPhase.Live && "中文：终端测试" in model.screen.screenText() }
        assertTrue(wide, "${model.phase}")
    } }

    @Test fun demoSignOutWipesOnlyTheDemoStores(@TempDir root: File) { runTest {
        val real = File(root, "ShellX").apply { mkdirs(); File(this, "keep.json").writeText("{}") }
        val demoDir = File(root, "ShellXDemo")
        val env = DemoEnvironment(backgroundScope, ManualClock(), demoDir, StandardTestDispatcher(testScheduler),
            approvalDelay = Duration.ZERO, runsScript = false)
        env.prepare(); env.coordinator.launch()
        env.history.writer().save(ChatThread(listOf(chatEntry(1))), ChatThread.CODEC,
            StoreDocument.Thread(SessionRef(env.first.machine.machineId, "s1", "claude", "shellx")))
        assertTrue(demoDir.exists())
        env.coordinator.signOut()
        assertEquals(AppPhase.SignedOut(false), env.coordinator.phase.value)
        assertTrue(File(real, "keep.json").isFile)                    // the real history is untouched
        assertFalse(demoDir.exists())                                 // the demo's own history was wiped
        // The demo relay refuses every account call (DemoRelay.REFUSAL): signing in again never leaves the process.
        assertSameCase(SignInException.Server("demo"), assertFails { env.coordinator.signInWithGoogle() })
    } }

    /** Review 4 M-3: a first `prepare()` cancelled during its vault writes (a configuration change in 3D's effect)
     *  leaves nothing half done: the next call seeds the demo account. */
    @Test fun aCancelledPrepareIsDoneAgainByTheNextCall(@TempDir root: File) { runTest {
        val env = environment(File(root, "ShellXDemo"), runsScript = false)
        val first = backgroundScope.launch(start = CoroutineStart.UNDISPATCHED) { env.prepare() }
        first.cancel()
        first.join()
        runCurrent()

        env.prepare()
        env.coordinator.launch()

        assertEquals(AppPhase.SignedIn(DemoEnvironment.EMAIL), env.coordinator.phase.value)
        val hub = assertNotNull(env.coordinator.hub.value)
        assertEquals(listOf(DemoEnvironment.FIRST_NAME), hub.machines.map { it.name })
    } }
}
