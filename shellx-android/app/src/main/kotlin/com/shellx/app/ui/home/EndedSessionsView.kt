package com.shellx.app.ui.home

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.shellx.app.R
import com.shellx.app.SignedInScope
import com.shellx.app.ui.components.HomeTicks
import com.shellx.app.ui.components.rememberNowMs
import com.shellx.app.ui.nav.ShellXNavigator
import com.shellx.core.home.HomeFocus
import kotlinx.coroutines.flow.Flow

/**
 * Route `sessions/ended` (`EndedSessionsView.swift`): the agents that ended in the last 12 hours, newest end first,
 * from every Mac that can be reached. A session leaves the page 12 hours after it ended, also while the page is open
 * (sorted again at each of [ticks]), or when the user takes its card off (the trash or the swipe), which only hides it
 * on this phone until it ends again (`EndedDismissalStore`). A session removed from this phone is not on it either.
 */
@Composable
fun EndedSessionsView(scope: SignedInScope, navigator: ShellXNavigator, ticks: Flow<Unit> = remember { HomeTicks.every() }) {
    val hub by scope.hub.state.collectAsStateWithLifecycle()
    val dismissed by scope.endedDismissals.dismissals.collectAsStateWithLifecycle()
    val gone by scope.goneRemovals.state.collectAsStateWithLifecycle()
    val nowMs = rememberNowMs(scope.clock, ticks)
    val ended = remember(hub, dismissed, gone, nowMs) {
        HomeFocus.make(hub.reachableSessions, emptyList(), emptyMap(), dismissed, gone.removals, nowMs).ended
    }
    SessionListScreen(
        title = stringResource(R.string.ended_title),
        header = null,
        items = ended,
        kind = { FocusKind.ENDED },
        nowMs = nowMs,
        showsMachineName = hub.machines.size > 1,
        empty = R.string.ended_empty,
        openAgent = navigator::openAgent,
        back = navigator::back,
        remove = { scope.endedDismissals.dismiss(it.session) },
    )
}
