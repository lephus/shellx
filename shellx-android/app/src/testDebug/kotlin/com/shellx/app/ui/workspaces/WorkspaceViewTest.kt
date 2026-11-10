package com.shellx.app.ui.workspaces

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import com.shellx.core.terminal.TerminalViewPhase
import android.content.Context
import android.net.Uri
import androidx.activity.compose.LocalActivityResultRegistryOwner
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.test.swipeRight
import com.shellx.app.screenshots.StillSpinner
import com.shellx.app.testing.FakeResultRegistry
import com.shellx.app.ui.components.LocalSpinner
import com.shellx.app.ui.composer.LocalAttachmentReader
import com.shellx.core.composer.AttachmentChecks
import com.shellx.link.core.AttachmentKind
import com.shellx.core.composer.AttachmentPick
import com.shellx.core.composer.AttachmentReader
import com.shellx.core.composer.OutgoingAttachment
import kotlinx.coroutines.CompletableDeferred
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.testing.WorkRig
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.workspaces.WorkspaceRef
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** The workspace screen over a signed-in rig: the Mac closes the pane shown, or the whole workspace. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w400dp-h900dp")
class WorkspaceViewTest {
    @get:Rule val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private var rig = WorkRig.make()
    private var backs = 0

    @After
    fun tearDown() = rig.close()

    private fun show() = compose.setContent {
        ShellXTheme {
            CompositionLocalProvider(LocalSpinner provides StillSpinner) {
                WorkspaceView(rig.scope, WorkspaceRef(rig.machineId, "ws-shellx"), open = {}, back = { backs++ })
            }
        }
    }

    private fun until(condition: () -> Boolean) = compose.waitUntil(10_000) {
        compose.waitForIdle()
        condition()
    }

    private fun shown(text: String): Boolean = compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    @Test
    fun thePaneClosedOnTheMacShowsTheNoticeThenItGoes() {
        show()
        until { tagged("workspace.chip.t-zsh") }
        // Frame by frame from here, so the 4 s count from the frame the notice shows (the chips slide meanwhile).
        compose.mainClock.autoAdvance = false
        rig.mac.upsertWorkspace(
            LinkWorkspace(
                "ws-shellx", "shellx-ios", 0, directory = "~/shellx/shellx-ios", branch = "feat/workspaces",
                terminals = listOf(LinkTerminal("t-claude", "claude", 0, selected = true, sessionId = "s1")),
            ),
        )
        val notice = context.getString(R.string.workspace_pane_closed_on_mac)
        compose.waitUntil(10_000) {
            compose.mainClock.advanceTimeByFrame()
            shown(notice)
        }
        compose.onNodeWithTag("workspace.chip.t-claude").assertIsSelected()
        compose.mainClock.advanceTimeBy(3_900)
        assertTrue("the notice stays 4 s", shown(notice))
        compose.mainClock.advanceTimeBy(200)
        assertTrue("the notice goes after 4 s", !shown(notice))
        compose.mainClock.autoAdvance = true
    }

    @Test
    fun aWorkspaceClosedOnTheMacLeavesWithTheListsNotice() {
        show()
        until { tagged("workspace.chip.t-zsh") }
        rig.mac.removeWorkspace("ws-shellx")
        until { backs == 1 }
        compose.waitForIdle()
        assertEquals(1, backs)
        assertEquals(context.getString(R.string.workspace_closed_on_mac), rig.scope.listNotice.current.value?.text)
    }

    /** The page's own lifecycle, as a navigation entry has it: the navigator's back works only while it is RESUMED. */
    private class Entry : LifecycleOwner {
        val registry = LifecycleRegistry(this).apply { currentState = Lifecycle.State.RESUMED }
        override val lifecycle: Lifecycle get() = registry
    }

    @Test
    fun aWorkspaceClosedWhileAnotherPageCoversItLeavesOnceTheUserIsBack() {
        val entry = compose.runOnIdle { Entry() }
        var covered by mutableStateOf(false)
        var dropped = 0
        compose.setContent {
            ShellXTheme {
                CompositionLocalProvider(LocalLifecycleOwner provides entry, LocalSpinner provides StillSpinner) {
                    if (!covered) {
                        WorkspaceView(rig.scope, WorkspaceRef(rig.machineId, "ws-shellx"), open = {}, back = {
                            if (entry.lifecycle.currentState == Lifecycle.State.RESUMED) backs++ else dropped++
                        })
                    }
                }
            }
        }
        until { tagged("workspace.chip.t-zsh") }
        // The "Needs you" page goes on top; the Mac closes the workspace meanwhile.
        compose.runOnIdle {
            entry.registry.currentState = Lifecycle.State.CREATED
            covered = true
        }
        rig.mac.removeWorkspace("ws-shellx")
        compose.waitForIdle()
        // Back: the page shows again while it slides in (STARTED), then is in front (RESUMED).
        compose.runOnIdle {
            covered = false
            entry.registry.currentState = Lifecycle.State.STARTED
        }
        compose.waitForIdle()
        assertEquals("the navigator would drop a back from a page not in front", 0, dropped)
        compose.runOnIdle { entry.registry.currentState = Lifecycle.State.RESUMED }
        until { backs == 1 }
        assertEquals(context.getString(R.string.workspace_closed_on_mac), rig.scope.listNotice.current.value?.text)
    }

    // Terminals (2C's additions to `WorkspaceViewTests.swift`; plan 3G ruling 8)

    @Test
    fun theShellPaneOpensItsTerminalAtThePhoneSize() {
        show()
        until { rig.mac.terminalViewOpens.firstOrNull()?.terminalId == "t-zsh" }
        assertTrue("${rig.mac.terminalViewOpens}", rig.mac.terminalViewOpens.first().cols >= 20)
        until { tagged("terminal.surface") }
        compose.onNodeWithTag("terminal.surface").assertIsDisplayed()
    }

    @Test
    fun viewAsTerminalOpensTheAgentsTerminal() {
        show()
        until { rig.mac.terminalViewOpens.any { it.terminalId == "t-zsh" } }
        compose.onNodeWithTag("workspace.chip.t-claude").performClick()
        compose.onNodeWithTag("workspace.menu").performClick()
        compose.onNodeWithText(context.getString(R.string.workspace_menu_view_as_terminal)).performClick()
        until { rig.mac.terminalViewOpens.any { it.terminalId == "t-claude" } }
        assertEquals("the shell's view closed first", listOf("t-zsh"), rig.mac.terminalViewCloses)
    }

    /** A Mac whose ShellX shows no terminals: the shell's page still says to update it, and there is no ＋. */
    @Test
    fun anOldMacStillShowsTheShellPlaceholder() {
        rig.close()
        rig = WorkRig.make(servesTerminalViews = false)
        show()
        until { tagged("workspace.shell.placeholder") }
        assertTrue(shown(context.getString(R.string.terminal_needs_update)))
        assertTrue("no new terminal on a Mac that takes none", !tagged("workspace.chip.add"))
        assertTrue(rig.mac.terminalViewOpens.isEmpty())
    }

    /** Names a photo as AttachmentPreparer does, once [gate] opens (a HEIC conversion or a cloud file takes seconds). */
    private class GatedReader(val gate: CompletableDeferred<Unit>) : AttachmentReader {
        override suspend fun read(pick: AttachmentPick, taken: List<String>): OutgoingAttachment {
            val name = AttachmentChecks.photoName("jpg", taken)
            gate.await()
            return OutgoingAttachment(kind = AttachmentKind.IMAGE, name = name, data = byteArrayOf(1, 2, 3))
        }
    }

    private fun tagged(tag: String): Boolean = compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()

    /** Final review m-3: a photo still being read when the user swipes to another pane is added once the read ends:
     *  the read belongs to the pane's holder, not to the composer shown. */
    @Test
    fun aPickStillBeingReadSurvivesASwipeToAnotherPane() {
        val gate = CompletableDeferred<Unit>()
        val registry = FakeResultRegistry().apply { answer = { listOf(Uri.parse("content://com.shellx.test.attachments/IMG_1")) } }
        compose.setContent {
            ShellXTheme {
                CompositionLocalProvider(
                    LocalAttachmentReader provides GatedReader(gate),
                    LocalActivityResultRegistryOwner provides registry.owner,
                    LocalSpinner provides StillSpinner,
                ) {
                    WorkspaceView(rig.scope, WorkspaceRef(rig.machineId, "ws-shellx"), open = {}, back = { backs++ })
                }
            }
        }
        until { tagged("workspace.chip.t-zsh") }
        compose.onNodeWithTag("workspace.chip.t-claude").performClick()
        until { tagged("composer.attach") }
        compose.onNodeWithTag("composer.attach").performClick()
        compose.onNodeWithText(context.getString(R.string.composer_attach_photos)).performClick()
        until { tagged("composer.attachments") }

        compose.onNodeWithTag("workspace.pager").performTouchInput { swipeLeft() }
        until { tagged("terminal.surface") && !tagged("composer.attach") }
        compose.onNodeWithTag("workspace.pager").performTouchInput { swipeRight() }
        until { tagged("composer.attach") }
        compose.runOnUiThread { gate.complete(Unit) }

        until { compose.onAllNodesWithContentDescription("photo-1.jpg").fetchSemanticsNodes().isNotEmpty() }
    }

    /**
     * A workspace screen replaced by another in the same page (3D's single-top navigation keeps the page's ViewModels)
     * lets the first one's terminal screen go and closes its view (final review m7); it opens again if that workspace
     * comes back.
     */
    @Test
    fun aReplacedWorkspaceScreenLetsItsTerminalGo() {
        var ref by mutableStateOf(WorkspaceRef(rig.machineId, "ws-shellx"))
        var owner: ViewModelStoreOwner? = null
        compose.setContent {
            ShellXTheme {
                CompositionLocalProvider(LocalSpinner provides StillSpinner) {
                    owner = LocalViewModelStoreOwner.current
                    WorkspaceView(rig.scope, ref, open = {}, back = {})
                }
            }
        }
        until { tagged("terminal.surface") }
        val first = ViewModelProvider(checkNotNull(owner))["workspace/${rig.machineId}/ws-shellx", WorkspaceScreenHolder::class.java]
        until { first.terminal.phase == TerminalViewPhase.Live && first.terminal.screen.cols > 0 }
        ref = WorkspaceRef(rig.machineId, "ws-web")
        until { tagged("workspace.chip.t-web") }
        until { first.terminal.terminalId == null }
        assertEquals(0, first.terminal.screen.cols)
        ref = WorkspaceRef(rig.machineId, "ws-shellx")
        until { first.terminal.terminalId == "t-zsh" && first.terminal.phase == TerminalViewPhase.Live }
    }
}
