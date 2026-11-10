package com.shellx.app.ui.workspaces

import android.content.res.Resources
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.shellx.app.R
import com.shellx.app.SignedInScope
import com.shellx.app.ui.agent.AgentNotice
import com.shellx.app.ui.agent.AgentView
import com.shellx.app.ui.components.LocalTerminalKeyboard
import com.shellx.app.ui.components.rememberNowMs
import com.shellx.app.voice.LocalVoice
import com.shellx.app.ui.terminal.TerminalPane
import com.shellx.core.terminal.TerminalViewModel
import com.shellx.core.workspaces.WorkspacePane
import com.shellx.core.workspaces.WorkspaceRef
import com.shellx.core.workspaces.WorkspaceScreenModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/**
 * One workspace screen's models and what it holds across configuration changes: the last alert, whether the user closed
 * the workspace here, the notice over the pages and the `shownPaneClosed` count it last answered. [terminal] is the one
 * terminal model of every terminal page of the screen; it stops for good when the screen goes ([onCleared]).
 * Main-confined.
 */
class WorkspaceScreenHolder(val model: WorkspaceScreenModel, val terminal: TerminalViewModel) : ViewModel() {
    var alert: WorkspaceAlert? by mutableStateOf(null)

    /** The user confirmed closing the workspace here: its leaving needs no word of explanation. */
    var closedHere: Boolean = false
    var notice: AgentNotice? by mutableStateOf(null)

    /** The `shownPaneClosed` count the screen last said something about. */
    var paneClosedSeen: Int by mutableIntStateOf(model.shownPaneClosed)

    /** The terminal view closes on the Mac (its close still goes out). */
    override fun onCleared() {
        terminal.close()
    }
}

/**
 * One workspace of a Mac (`WorkspaceView.swift`): [WorkspaceScreen] fed by 3C's [WorkspaceScreenModel] and the hub.
 * An agent's chip shows the agent screen as its pane ([AgentView], embedded); a shell's chip, or an agent's chip shown
 * as its terminal, shows the Mac's terminal ([TerminalPane]). One [TerminalViewModel] serves every page and shows the
 * terminal of the chip shown (`WorkspaceScreenModel.terminalShown`), never a neighbour the pager keeps alive. It runs
 * while the screen is STARTED: the background, another screen over it or a rotation closes the view on the Mac, and the
 * next start opens it again (ledger A-35). Typing into a page settles the screen on its chip. The commands in `⋮` and ＋
 * are the hub's ([WorkspaceScreenActions]).
 *
 * When the pane shown is closed on the Mac, the next chip shows and a short line says why ([paneClosedNotice]). The
 * screen leaves by itself when its workspace is closed on the Mac: it goes [back], and the list says so in a short line
 * ([leavingNotice]); a tab or a workspace the user closed here goes the same way without either line. When the Mac is
 * removed from this phone it goes back without a word. A workspace the Mac has not listed yet shows a spinner; one that
 * does not come says it is not found.
 */
@Composable
fun WorkspaceView(scope: SignedInScope, ref: WorkspaceRef, open: (String) -> Unit, back: () -> Unit) {
    val holder: WorkspaceScreenHolder = viewModel(key = "workspace/${ref.machineId}/${ref.workspaceId}") {
        WorkspaceScreenHolder(WorkspaceScreenModel(ref, scope.hub), TerminalViewModel(ref.machineId, scope.hub, scope.hub.scope))
    }
    val model = holder.model
    val terminal = holder.terminal
    val hub = scope.hub
    val res = LocalContext.current.resources
    // Read so that the model's and the hub's getters are read again when they change.
    model.state.collectAsStateWithLifecycle().value
    hub.state.collectAsStateWithLifecycle().value
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(model, lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            launch { terminal.run() }
            model.run()
        }
    }
    val terminalShown = model.terminalShown
    LaunchedEffect(terminalShown) { terminal.show(terminalShown) }
    // Whatever finished while the user was here, the user saw.
    DisposableEffect(hub, ref) { onDispose { hub.markSeen(ref) } }

    val leave by rememberUpdatedState(back)
    val phase = model.phase
    LaunchedEffect(phase, lifecycle) {
        val gone = phase == WorkspaceScreenModel.Phase.DISMISSED || phase == WorkspaceScreenModel.Phase.MACHINE_REMOVED
        if (!gone) return@LaunchedEffect
        // The navigator goes back only from the page in front: a page still sliding back in (STARTED, after the page
        // that covered it went) leaves once it is there.
        lifecycle.currentStateFlow.first { it.isAtLeast(Lifecycle.State.RESUMED) }
        if (phase == WorkspaceScreenModel.Phase.DISMISSED) {
            WorkspaceView.leavingNotice(holder.closedHere || model.lastTabClosedHere, res)?.let(scope.listNotice::show)
        }
        leave()
    }
    val closedCount = model.shownPaneClosed
    LaunchedEffect(closedCount) {
        if (closedCount > holder.paneClosedSeen) holder.notice = AgentNotice(WorkspaceView.paneClosedNotice(res))
        holder.paneClosedSeen = closedCount
    }
    val notice = holder.notice
    LaunchedEffect(notice?.id) {
        if (notice == null) return@LaunchedEffect
        delay(AgentView.NOTICE_DURATION)
        if (holder.notice?.id == notice.id) holder.notice = null
    }

    when (phase) {
        WorkspaceScreenModel.Phase.SHOWING -> {
            val activity = LocalVoice.current?.activity
            val voiceLocksPaging by (activity?.anyActive ?: remember { MutableStateFlow(false) }).collectAsStateWithLifecycle()
            var terminalLocksPaging by remember { mutableStateOf(false) }
            var terminalHoldsKeyboard by remember { mutableStateOf(false) }
            // The window's bars above the screen (the demo banner) step aside with the screen's own (ledger A-36).
            val windowKeyboard = LocalTerminalKeyboard.current
            val actions = remember(model) {
                WorkspaceScreenActions.make(
                    scope, model,
                    alert = {
                        holder.closedHere = false
                        holder.alert = it
                    },
                    closing = { holder.closedHere = true },
                )
            }
            WorkspaceScreen(
                title = model.workspace?.title.orEmpty(),
                branch = model.workspace?.branch,
                panes = model.panes,
                selected = model.selectedTerminalId,
                nowMs = rememberNowMs(scope.clock),
                canControl = model.canControl,
                canCloseTab = WorkspaceListActions.canCloseTab(ref.machineId, hub),
                canCreateTerminal = hub.supportsTerminalCreate(ref.machineId),
                canViewTerminals = hub.supportsTerminalView(ref.machineId),
                shownAsTerminal = model.shownAsTerminal,
                creatingTerminal = model.creatingTerminal,
                terminalHoldsKeyboard = terminalHoldsKeyboard,
                pagingLocked = voiceLocksPaging || terminalLocksPaging,
                notice = notice,
                alert = holder.alert,
                onAlertDismiss = { holder.alert = null },
                actions = actions,
                back = back,
            ) { pane, shown ->
                val terminalPage = @Composable { page: WorkspacePane, pageShown: Boolean ->
                    TerminalPane(
                        terminal, page.id, PaneChips.label(page, res), pageShown,
                        locksPaging = { terminalLocksPaging = it },
                        // Typing into a page settles the screen on it: an agent that starts asking does not pull the
                        // keyboard away mid-command.
                        engaged = model::settle,
                        holdsKeyboard = {
                            terminalHoldsKeyboard = it
                            windowKeyboard?.held = it
                        },
                    )
                }
                if (pane.id in model.shownAsTerminal) {
                    terminalPage(pane, shown)
                } else {
                    PaneContent(
                        pane, shown,
                        agent = { session ->
                            // Another session in the same terminal is another chat, not this one's model.
                            key(session.ref) { AgentView(scope, session.ref, open, back, embedded = true) }
                        },
                        shell = { page, pageShown -> terminalPage(page, pageShown) },
                    )
                }
            }
        }
        WorkspaceScreenModel.Phase.WAITING -> WorkspaceWaitingView(back)
        WorkspaceScreenModel.Phase.NOT_FOUND -> WorkspaceMissingView(back)
        WorkspaceScreenModel.Phase.DISMISSED, WorkspaceScreenModel.Phase.MACHINE_REMOVED ->
            Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background))
    }
}

object WorkspaceView {
    /** What the screen says when the pane shown was closed on the Mac and the next chip shows. */
    fun paneClosedNotice(res: Resources): String = res.getString(R.string.workspace_pane_closed_on_mac)

    /** What the list says after the screen left because its workspace is gone; nothing when the user closed the
     *  workspace (or its last tab) here. */
    fun leavingNotice(closedHere: Boolean, res: Resources): String? =
        if (closedHere) null else res.getString(R.string.workspace_closed_on_mac)
}
