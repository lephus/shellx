package com.shellx.app.ui.pending

import androidx.compose.foundation.layout.Box
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.shellx.app.R
import com.shellx.core.link.MachineHub
import com.shellx.core.pairing.SheetPresence
import com.shellx.core.pending.DecisionCenter
import com.shellx.core.pending.DecisionStatus
import com.shellx.link.core.LinkDecision
import kotlinx.coroutines.launch

/**
 * The bottom sheet over the pending cards, fed by its route's model (`PendingSheetHost.swift`): it closes once its own
 * decision is taken, and tells TalkBack when the item was decided elsewhere meanwhile. While it is up it counts in
 * [sheets], so a pairing link opened meanwhile waits. Sends run in `hub.scope`, so they outlive the sheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PendingSheetHost(route: PendingRoute, hub: MachineHub, center: DecisionCenter, sheets: SheetPresence?, close: () -> Unit) {
    // Read so that the getters below are read again when any of the three changes.
    hub.state.collectAsStateWithLifecycle().value
    center.state.collectAsStateWithLifecycle().value
    route.model.state.collectAsStateWithLifecycle().value
    val state = PendingSheetState.of(route.model)
    val closing by rememberUpdatedState(close)
    LaunchedEffect(state.status) { if (state.status == DecisionStatus.Done) closing() }
    DisposableEffect(sheets) {
        sheets?.opened()
        onDispose { sheets?.closed() }
    }
    val send: (LinkDecision) -> Unit = { decision -> hub.scope.launch { route.model.send(decision) } }
    // The sheet's own state (page, picks, typed answers, feedback, the last decision) is kept with the page, not with
    // the bottom sheet's window: the window keeps its state apart, which a rebuilt screen does not give back (RF 3).
    val kept = rememberSaveableStateHolder()
    val item = route.model.opened ?: return
    ModalBottomSheet(
        onDismissRequest = close,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        kept.SaveableStateProvider("${route.kind}/${route.id.machineId}/${route.id.requestId}") {
            Box {
                when (route.kind) {
                    PendingRoute.Kind.QUESTION -> QuestionAnswerSheet(item, state, send, close)
                    PendingRoute.Kind.PLAN -> PlanReviewSheet(item, state, send, close)
                    PendingRoute.Kind.FULL_TEXT -> FullTextSheet(item.item, close)
                }
                Announcement(if (state.handledElsewhere) stringResource(R.string.pending_status_handled_elsewhere) else "")
            }
        }
    }
}
