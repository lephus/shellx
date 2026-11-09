package com.shellx.app.ui.workspaces

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.shellx.app.SignedInScope
import com.shellx.app.ui.components.HomeTicks
import com.shellx.app.ui.components.rememberNowMs
import com.shellx.app.ui.nav.ShellXNavigator
import com.shellx.core.home.HomeFocus
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow

/** ＋ waiting for the Mac's answer and the last command's alert, kept across a recreated home (carry 3D-3): a
 *  rotation while a workspace is being made never lets a second ＋ through. */
internal class HomeProgress : ViewModel() {
    val creating = mutableStateOf(false)
    val alert = mutableStateOf<WorkspaceAlert?>(null)
}

/**
 * The home (routes `home` and `demo`, through SignedInView; `WorkspaceListView.swift`): [WorkspaceListScreen] fed by
 * [scope]. The hub gives each Mac's workspaces and the sessions of the reachable Macs, sorted by [HomeFocus] again at
 * each of [ticks] (every 30 s, ledger 6.2-7), so "just finished" and "ended" age out with the screen open; the decision
 * center gives what waits for the user. Sessions removed from this phone are in no group and no count.
 */
@Composable
fun WorkspaceListView(scope: SignedInScope, navigator: ShellXNavigator, ticks: Flow<Unit> = remember { HomeTicks.every() }) {
    val hub by scope.hub.state.collectAsStateWithLifecycle()
    val decisions by scope.decisions.state.collectAsStateWithLifecycle()
    val gone by scope.goneRemovals.state.collectAsStateWithLifecycle()
    val dismissed by scope.endedDismissals.dismissals.collectAsStateWithLifecycle()
    val notice by scope.listNotice.current.collectAsStateWithLifecycle()
    val nowMs = rememberNowMs(scope.clock, ticks)
    val progress = viewModel { HomeProgress() }
    var alert by progress.alert
    val creating by progress.creating

    val pending = remember(hub, decisions) { scope.decisions.visibleItems(hub.pendingItems) }
    val groups = remember(hub, gone) { WorkspaceListModel.groups(hub, gone.removals) }
    val focus = remember(hub, pending, dismissed, gone, nowMs) {
        HomeFocus.make(hub.reachableSessions, pending, hub.finishTimes, dismissed, gone.removals, nowMs)
    }
    val closable = remember(hub) { WorkspaceListModel.closableAgents(scope.hub) }
    val removable = remember(hub, gone) { WorkspaceListModel.removableAgents(hub, scope.goneRemovals) }
    val actions = remember(scope, navigator, progress) {
        WorkspaceListActions.make(scope, navigator, { progress.alert.value = it }, progress.creating)
    }

    WorkspaceListScreen(
        groups = groups,
        focus = focus,
        pending = pending,
        nowMs = nowMs,
        creating = creating,
        notice = notice,
        showsMachineNames = hub.machines.size > 1,
        closableAgents = closable,
        removableAgents = removable,
        actions = actions,
        alert = alert,
        onAlertDismissed = { alert = null },
    )

    LaunchedEffect(Unit) { scope.homeShown() }
    LaunchedEffect(hub.defaultMachineListedWorkspaces) { if (hub.defaultMachineListedWorkspaces) scope.workspacesListed() }
    LaunchedEffect(notice?.id) {
        val id = notice?.id ?: return@LaunchedEffect
        delay(ListNotice.DURATION)
        scope.listNotice.clear(id)
    }
}
