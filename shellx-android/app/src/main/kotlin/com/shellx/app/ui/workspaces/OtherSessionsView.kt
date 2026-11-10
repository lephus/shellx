package com.shellx.app.ui.workspaces

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.shellx.app.R
import com.shellx.app.SignedInScope
import com.shellx.app.ui.components.HomeTicks
import com.shellx.app.ui.components.rememberNowMs
import com.shellx.app.ui.home.SessionListScreen
import com.shellx.app.ui.nav.ShellXNavigator
import com.shellx.core.home.FocusItem
import com.shellx.core.home.SessionName
import kotlinx.coroutines.flow.Flow

/**
 * Route `sessions/other?machineId=…` (`OtherSessionsView.swift`): the live sessions of one Mac that no terminal of its
 * workspaces names (run over SSH, in a workspace since closed). Ended sessions are on the Ended page, and the ones
 * removed from this phone are on no list. A card opens its agent and offers no Close (`agent.close` reaches only an
 * agent whose terminal the Mac lists). A session an agent screen saw gone from its Mac this run swipes to "Remove from
 * This Phone". Each card's group follows the clock at each of [ticks].
 */
@Composable
fun OtherSessionsView(
    scope: SignedInScope,
    machineId: String,
    navigator: ShellXNavigator,
    ticks: Flow<Unit> = remember { HomeTicks.every() },
) {
    val hub by scope.hub.state.collectAsStateWithLifecycle()
    val gone by scope.goneRemovals.state.collectAsStateWithLifecycle()
    val nowMs = rememberNowMs(scope.clock, ticks)
    val sessions = remember(hub, gone, machineId) { OtherSessionsModel.sessions(hub, machineId, gone.removals) }
    val removable = remember(sessions, gone) { scope.goneRemovals.removable(sessions) }
    val items = remember(hub, sessions, machineId) {
        val names = SessionName.distinct(sessions)
        val finishTimes = hub.finishTimes[machineId].orEmpty()
        sessions.map { FocusItem(it, names[it.ref] ?: it.session.sessionId, finishedAtMs = finishTimes[it.session.sessionId]) }
    }
    SessionListScreen(
        title = stringResource(R.string.workspaces_other_title),
        // A Mac unpaired while the page is open leaves no empty heading.
        header = hub.machines.firstOrNull { it.id == machineId }?.name,
        items = items,
        kind = { OtherSessionsModel.kind(it.session.session, it.finishedAtMs, nowMs) },
        nowMs = nowMs,
        showsMachineName = false,
        empty = R.string.workspaces_other_empty,
        openAgent = navigator::openAgent,
        back = navigator::back,
        removableGone = removable,
        removeGone = { scope.goneRemovals.remove(it.session) },
    )
}
